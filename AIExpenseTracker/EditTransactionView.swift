import SwiftUI

struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Transaction
    let onSave: (Transaction) -> Void

    init(transaction: Transaction, onSave: @escaping (Transaction) -> Void) {
        self._draft = State(initialValue: transaction)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("品項") {
                    TextField("品項", text: $draft.description)
                }

                Section("金額") {
                    TextField("金額", value: $draft.amount, format: .number)
                        .keyboardType(.decimalPad)
                }

                Section("日期") {
                    DatePicker("日期", selection: $draft.date, displayedComponents: .date)
                }

                Section("分類") {
                    Picker("分類", selection: $draft.category) {
                        ForEach(TransactionCategory.allCases, id: \.self) { cat in
                            Text(cat.localizedName).tag(cat)
                        }
                    }
                }
            }
            .navigationTitle("編輯記錄")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

