import SwiftUI

struct InputBar: View {
    @Binding var text: String
    var isRecording: Bool
    var onSubmit: () -> Void
    var onMicTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 麥克風
            Button(action: onMicTap) {
                Image(systemName: isRecording ? "waveform.circle.fill" : "mic.circle")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }

            // 文字輸入
            TextField("例如：超商咖啡 2 杯 每杯 55", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit {
                    onSubmit()
                }

            // 送出
            Button {
                onSubmit()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

