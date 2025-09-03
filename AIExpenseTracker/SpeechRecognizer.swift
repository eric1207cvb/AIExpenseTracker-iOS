// SpeechRecognizer.swift

import Foundation
import Speech
import AVFoundation
import Combine

class SpeechRecognizer: ObservableObject {

    @Published var transcript: String = ""

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?

    init() {
        // 台灣繁中辨識器
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hant-TW"))

        // ⚠️ 用 Task{}（承襲呼叫端 actor = MainActor），不要用 Task.detached{}
        Task { [weak self] in
            guard let self else { return }
            do {
                // 在 MainActor 環境下，直接安全地讀取 self.recognizer
                guard self.recognizer != nil else {
                    throw RecognizerError.nilRecognizer
                }
                guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
                    throw RecognizerError.notAuthorizedToRecognize
                }
                guard await AVAudioSession.sharedInstance().hasPermissionToRecord() else {
                    throw RecognizerError.notPermittedToRecord
                }
            } catch {
                // 切回主執行緒更新 UI
                await MainActor.run { self.speakError(error) }
            }
        }
    }

    deinit {
        reset()
    }

    // MARK: - Public

    func toggleTranscribing() {
        if task != nil {
            stopTranscribing()
        } else {
            transcribe()
        }
    }

    func stopTranscribing() {
        reset()
    }

    // MARK: - Core

    private func transcribe() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            // 在非 async 環境，用 Task{ @MainActor in ... } 切回主執行緒
            Task { @MainActor in self.speakError(RecognizerError.recognizerIsUnavailable) }
            return
        }

        do {
            let (audioEngine, request) = try Self.prepareEngine()
            self.audioEngine = audioEngine
            self.request = request

            self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                let receivedFinalResult = result?.isFinal ?? false
                let receivedError = (error as NSError?) != nil

                if let result = result {
                    Task { @MainActor in self.speak(result.bestTranscription.formattedString) }
                }

                if receivedFinalResult || receivedError {
                    self.request?.endAudio()
                    self.audioEngine?.stop()
                    self.audioEngine?.inputNode.removeTap(onBus: 0)
                    self.cleanupRecognitionKeepSession()
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        Self.deactivateAudioSession()
                    }
                }
            }
        } catch {
            reset()
            Task { @MainActor in self.speakError(error) }
        }
    }

    // MARK: - Reset / Cleanup

    private func reset() {
        task?.cancel()
        request?.endAudio()

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()

        cleanupRecognitionKeepSession()
        Self.deactivateAudioSession()
    }

    private func cleanupRecognitionKeepSession() {
        task = nil
        request = nil
        audioEngine = nil
    }

    // MARK: - Engine Setup

    private static func prepareEngine() throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest) {
        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // request.requiresOnDeviceRecognition = true // 視裝置支援情況

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        return (audioEngine, request)
    }

    private static func deactivateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Output (UI updates on MainActor)

    @MainActor
    private func speak(_ message: String) {
        transcript = message
    }

    @MainActor
    private func speakError(_ error: Error) {
        var errorMessage = ""
        if let error = error as? RecognizerError {
            errorMessage += error.message
        } else {
            errorMessage += error.localizedDescription
        }
        transcript = "<< \(errorMessage) >>"
    }

    // MARK: - Error

    enum RecognizerError: Error {
        case nilRecognizer
        case notAuthorizedToRecognize
        case notPermittedToRecord
        case recognizerIsUnavailable

        var message: String {
            switch self {
            case .nilRecognizer: return "無法初始化辨識器"
            case .notAuthorizedToRecognize: return "未授權語音辨識"
            case .notPermittedToRecord: return "未授權麥克風"
            case .recognizerIsUnavailable: return "辨識器無法使用"
            }
        }
    }
}

// MARK: - Permissions Helpers

extension AVAudioSession {
    func hasPermissionToRecord() async -> Bool {
        if #available(iOS 17.0, *) {
            // ✅ iOS 17+ 正確用法：類方法，不是 shared 實例方法
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { authorized in
                    continuation.resume(returning: authorized)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                self.requestRecordPermission { authorized in
                    continuation.resume(returning: authorized)
                }
            }
        }
    }
}

extension SFSpeechRecognizer {
    static func hasAuthorizationToRecognize() async -> Bool {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

