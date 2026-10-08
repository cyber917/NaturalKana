import Foundation

public struct PersonalLexiconEntry: Codable, Equatable, Sendable, Identifiable {
    public var term: String
    public var reading: String
    public var meaning: String
    public var example: String
    public var note: String
    public var source: String
    public var id: String { TextNormalization.nfkc(term).lowercased() }
    public init(term: String, reading: String = "", meaning: String, example: String = "", note: String = "", source: String = "") {
        self.term = term; self.reading = reading; self.meaning = meaning; self.example = example; self.note = note; self.source = source
    }
    enum CodingKeys: String, CodingKey { case term, reading, meaning, example, note, source }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term); meaning = try c.decode(String.self, forKey: .meaning)
        reading = try c.decodeIfPresent(String.self, forKey: .reading) ?? ""
        example = try c.decodeIfPresent(String.self, forKey: .example) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
    }
}
public enum PersonalLexiconError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
public enum PersonalLexicon {
    public static let template = "term\treading\tmeaning\texample\tnote\tsource\n"
    public static func parse(_ data: Data, json: Bool) throws -> [PersonalLexiconEntry] {
        guard data.count <= 1_000_000, var text = String(data: data, encoding: .utf8) else { throw PersonalLexiconError.invalid(UIText.t("请选择不超过 1 MB 的 UTF-8 词表。")) }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let rows: [PersonalLexiconEntry]
        if json {
            do { rows = try JSONDecoder().decode([PersonalLexiconEntry].self, from: Data(text.utf8)) }
            catch { throw PersonalLexiconError.invalid(UIText.t("JSON 必须是词条数组，每条至少包含 term 和 meaning 字段。")) }
        } else {
            let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let first = lines.first else { throw PersonalLexiconError.invalid(UIText.t("词表为空。")) }
            let aliases = ["词语":"term", "读音":"reading", "释义":"meaning", "例句":"example", "用法":"note", "来源":"source"]
            let headers = first.components(separatedBy: "\t").map { value in
                let key = value.trimmingCharacters(in: .whitespaces).lowercased(); return aliases[key] ?? key
            }
            guard headers.contains("term"), headers.contains("meaning"), Set(headers).count == headers.count,
                  headers.allSatisfy({ ["term", "reading", "meaning", "example", "note", "source"].contains($0) }) else {
                throw PersonalLexiconError.invalid(UIText.t("TSV 第一行需包含 term、meaning（或“词语”“释义”）；可选 reading、example、note、source。列之间使用制表符。"))
            }
            rows = try lines.dropFirst().enumerated().map { index, line in
                let values = line.components(separatedBy: "\t")
                guard values.count == headers.count else { throw PersonalLexiconError.invalid(UIText.t("第 %@ 行列数不一致；单元格内不要换行或插入制表符。", "\(index + 2)")) }
                let record = Dictionary(uniqueKeysWithValues: zip(headers, values))
                return PersonalLexiconEntry(term: record["term"] ?? "", reading: record["reading"] ?? "", meaning: record["meaning"] ?? "", example: record["example"] ?? "", note: record["note"] ?? "", source: record["source"] ?? "")
            }
        }
        guard !rows.isEmpty else { throw PersonalLexiconError.invalid(UIText.t("没有可导入的词条。")) }
        return try merge(existing: [], incoming: rows)
    }
    public static func merge(existing: [PersonalLexiconEntry], incoming: [PersonalLexiconEntry]) throws -> [PersonalLexiconEntry] {
        guard existing.count <= 2000, incoming.count <= 2000 else { throw PersonalLexiconError.invalid(UIText.t("词库最多支持 2000 条。")) }
        var result: [String: PersonalLexiconEntry] = [:]
        for row in existing + incoming {
            let fields = [row.term, row.reading, row.meaning, row.example, row.note, row.source].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let limits = [80, 100, 500, 300, 300, 300]
            guard !fields[0].isEmpty, !fields[2].isEmpty,
                  zip(fields, limits).allSatisfy({ $0.count <= $1 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
                throw PersonalLexiconError.invalid(UIText.t("词语与释义不能为空；字段过长或含控制字符，请检查词表。"))
            }
            let entry = PersonalLexiconEntry(term: fields[0], reading: fields[1], meaning: fields[2], example: fields[3], note: fields[4], source: fields[5])
            result[entry.id] = entry
        }
        let rows = result.values.sorted { $0.id < $1.id }
        guard rows.count <= 2000, try JSONEncoder().encode(rows).count <= 1_000_000 else { throw PersonalLexiconError.invalid(UIText.t("合并后的词库超过 2000 条或 1 MB；原词库未修改。")) }
        return rows
    }
    /// Literal term matches only. Longer terms win; unrelated book content is never sent.
    public static func references(for draft: String, entries: [PersonalLexiconEntry]) -> [[String: String]] {
        let text = TextNormalization.nfkc(draft).lowercased()
        let matches = entries.filter { text.contains($0.id) }.sorted { $0.term.count == $1.term.count ? $0.id < $1.id : $0.term.count > $1.term.count }
        var result: [[String: String]] = []; var bytes = 0
        for entry in matches.prefix(8) {
            let item = ["term": entry.term, "meaning": entry.meaning, "usage": entry.note]
            let count = (try? JSONSerialization.data(withJSONObject: item).count) ?? 3001
            if bytes + count > 3000 { continue }
            result.append(item); bytes += count
        }
        return result
    }
}
