import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    private let nlp = ExpenseNLP()

    func add(_ t: Transaction) { transactions.insert(t, at: 0) }
    func update(_ t: Transaction) { if let i = transactions.firstIndex(where: { $0.id == t.id }) { transactions[i] = t } }
    func delete(id: UUID) { transactions.removeAll { $0.id == id } }
    func deleteAtOffsets(_ offsets: IndexSet) { for i in offsets.sorted(by: >) { if transactions.indices.contains(i) { transactions.remove(at: i) } } }

    // ✅ 新增這個
    func addFromInput(_ raw: String) async {
        let tx = await nlp.parseOne(raw)
        add(tx)
    }
}

