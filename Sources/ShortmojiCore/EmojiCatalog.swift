import Foundation

public struct EmojiEntry: Codable, Hashable, Sendable {
    public let emoji: String
    public let name: String
    public let aliases: [String]
    public let keywords: [String]
    public let category: String?

    public init(emoji: String, name: String, aliases: [String] = [], keywords: [String] = [], category: String? = nil) {
        self.emoji = emoji
        self.name = name
        self.aliases = aliases
        self.keywords = keywords
        self.category = category
    }

    public var shortcode: String { ":\(name):" }
    public var hasSkinTone: Bool {
        emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
    }
}

public final class EmojiCatalog: @unchecked Sendable {
    public static let shared = EmojiCatalog()
    public let entries: [EmojiEntry]
    private struct IndexedEntry {
        let entry: EmojiEntry
        let fields: [(text: String, penalty: Int, words: [String])]
        let terms: Set<String>
        let nameTerms: Set<String>
        let keywordTerms: Set<String>
        let hasSkinTone: Bool

        init(_ entry: EmojiEntry) {
            self.entry = entry
            fields = ([entry.name] + entry.aliases + entry.keywords).enumerated().map { index, field in
                let text = EmojiCatalog.normalize(field)
                return (text, index == 0 ? 0 : (index <= entry.aliases.count ? 40 : 85), text.split(separator: "_").map(String.init))
            }
            nameTerms = Set(([entry.name] + entry.aliases).flatMap(EmojiCatalog.searchTerms))
            keywordTerms = Set(entry.keywords.flatMap(EmojiCatalog.searchTerms))
            terms = nameTerms.union(keywordTerms)
            hasSkinTone = entry.emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
        }
    }
    private let index: [IndexedEntry]
    private let exact: [String: EmojiEntry]
    private let tones: [String: [Int: String]]
    public var browsingEntries: [EmojiEntry] { entries.filter { !$0.hasSkinTone } }

    private static func familyKey(_ emoji: String) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter {
            !(0x1F3FB...0x1F3FF).contains($0.value) && $0.value != 0xFE0F
        }))
    }

    /// Preserve explicit toned shortcodes; apply the preference only to base entries.
    public func applyingSkinTone(_ tone: Int, to entry: EmojiEntry) -> EmojiEntry {
        guard !entry.hasSkinTone, let glyph = tones[Self.familyKey(entry.emoji)]?[tone] else { return entry }
        return EmojiEntry(emoji: glyph, name: entry.name, aliases: entry.aliases,
                          keywords: entry.keywords, category: entry.category)
    }

    public init(entries: [EmojiEntry]? = nil) {
        let loaded: [EmojiEntry]
        if let entries {
            loaded = entries
        } else if let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([EmojiEntry].self, from: data) {
            loaded = decoded
        } else {
            loaded = [
                EmojiEntry(emoji: "💀", name: "skull", keywords: ["death", "dead", "skeleton"]),
                EmojiEntry(emoji: "☠️", name: "skull_and_crossbones", keywords: ["death", "danger", "pirate", "skull"]),
            ]
        }
        self.entries = loaded
        var toneLookup: [String: [Int: String]] = [:]
        for entry in loaded {
            let modifiers = Set(entry.emoji.unicodeScalars.filter { (0x1F3FB...0x1F3FF).contains($0.value) }.map(\.value))
            if modifiers.count == 1, let modifier = modifiers.first {
                toneLookup[Self.familyKey(entry.emoji), default: [:]][Int(modifier - 0x1F3FA)] = entry.emoji
            }
        }
        tones = toneLookup
        index = loaded.map(IndexedEntry.init)
        var lookup: [String: EmojiEntry] = [:]
        for entry in loaded { lookup[Self.normalize(entry.name)] = entry }
        for entry in loaded {
            for alias in entry.aliases where lookup[Self.normalize(alias)] == nil {
                lookup[Self.normalize(alias)] = entry
            }
        }
        exact = lookup
    }

    public func exactMatch(_ rawQuery: String) -> EmojiEntry? {
        let query = Self.normalize(rawQuery)
        return exact[query]
    }

    public func search(_ rawQuery: String, limit: Int = 8) -> [EmojiEntry] {
        let query = Self.normalize(rawQuery)
        guard !query.isEmpty else { return [] }

        return index
            .compactMap { item -> (EmojiEntry, Int)? in
                let entry = item.entry
                if item.hasSkinTone && !query.contains("skin") && !query.contains("tone") { return nil }
                var best = Int.max

                for field in item.fields {
                    let normalized = field.text
                    let sourcePenalty = field.penalty
                    if normalized == query {
                        best = min(best, sourcePenalty)
                    } else if normalized.hasPrefix(query) {
                        // Rank the matching word, so skull_and_crossbones stays
                        // beside skull instead of losing to a shorter skunk name.
                        let matchingLength = query.contains("_") ? normalized.count
                            : (field.words.first?.count ?? normalized.count)
                        best = min(best, 8 + sourcePenalty + matchingLength - query.count)
                    } else if field.words.contains(where: { $0.hasPrefix(query) }) {
                        best = min(best, 32 + sourcePenalty + normalized.count - query.count)
                    } else if normalized.contains(query) {
                        best = min(best, 58 + sourcePenalty + normalized.count - query.count)
                    } else if query.count >= 4, Self.isSubsequence(query, of: normalized) {
                        best = min(best, 150 + sourcePenalty + normalized.count - query.count)
                    }
                }

                let variantPenalty = item.hasSkinTone && !query.contains("skin") && !query.contains("tone") ? 20 : 0
                return best == Int.max ? nil : (entry, best + variantPenalty)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.name < rhs.0.name }
                return lhs.1 < rhs.1
            }
            .prefix(max(0, limit))
            .map(\.0)
    }

    public func related(to entry: EmojiEntry, limit: Int = 25) -> [EmojiEntry] {
        let source = IndexedEntry(entry)

        return index
            .filter { $0.entry.name != entry.name && !$0.hasSkinTone }
            .compactMap { item -> (EmojiEntry, Int)? in
                let candidate = item.entry
                let overlap = source.terms.intersection(item.terms)
                guard !overlap.isEmpty else { return nil }

                let keywordOverlap = source.keywordTerms.intersection(item.keywordTerms)
                let nameOverlap = source.nameTerms.intersection(item.nameTerms)
                let score = nameOverlap.count * 150 + keywordOverlap.count * 100 + overlap.count * 10
                return (candidate, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.name < rhs.0.name }
                return lhs.1 > rhs.1
            }
            .prefix(max(0, limit))
            .map(\.0)
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var index = needle.startIndex
        for character in haystack where index < needle.endIndex {
            if character == needle[index] {
                index = needle.index(after: index)
            }
        }
        return index == needle.endIndex
    }

    private static func searchTerms(_ value: String) -> [String] {
        normalize(value)
            .split(separator: "_")
            .map(String.init)
            .filter { $0.count > 2 }
    }
}
