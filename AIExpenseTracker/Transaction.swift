import Foundation

enum TransactionCategory: String, CaseIterable, Codable, Hashable {
    case food, transport, entertainment, shopping, utility, other

    var localizedName: String {
        switch self {
        case .food: return "餐飲"
        case .transport: return "交通"
        case .entertainment: return "娛樂"
        case .shopping: return "購物"
        case .utility: return "帳單"
        case .other: return "其他"
        }
    }

    var sfSymbol: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "train.side.front.car"
        case .entertainment: return "gamecontroller"
        case .shopping: return "cart"
        case .utility: return "bolt"
        case .other: return "questionmark.circle"
        }
    }
}

struct Transaction: Identifiable, Hashable, Codable {
    let id: UUID
    var description: String
    var amount: Double
    var date: Date
    var category: TransactionCategory

    static let sample = Transaction(id: UUID(),
                                    description: "蛋糕",
                                    amount: 500,
                                    date: Date(),
                                    category: .food)
}

