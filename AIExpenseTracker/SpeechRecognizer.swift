import Foundation
import AVFoundation
import Speech
import Combine

/// 簡單的語音辨識封裝（支援 zh-TW，模擬器有後備 format，避免崩潰）
final class SpeechRecognizer: NSObject, ObservableObject {

    // MARK: - Published
    @Published var transcript: String = ""

    // MARK: - Private
    private let audioEngine = AVAudioEngine()
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))

    private(set) var isAuthorized = false

    // MARK: - Lifecycle
    override init() {
        super.init()
        requestAuthorization()
    }

    deinit {
        stopTranscribing()
    }

    // MARK: - Public API

    /// 提供給 ContentView 呼叫：若尚未授權，發起權限要求並回傳結果
    func requestAuthorizationIfNeeded() async -> Bool {
        if isAuthorized { return true }
        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else {
                    DispatchQueue.main.async {
                        self.isAuthorized = false
                        cont.resume(returning: false)
                    }
                    return
                }
                SFSpeechRecognizer.requestAuthorization { status in
                    let ok = (status == .authorized)
                    DispatchQueue.main.async {
                        self.isAuthorized = ok
                        cont.resume(returning: ok)
                    }
                }
            }
        }
    }

    /// 清空逐字稿
    func resetTranscript() {
        transcript = ""
    }

    /// 啟動辨識
    func startTranscribing() {
        guard isAuthorized else { return }

        // 先確保乾淨狀態
        stopTranscribing()

        // 1) Audio Session
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setPreferredSampleRate(44100)
        try? session.setPreferredIOBufferDuration(0.02)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        // 2) Recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        audioRequest = request

        guard let recognizer = recognizer, recognizer.isAvailable else {
            // 無可用辨識器（離線/網路），直接返回
            return
        }

        // 3) 建立 recognitionTask
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self.stopTranscribing()
            }
        }

        // 4) 安裝 tap（模擬器可能拿到 0Hz，要提供後備）
        let inputNode = audioEngine.inputNode
        var format = inputNode.outputFormat(forBus: 0)
        if format.sampleRate == 0 || format.channelCount == 0 {
            // 後備：44100Hz / mono / float
            format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 44100,
                                   channels: 1,
                                   interleaved: false)!
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.audioRequest?.append(buffer)
        }

        // 5) 開始錄音
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            // 在模擬器或無麥克風時可能失敗：優雅收尾
            inputNode.removeTap(onBus: 0)
            audioRequest?.endAudio()
            recognitionTask?.cancel()
            audioRequest = nil
            recognitionTask = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// 停止辨識並釋放資源
    func stopTranscribing() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioRequest?.endAudio()
        recognitionTask?.cancel()

        audioRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Permission（內部預先要求）
    private func requestAuthorization() {
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else {
                DispatchQueue.main.async { self.isAuthorized = false }
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.isAuthorized = (status == .authorized)
                }
            }
        }
    }
}

