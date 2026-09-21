import Foundation

public struct EmojiEntry: Codable, Hashable, Sendable {
    public let emoji: String
    public let name: String
    public let aliases: [String]
    public let keywords: [String]

    public init(emoji: String, name: String, aliases: [String] = [], keywords: [String] = []) {
        self.emoji = emoji
        self.name = name
        self.aliases = aliases
        self.keywords = keywords
    }

    public var shortcode: String { ":\(name):" }
}

public final class EmojiCatalog: @unchecked Sendable {
    public static let shared = EmojiCatalog()
    public let entries: [EmojiEntry]

    public init(entries: [EmojiEntry]? = nil) {
        if let entries {
            self.entries = entries
            return
        }

        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([EmojiEntry].self, from: data) else {
            self.entries = [
                EmojiEntry(emoji: "💀", name: "skull", keywords: ["death", "dead", "skeleton"]),
                EmojiEntry(emoji: "☠️", name: "skull_and_crossbones", keywords: ["death", "danger", "pirate", "skull"]),
            ]
            return
        }
        self.entries = decoded
    }

    public func exactMatch(_ rawQuery: String) -> EmojiEntry? {
        let query = Self.normalize(rawQuery)
        return entries.first { entry in
            entry.name == query || entry.aliases.contains(query)
        }
    }

    public func search(_ rawQuery: String, limit: Int = 8) -> [EmojiEntry] {
        let query = Self.normalize(rawQuery)
        guard !query.isEmpty else { return [] }

        return entries
            .compactMap { entry -> (EmojiEntry, Int)? in
                let fields = [entry.name] + entry.aliases + entry.keywords
                var best = Int.max

                for (index, field) in fields.enumerated() {
                    let normalized = Self.normalize(field)
                    let sourcePenalty = index == 0 ? 0 : (index <= entry.aliases.count ? 40 : 85)
                    if normalized == query {
                        best = min(best, sourcePenalty)
                    } else if normalized.hasPrefix(query) {
                        best = min(best, 8 + sourcePenalty + normalized.count - query.count)
                    } else if normalized.split(separator: "_").contains(where: { $0.hasPrefix(query) }) {
                        best = min(best, 32 + sourcePenalty + normalized.count - query.count)
                    } else if normalized.contains(query) {
                        best = min(best, 58 + sourcePenalty + normalized.count - query.count)
                    } else if query.count >= 4, Self.isSubsequence(query, of: normalized) {
                        best = min(best, 150 + sourcePenalty + normalized.count - query.count)
                    }
                }

                return best == Int.max ? nil : (entry, best)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.name < rhs.0.name }
                return lhs.1 < rhs.1
            }
            .prefix(max(0, limit))
            .map(\.0)
    }

    public func related(to entry: EmojiEntry, limit: Int = 25) -> [EmojiEntry] {
        let sourceTerms = Set(
            ([entry.name] + entry.aliases + entry.keywords)
                .flatMap { Self.searchTerms($0) }
        )

        return entries
            .filter { $0 != entry }
            .compactMap { candidate -> (EmojiEntry, Int)? in
                let candidateTerms = Set(
                    ([candidate.name] + candidate.aliases + candidate.keywords)
                        .flatMap { Self.searchTerms($0) }
                )
                let overlap = sourceTerms.intersection(candidateTerms)
                guard !overlap.isEmpty else { return nil }

                let keywordOverlap = Set(entry.keywords.flatMap { Self.searchTerms($0) })
                    .intersection(Set(candidate.keywords.flatMap { Self.searchTerms($0) }))
                let nameOverlap = Set(([entry.name] + entry.aliases).flatMap { Self.searchTerms($0) })
                    .intersection(Set(([candidate.name] + candidate.aliases).flatMap { Self.searchTerms($0) }))
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
