import Foundation
#if canImport(FoundationModels)
import FoundationModels   // 先條件式 import，不會用到也不會報錯
#endif

/// 極簡 NLP：
/// - 自動「摘要關鍵字」（把多餘助詞/數字/量詞去掉）
/// - 嘗試抓金額
/// - 用關鍵字歸類到 TransactionCategory
@MainActor
final class ExpenseNLP {

    func parseOne(_ raw: String) async -> Transaction {
        let desc = Self.extractKeyword(from: raw)
        let amount = Self.detectAmount(in: raw) ?? 0
        let category = Self.detectCategory(in: raw)
        let date = Self.detectDate(in: raw) ?? Date()

        return Transaction(
            id: UUID(),
            description: desc.isEmpty ? raw : desc,
            amount: amount,
            date: date,
            category: category
        )
    }

    // MARK: - Keyword 摘要（移除助詞/數字/量詞/幣別）
    private static func extractKeyword(from s: String) -> String {
        var t = s

        // 常見贅字
        let fillers = [
            "我", "買了", "買", "花了", "用了", "繳了", "付了", "充了", "儲值了",
            "今天", "昨天", "前天", "上週", "上周", "上禮拜",
            "的", "了", "去", "到", "在", "跟", "和", "以及", "還有", "並"
        ]
        fillers.forEach { f in
            t = t.replacingOccurrences(of: f, with: " ")
        }

        // 金額/幣別（NT$ 120、120元、$80 等）
        let moneyPatterns = [
            #"(?i)(NT\$|TWD|USD|\$)\s*[0-9,]+(?:\.[0-9]+)?"#,
            #"[0-9,]+(?:\.[0-9]+)?\s*(元|塊|圓)"#
        ]
        moneyPatterns.forEach { p in
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }

        // 數量/單價（x2、2x、每杯 55、3 個…）
        let qtyPatterns = [
            #"(?i)(^|\s)x\s*[0-9]+(?:\.[0-9]+)?"#,
            #"(?i)[0-9]+(?:\.[0-9]+)?\s*x"#,
            #"(?i)每[^\s]{0,3}\s*[0-9,]+(?:\.[0-9]+)?"#,
            #"(?i)(([0-9]+(?:\.[0-9]+)?)|[一二兩三四五六七八九十半]+)\s*(顆|瓶|杯|份|包|盒|組|罐|個)"#
        ]
        qtyPatterns.forEach { p in
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }

        // 日期 token
        t = t.replacingOccurrences(of: #"\b20[0-9]{2}-[01][0-9]-[0-3][0-9]\b"#,
                                   with: " ", options: .regularExpression)

        // 特例合併
        t = t.replacingOccurrences(of: #"儲值\s*悠遊卡"#, with: "儲值悠遊卡", options: .regularExpression)
        t = t.replacingOccurrences(of: #"加值\s*悠遊卡"#, with: "加值悠遊卡", options: .regularExpression)

        // 只保留中文字母數字與空白
        t = t.replacingOccurrences(of: #"[^A-Za-z0-9\u4E00-\u9FFF\s]"#, with: " ",
                                   options: .regularExpression)

        // 壓縮空白
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
             .trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果還是太長，取前 12~16 字（避免列表過長）
        let maxLen = 16
        if t.count > maxLen {
            let end = t.index(t.startIndex, offsetBy: maxLen)
            return String(t[..<end])
        }
        return t
    }

    // MARK: - 金額偵測
    private static func detectAmount(in s: String) -> Double? {
        let patterns = [
            #"(?i)(?:NT\$|TWD|USD|\$)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)\s*(元|塊|圓)"#
        ]
        for p in patterns {
            if let r = s.range(of: p, options: .regularExpression) {
                let token = String(s[r])
                if let numRange = token.range(of: #"[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?"#,
                                              options: .regularExpression) {
                    let num = token[numRange].replacingOccurrences(of: ",", with: "")
                    if let v = Double(num) { return v }
                }
            }
        }
        return nil
    }

    // MARK: - 類別偵測
    private static func detectCategory(in s: String) -> TransactionCategory {
        let t = s.lowercased()
        let table: [(TransactionCategory, [String])] = [
            (.food, ["餐","早餐","午餐","晚餐","飲料","咖啡","超商","麵","飯","蛋糕","三明治","便當","星巴克","kfc","mcdonald"]),
            (.transport, ["捷運","公車","火車","高鐵","加油","uber","taxi","停車","客運","機票","悠遊卡","一卡通","儲值","加值"]),
            (.entertainment, ["電影","影城","遊戲","steam","netflix","spotify","演唱會","娛樂"]),
            (.shopping, ["蝦皮","momo","pchome","購物","衣服","鞋","3c","配件","商場"]),
            (.utility, ["水費","電費","瓦斯","網路","手機費","電信","瓦斯費","帳單","第四台"])
        ]
        for (cat, keys) in table {
            if keys.contains(where: { t.contains($0) }) { return cat }
        }
        return .other
    }

    // MARK: - 日期偵測（簡化：相對詞 or ISO 8601）
    private static func detectDate(in s: String) -> Date? {
        let lower = s.lowercased()
        let cal = Calendar(identifier: .gregorian)
        let now = Date()

        if lower.contains("今天") || lower.contains("today") { return now }
        if lower.contains("昨天") || lower.contains("昨日") { return cal.date(byAdding: .day, value: -1, to: now) }
        if lower.contains("前天") { return cal.date(byAdding: .day, value: -2, to: now) }

        if let r = s.range(of: #"\b(20[0-9]{2})-(0[1-9]|1[0-2])-(0[0-9]|[12][0-9]|3[01])\b"#,
                           options: .regularExpression) {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            return f.date(from: String(s[r]))
        }
        return nil
    }
}

