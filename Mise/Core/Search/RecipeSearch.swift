import Foundation

enum RecipeSortOrder: String, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case recentlyCooked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recentlyAdded: return "Recently added"
        case .title: return "Title A–Z"
        case .recentlyCooked: return "Recently cooked"
        }
    }
}

struct RecipeFilter {
    var query: String = ""
    var favouritesOnly: Bool = false
    var includeArchived: Bool = false
    var collectionRecipeIDs: Set<UUID>? = nil
    var sourceType: RecipeSourceType? = nil
    var category: String? = nil
}

enum RecipeSearch {
    static func apply(
        _ recipes: [Recipe],
        filter: RecipeFilter,
        sort: RecipeSortOrder = .recentlyAdded
    ) -> [Recipe] {
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        var result = recipes.filter { recipe in
            if !filter.includeArchived && recipe.isArchived { return false }
            if filter.favouritesOnly && !recipe.isFavourite { return false }
            if let ids = filter.collectionRecipeIDs, !ids.contains(recipe.id) { return false }
            if let sourceType = filter.sourceType, recipe.sourceType != sourceType { return false }
            if let category = filter.category, recipe.category != category { return false }
            if !query.isEmpty {
                let haystack = recipe.searchText
                let tokens = query.split(separator: " ").map(String.init)
                if !tokens.allSatisfy({ haystack.contains($0) }) { return false }
            }
            return true
        }
        switch sort {
        case .recentlyAdded:
            result.sort { $0.dateAdded > $1.dateAdded }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .recentlyCooked:
            result.sort {
                ($0.lastCookedAt ?? .distantPast) > ($1.lastCookedAt ?? .distantPast)
            }
        }
        return result
    }
}

struct DuplicateCandidate: Identifiable, Equatable {
    enum Reason: String {
        case sameSource
        case similarTitle
    }

    var id: UUID { recipeID }
    var recipeID: UUID
    var title: String
    var reason: Reason
}

enum DuplicateDetector {
    static func candidates(for draft: RecipeDraft, excluding recipeID: UUID? = nil, in recipes: [Recipe]) -> [DuplicateCandidate] {
        var matches: [DuplicateCandidate] = []
        let normalizedSource = draft.sourceURLString.flatMap { raw -> String? in
            guard let url = URL(string: raw) else { return nil }
            return SourceDetector.normalizedURLString(url)
        }
        for recipe in recipes {
            if recipe.id == recipeID || recipe.isArchived { continue }
            if let normalizedSource, let existingURL = recipe.sourceURL {
                if SourceDetector.normalizedURLString(existingURL) == normalizedSource {
                    matches.append(DuplicateCandidate(recipeID: recipe.id, title: recipe.title, reason: .sameSource))
                    continue
                }
            }
            if titleSimilarity(draft.displayTitle, recipe.title) >= 0.88 {
                matches.append(DuplicateCandidate(recipeID: recipe.id, title: recipe.title, reason: .similarTitle))
            }
        }
        return matches.sorted { lhs, rhs in
            if lhs.reason != rhs.reason { return lhs.reason == .sameSource }
            return lhs.title < rhs.title
        }
    }

    static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalize(lhs)
        let b = normalize(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        let distance = levenshtein(a, b)
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 0 }
        let ratio = 1 - Double(distance) / Double(longest)
        let aTokens = Set(a.split(separator: " ").map(String.init))
        let bTokens = Set(b.split(separator: " ").map(String.init))
        let union = aTokens.union(bTokens).count
        let jaccard = union == 0 ? 0 : Double(aTokens.intersection(bTokens).count) / Double(union)
        return max(ratio, jaccard)
    }

    private static func normalize(_ value: String) -> String {
        let tokens = value.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map(String.init)
            .filter { $0 != "recipe" && $0 != "recipes" }
        return tokens.joined(separator: " ")
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost))
            }
            previous = current
        }
        return previous[b.count]
    }
}
