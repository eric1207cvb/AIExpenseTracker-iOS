import Foundation
import Combine

final class HomeViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []

    func add(_ t: Transaction) {
        transactions.insert(t, at: 0)
    }

    func update(_ t: Transaction) {
        if let i = transactions.firstIndex(where: { $0.id == t.id }) {
            transactions[i] = t
        }
    }

    func delete(id: UUID) {
        transactions.removeAll { $0.id == id }
    }

    /// 給 `.onDelete` 用：不依賴 SwiftUI 的 remove(atOffsets:)
    func deleteAtOffsets(_ offsets: IndexSet) {
        // 由大到小刪，避免 index 移動
        for index in offsets.sorted(by: >) {
            guard transactions.indices.contains(index) else { continue }
            transactions.remove(at: index)
        }
    }
}

