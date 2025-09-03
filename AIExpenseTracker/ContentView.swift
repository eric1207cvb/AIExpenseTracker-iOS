import SwiftUI

struct ContentView: View {
    // 資料
    @StateObject private var vm = HomeViewModel()
    private let ai = AppleIntelligenceService()

    // 輸入區狀態
    @State private var inputText: String = ""
    @State private var isRecording = false
    @StateObject private var speech = SpeechRecognizer()   // 需用前面提供的 SpeechRecognizer.swift

    // 日期/金額顯示
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        return f
    }()

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {

                // 清單
                List {
                    Section(header: Text("花費").font(.system(size: 32, weight: .heavy))) {
                        ForEach(vm.transactions) { t in
                            HStack(spacing: 12) {
                                Image(systemName: t.category.sfSymbol)
                                    .font(.system(size: 24, weight: .medium))
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t.description)
                                        .font(.system(size: 20, weight: .semibold))
                                        .lineLimit(1)
                                    Text(dateFormatter.string(from: t.date))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(currencyFormatter.string(from: NSNumber(value: t.amount)) ?? "—")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete(perform: vm.deleteAtOffsets)
                    }
                }
                .listStyle(.insetGrouped)

                // 下方輸入列（獨立在 InputBar.swift）
                InputBar(
                    text: $inputText,
                    isRecording: isRecording,
                    onSubmit: { submitCurrentInput() },
                    onMicTap: { handleMicTap() }
                )
                .padding(.horizontal)
                .onChange(of: speech.transcript) { newValue in
                    // 語音→文字即時回填輸入框
                    inputText = newValue
                }
                .task {
                    // 進畫面先請權限（避免按下去才跳）
                    _ = await speech.requestAuthorizationIfNeeded()
                }
            }
            .navigationBarHidden(true)
        }
        .onDisappear {
            // 離開畫面安全收尾
            if isRecording { speech.stopTranscribing(); isRecording = false }
        }
    }

    // MARK: - Actions

    /// 點送出：呼叫 FM 分析 → 轉成多筆 Transaction → 插入列表
    private func submitCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task { @MainActor in
            do {
                let items = try await ai.analyzeExpense(userInput: text)
                items.forEach { vm.add($0) }
            } catch {
                // 萬一 FM 也失敗，這裡可視情況加上本地 fallback
                print("Analyze failed: \(error)")
            }
            inputText = ""
            if isRecording {
                speech.stopTranscribing()
                isRecording = false
            }
        }
    }

    /// 麥克風按鈕：開始/停止錄音 + 權限處理
    private func handleMicTap() {
        if isRecording {
            speech.stopTranscribing()
            isRecording = false
            return
        }

        Task { @MainActor in
            let granted = await speech.requestAuthorizationIfNeeded()
            guard granted else { return }
            speech.resetTranscript()
            speech.startTranscribing()
            isRecording = true
        }
    }
}

