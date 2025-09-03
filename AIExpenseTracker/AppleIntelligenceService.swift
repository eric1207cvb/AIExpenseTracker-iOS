//  AppleIntelligenceService.swift
//  AIExpenseTracker

import Foundation
import CoreML

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AppleIntelligenceService {

    // 如果你沒有自訓 CoreML 模型，保持 nil
    private let MODEL_RESOURCE_NAME: String? = nil
    private let fmCoreML: MLModel?

    init() {
        if let name = MODEL_RESOURCE_NAME,
           let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            do {
                let cfg = MLModelConfiguration()
                self.fmCoreML = try MLModel(contentsOf: url, configuration: cfg)
            } catch {
                print("⚠️ CoreML model load failed: \(error)")
                self.fmCoreML = nil
            }
        } else {
            self.fmCoreML = nil
        }
    }

    // MARK: - Public

    func analyzeExpense(userInput: String) async throws -> [Transaction] {
        // 1) Apple Intelligence（FoundationModels）
        if let fm = try? await analyzeWithFoundationModels(userInput: userInput), !fm.isEmpty {
            return fm
        }
        // 2)（可選）CoreML 自訓模型
        if let core = fmCoreML {
            if let items = try? analyzeWithCoreML(model: core, userInput: userInput), !items.isEmpty {
                return items
            }
        }
        // 3) 規則 fallback
        return try fallbackParseMany(userInput: userInput)
    }

    // MARK: - Foundation Models（Apple Intelligence）

#if canImport(FoundationModels)
private func analyzeWithFoundationModels(userInput: String) async throws -> [Transaction] {
    let model = SystemLanguageModel.default
    guard model.isAvailable else { return [] }

    let df = ISO8601DateFormatter()
    df.formatOptions = [.withFullDate]
    let today = df.string(from: Date())
    let cats = TransactionCategory.allCases.map { $0.rawValue }.joined(separator: ", ")

    let instructions = """
    你是記帳助理。請把中文/中英夾雜輸入解析成 JSON 陣列，每個元素必須含：
    - "description": String（品項，請去除金額與量詞）
    - "amount": Double（總金額，若出現「數量×單價」請先相乘）
    - "category": String（必須是：\(cats)）
    - "date": String（YYYY-MM-DD；相對日期請以今天 \(today) 換算）
    規範：
    - 一句可能包含多筆，請拆成多個物件。
    - 僅輸出 JSON（無任何前後註解、標記、說明文字）。
    """

    let session = LanguageModelSession(instructions: instructions)

    var options = GenerationOptions()
    options.temperature = 0.1

    let prompt = """
    使用者輸入：「\(userInput)」
    請輸出 JSON 陣列。
    """

    // ✅ 修正：參數順序 + 取 content
    let resp = try await session.respond(to: prompt, generating: String.self, options: options)
    let raw = resp.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

    let cleaned: String = raw
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

    if let arr = decodeTransactionsArray(from: cleaned) { return arr }
    if let one = decodeTransactionObject(from: cleaned) { return [one] }
    return []
}
#endif
    
    // MARK: - CoreML（僅當你真的有自訓模型）

    private func analyzeWithCoreML(model: MLModel, userInput: String) throws -> [Transaction] {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        let today = df.string(from: Date())
        let categories = TransactionCategory.allCases.map { $0.rawValue }.joined(separator: ", ")

        let prompt = """
        你是記帳助理。請把以下輸入解析成「JSON 陣列」，每個元素必須含：
        - "description": String（品項，請去除金額與量詞）
        - "amount": Double（總金額，若出現「數量×單價」請先相乘）
        - "category": String（必須是：\(categories)）
        - "date": String（YYYY-MM-DD；相對日期請以今天 \(today) 換算）
        規範：
        - 一句可能包含多筆，請拆成多個物件。
        - 只輸出 JSON 陣列，前後不得有任何文字或標記。
        使用者輸入：「\(userInput)」
        """

        // CoreML prediction 是同步 API
        let out1 = try? model.prediction(from: try MLDictionaryFeatureProvider(dictionary: ["prompt": prompt]))
        let raw = out1?.featureValue(for: "text")?.stringValue
            ?? out1?.featureValue(for: "generatedText")?.stringValue
            ?? out1?.featureValue(for: "generated_text")?.stringValue
            ?? {
                let out2 = try? model.prediction(from: try MLDictionaryFeatureProvider(dictionary: ["text": prompt]))
                return out2?.featureValue(for: "text")?.stringValue
                    ?? out2?.featureValue(for: "generatedText")?.stringValue
                    ?? out2?.featureValue(for: "generated_text")?.stringValue
            }() ?? ""

        let cleaned: String = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if let arr = decodeTransactionsArray(from: cleaned) { return arr }
        if let one = decodeTransactionObject(from: cleaned) { return [one] }
        return []
    }

    // MARK: - JSON 解析（支援 yyyy-MM-dd 與 ISO8601）

    private func decodeTransactionsArray(from json: String) -> [Transaction]? {
        guard let data = json.data(using: .utf8) else { return nil }
        struct Decoded: Decodable {
            var description: String
            var amount: Double
            var category: TransactionCategory
            var date: Date
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom(Self.decodeFlexibleDate)
        guard let items = try? dec.decode([Decoded].self, from: data) else { return nil }
        return items.map {
            Transaction(id: UUID(),
                        description: cleanDescription($0.description),
                        amount: $0.amount,
                        date: $0.date,
                        category: $0.category)
        }
    }

    private func decodeTransactionObject(from json: String) -> Transaction? {
        guard let data = json.data(using: .utf8) else { return nil }
        struct Decoded: Decodable {
            var description: String
            var amount: Double
            var category: TransactionCategory
            var date: Date
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom(Self.decodeFlexibleDate)
        guard let d = try? dec.decode(Decoded.self, from: data) else { return nil }
        return Transaction(id: UUID(),
                           description: cleanDescription(d.description),
                           amount: d.amount,
                           date: d.date,
                           category: d.category)
    }

    /// 由於整個型別是 @MainActor，這裡用 `nonisolated` 讓同步 JSONDecoder 可直接呼叫。
    nonisolated private static func decodeFlexibleDate(_ dec: Decoder) throws -> Date {
        let c = try dec.singleValueContainer()
        let s = try c.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)

        // yyyy-MM-dd 快速判斷（用 index，不用 Int 下標）
        if s.count == 10 {
            let i4 = s.index(s.startIndex, offsetBy: 4)
            let i7 = s.index(s.startIndex, offsetBy: 7)
            if s[i4] == "-", s[i7] == "-" {
                let f = DateFormatter()
                f.calendar = Calendar(identifier: .gregorian)
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "yyyy-MM-dd"
                if let d = f.date(from: s) { return d }
            }
        }

        // ISO8601（先試含毫秒，再試不含）
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported date format: \(s)")
    }

    // MARK: - Fallback（你的規則解析，幾乎原封不動）

    private func fallbackParseMany(userInput: String) throws -> [Transaction] {
        let normalized = userInput
            .replacingOccurrences(of: "和", with: "、")
            .replacingOccurrences(of: "及", with: "、")
            .replacingOccurrences(of: "與", with: "、")
            .replacingOccurrences(of: "並", with: "、")
            .replacingOccurrences(of: "加上", with: "、")
            .replacingOccurrences(of: "加", with: "、")
            .replacingOccurrences(of: "跟", with: "、")
            .replacingOccurrences(of: "還有", with: "、")
            .replacingOccurrences(of: "以及", with: "、")
            .replacingOccurrences(of: "另外", with: "、")
            .replacingOccurrences(of: "再", with: "、")

        let parts = normalized
            .components(separatedBy: CharacterSet(charactersIn: "，、,。；;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.count <= 1 {
            return [try fallbackParseOne(userInput: userInput)]
        }

        var results: [Transaction] = []
        for p in parts {
            results.append(try fallbackParseOne(userInput: p))
        }
        return results.filter { !$0.description.isEmpty || $0.amount > 0 }
    }

    private func fallbackParseOne(userInput: String) throws -> Transaction {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let (qtyOpt, unitOpt, explicitTotalOpt) = detectQtyUnitPrice(in: text)
        let parsedAmount = matchAmount(in: text)

        var amount: Double = explicitTotalOpt ?? 0.0
        if amount == 0, let q = qtyOpt, let u = unitOpt { amount = Double(q) * Double(u) }
        if amount == 0, let a = parsedAmount, a > 0 { amount = a }

        let date = resolveDate(in: text)
        let category = resolveCategory(in: text)
        let description = resolveDescriptionRemovingQty(in: text, amount: amount, qty: qtyOpt, unitPrice: unitOpt)

        return Transaction(id: UUID(),
                           description: description,
                           amount: amount,
                           date: date,
                           category: category)
    }

    // MARK: - 金額 / 數量 / 單價

    private func detectQtyUnitPrice(in text: String) -> (qty: Double?, unitPrice: Double?, total: Double?) {
        let t = text.replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "＊", with: "*")
            .replacingOccurrences(of: "×", with: "x")
            .lowercased()

        if let totalByKeyword = matchAmount(after: ["合計","總計","總共","共"], in: t) {
            return (qty: parseQuantity(in: t), unitPrice: parseUnitPrice(in: t), total: totalByKeyword)
        }

        let amounts = allAmounts(in: t)
        let q = parseQuantity(in: t)
        let u = parseUnitPrice(in: t)

        if let q, let u { return (qty: q, unitPrice: u, total: nil) }
        if let q, amounts.count == 1, let only = amounts.first { return (qty: q, unitPrice: only, total: nil) }
        if let q, let first = amounts.first { return (qty: q, unitPrice: nil, total: first) }
        return (qty: q, unitPrice: u, total: nil)
    }

    private func allAmounts(in text: String) -> [Double] {
        let pattern = #"(?i)(?:NT\$|NTD|TWD)?\s*\$?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)\s*(?:元|塊|NTD|TWD)?"#
        var result: [Double] = []
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = NSRange(text.startIndex..., in: text)
            for m in regex.matches(in: text, range: ns) {
                guard m.numberOfRanges >= 2, let r = Range(m.range(at: 1), in: text) else { continue }
                let num = text[r].replacingOccurrences(of: ",", with: "")
                if let v = Double(num) { result.append(v) }
            }
        }
        return result
    }

    private func matchAmount(in text: String) -> Double? {
        let s = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "．", with: ".")

        let patterns = [
            #"(?i)(?:NT\$|TWD|USD|\$|＄)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)\s*(?:元|圓|塊|塊錢|NTD|TWD)"#,
            #"(?<![0-9])([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?)(?![0-9])"#
        ]

        for p in patterns {
            if let r = s.range(of: p, options: .regularExpression) {
                if let m = try? NSRegularExpression(pattern: p).firstMatch(in: s, range: NSRange(r, in: s)),
                   m.numberOfRanges >= 2,
                   let gr = Range(m.range(at: 1), in: s) {
                    let num = s[gr].replacingOccurrences(of: ",", with: "")
                    if let v = Double(num) { return v }
                } else {
                    let token = String(s[r])
                    let cleaned = token.replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
                        .replacingOccurrences(of: ",", with: "")
                    if let v = Double(cleaned) { return v }
                }
            }
        }
        return nil
    }

    private func matchAmount(after keywords: [String], in text: String) -> Double? {
        let joined = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "(?:\(joined))\\s*(?:NT\\$|NTD|TWD|\\$)?\\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\\.[0-9]+)?|[0-9]+(?:\\.[0-9]+)?)\\s*(?:元|塊|NTD|TWD)?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let ns = NSRange(text.startIndex..., in: text)
            if let m = regex.firstMatch(in: text, range: ns), m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: text) {
                let num = text[r].replacingOccurrences(of: ",", with: "")
                return Double(num)
            }
        }
        return nil
    }

    private func parseQuantity(in text: String) -> Double? {
        if let r = text.range(of: #"(?:^|\s)x\s*([0-9]+(?:\.[0-9]+)?)"#, options: .regularExpression) {
            let n = String(text[r]).replacingOccurrences(of: #"[^0-9\.]"#, with: "", options: .regularExpression)
            if let v = Double(n) { return v }
        }
        if let r = text.range(of: #"([0-9]+(?:\.[0-9]+)?)\s*x"#, options: .regularExpression) {
            let n = String(text[r]).replacingOccurrences(of: #"[^0-9\.]"#, with: "", options: .regularExpression)
            if let v = Double(n) { return v }
        }
        if let r = text.range(of: #"((?:[0-9]+(?:\.[0-9]+)?)|[一二兩三四五六七八九十半]+)\s*(?:顆|瓶|杯|份|包|盒|組|罐|個)"#, options: .regularExpression) {
            let token = String(text[r])
            if let num = token.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) {
                return Double(token[num])
            }
            let cn = token.replacingOccurrences(of: #"[^一二兩三四五六七八九十半]"#, with: "", options: .regularExpression)
            if cn == "半" { return 0.5 }
            return Double(cn2int(cn))
        }
        return nil
    }

    private func parseUnitPrice(in text: String) -> Double? {
        if let r = text.range(of: #"每[^\s]{0,3}\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)"#, options: .regularExpression) {
            let n = String(text[r]).replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: #"[^0-9\.]"#, with: "", options: .regularExpression)
            return Double(n)
        }
        if parseQuantity(in: text) != nil {
            if let r = text.range(of: #"(單價|一[^\s]{0,3})\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)"#, options: .regularExpression) {
                let s = String(text[r])
                if let m = try? NSRegularExpression(pattern: #"(?:單價|一[^\s]{0,3})\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)"#)
                    .firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                   let gr = Range(m.range(at: 1), in: s) {
                    let n = s[gr].replacingOccurrences(of: ",", with: "")
                    return Double(n)
                }
            }
        }
        return nil
    }

    private func cn2int(_ s: String) -> Int {
        let map: [Character:Int] = ["零":0,"一":1,"二":2,"兩":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
        if s == "十" { return 10 }
        if s.hasPrefix("十") {
            let tail = s.dropFirst()
            let ones = tail.first.flatMap { map[$0] } ?? 0
            return 10 + ones
        }
        if let tenChar = s.first, let tens = map[tenChar], s.contains("十") {
            let parts = s.split(separator: "十", omittingEmptySubsequences: false)
            let ones = (parts.count > 1 && !parts[1].isEmpty) ? (map[parts[1].first!] ?? 0) : 0
            return tens * 10 + ones
        }
        return map[s.first ?? "零"] ?? 0
    }

    // MARK: - 日期 / 類別 / 描述

    private func resolveDate(in text: String) -> Date {
        let lower = text.lowercased()
        let cal = Calendar(identifier: .gregorian)
        let now = Date()

        if lower.contains("前天") { return cal.date(byAdding: .day, value: -2, to: now) ?? now }
        if lower.contains("昨天") || lower.contains("昨日") { return cal.date(byAdding: .day, value: -1, to: now) ?? now }
        if lower.contains("today") || lower.contains("今天") { return now }

        if let r = text.range(of: #"(上(一|個)?\s*(週|周|星期|禮拜))\s*[一二三四五六日天]"#, options: .regularExpression) {
            let matched = String(text[r])
            if let c = matched.last, let wd = weekdayNumber(fromChinese: c) {
                return dateForLastWeek(weekday: wd)
            }
        }

        if let r = text.range(of: #"\b(20[0-9]{2})-(0[1-9]|1[0-2])-(0[0-9]|[12][0-9]|3[01])\b"#, options: .regularExpression) {
            let s = String(text[r])
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: s) { return d }
        }
        return now
    }

    private func weekdayNumber(fromChinese c: Character) -> Int? {
        switch c {
        case "日", "天": return 1
        case "一": return 2
        case "二": return 3
        case "三": return 4
        case "四": return 5
        case "五": return 6
        case "六": return 7
        default: return nil
        }
    }

    private func dateForLastWeek(weekday: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday first
        let now = Date()
        guard let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart),
              let target = cal.date(bySetting: .weekday, value: weekday, of: lastWeekStart) else {
            return now
        }
        return target
    }

    private func resolveCategory(in text: String) -> TransactionCategory {
        let t = text.lowercased()
        let mapping: [(TransactionCategory, [String])] = [
            (.food, ["餐","便當","早餐","午餐","晚餐","飲料","咖啡","超商","麵","飯",
                     "starbucks","麥當勞","mcdonald","kfc","鮮奶","牛奶","蛋","茶葉蛋","蛋糕","蘋果"]),
            (.transport, ["捷運","公車","火車","高鐵","加油","uber","taxi","停車","客運","機票",
                          "悠遊卡","一卡通","儲值","加值"]),
            (.entertainment, ["電影","影城","遊戲","steam","netflix","spotify","演唱會","娛樂"]),
            (.shopping, ["蝦皮","momo","pchome","購物","衣服","鞋","3c","配件","商場"]),
            (.utility, ["水費","電費","瓦斯","網路","手機費","電信","瓦斯費","帳單","第四台"])
        ]
        for (cat, keys) in mapping where keys.contains(where: { t.contains($0) }) {
            return cat
        }
        return .other
    }

    private func resolveDescriptionRemovingQty(in text: String, amount: Double?, qty: Double?, unitPrice: Double?) -> String {
        var s = text
        let amountTokenPatterns = [
            #"(?i)(?:合計|總計|總共|共)\s*\$?\s*[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?\s*(?:元|塊|NTD|TWD)?"#,
            #"(?i)(?:NT\$|NTD|TWD)?\s*\$?\s*[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?\s*(?:元|塊|NTD|TWD)?"#,
            #"(?i)\$?\s*[0-9]+(?:\.[0-9]+)?\s*(?:元|塊)?"#
        ]
        for p in amountTokenPatterns { s = s.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        s = s.replacingOccurrences(of: #"(?i)(NT\$|NTD|TWD|\$)"#, with: "", options: .regularExpression)

        let qtyUnitPatterns = [
            #"(?i)(?:^|\s)x\s*[0-9]+(?:\.[0-9]+)?"#,
            #"(?i)[0-9]+(?:\.[0-9]+)?\s*x"#,
            #"(?i)每[^\s]{0,3}\s*[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?"#,
            #"(?i)(?:單價|一[^\s]{0,3})\s*[0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?"#,
            #"(?i)((?:[0-9]+(?:\.[0-9]+)?)|[一二兩三四五六七八九十半]+)\s*(?:顆|瓶|杯|份|包|盒|組|罐|個)"#
        ]
        for p in qtyUnitPatterns { s = s.replacingOccurrences(of: p, with: "", options: .regularExpression) }

        s = s.replacingOccurrences(of: #"到\s*([^\s]{1,8}?)(裡|內)"#, with: " $1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(顆|瓶|杯|份|包|盒|組|罐|個)\s*的"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b的\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(跟|加|以及|還有|並)"#, with: " ", options: .regularExpression)

        ["今天","昨日","昨天","前天","today"].forEach { s = s.replacingOccurrences(of: $0, with: "") }

        s = s.replacingOccurrences(of: #"[，,\.。]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if s.hasPrefix("的") { s.removeFirst() }
        s = s.replacingOccurrences(of: #"儲值\s+悠遊卡"#, with: "儲值悠遊卡", options: .regularExpression)
            .replacingOccurrences(of: #"加值\s+悠遊卡"#, with: "加值悠遊卡", options: .regularExpression)
        return s.isEmpty ? text : s
    }

    private func cleanDescription(_ s: String) -> String {
        var t = s
        let patterns = [
            #"(?i)(?:NT\$|NTD|TWD|\$)\s*[0-9,\.]+"#,
            #"[0-9,\.]+\s*(?:元|塊)"#,
            #"(?i)(?:^|\s)x\s*[0-9]+(?:\.[0-9]+)?"#,
            #"(?i)[0-9]+(?:\.[0-9]+)?\s*x"#,
            #"(?i)每[^\s]{0,3}\s*[0-9,\.]+"#,
            #"(顆|瓶|杯|份|包|盒|組|罐|個)\s*的"#
        ]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        t = t.replacingOccurrences(of: #"\b的\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[，,\.。]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return t.isEmpty ? s : t
    }

    // MARK: - 其它

    private func chineseNumberToDouble(_ cn: String) -> Double? {
        let s = cn.trimmingCharacters(in: CharacterSet.whitespaces)
        if s.isEmpty { return nil }
        if s == "半" { return 0.5 }
        let map: [Character:Int] = ["零":0,"〇":0,"一":1,"二":2,"兩":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
        if s.count == 1, let v = map[s.first!] { return Double(v) }
        if s == "十" { return 10 }
        if s.hasPrefix("十") {
            let tail = s.dropFirst()
            let ones = tail.first.flatMap { map[$0] } ?? 0
            return Double(10 + ones)
        }
        if let tenChar = s.first, let tens = map[tenChar], s.contains("十") {
            let parts = s.split(separator: "十", omittingEmptySubsequences: false)
            let ones = (parts.count > 1 && !parts[1].isEmpty) ? (map[parts[1].first!] ?? 0) : 0
            return Double(tens * 10 + ones)
        }
        return nil
    }
}

