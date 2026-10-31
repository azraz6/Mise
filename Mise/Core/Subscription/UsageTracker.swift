import Foundation
import Observation

enum FreeTier {
    static let automaticImportsPerMonth = 20
    static let collections = 3
}

@MainActor
@Observable
final class UsageTracker {
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar

    private(set) var automaticImportsThisMonth: Int
    private var monthKey: String

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let key = Self.monthKey(for: now(), calendar: calendar)
        self.monthKey = key
        self.automaticImportsThisMonth = defaults.integer(forKey: "com.mise.usage.automaticImports.\(key)")
    }

    var currentMonthKey: String {
        Self.monthKey(for: now(), calendar: calendar)
    }

    var remainingFreeImports: Int {
        max(0, FreeTier.automaticImportsPerMonth - automaticImportsThisMonth)
    }

    func refreshForCurrentMonth() {
        let current = currentMonthKey
        guard current != monthKey else { return }
        monthKey = current
        automaticImportsThisMonth = defaults.integer(forKey: importKey)
    }

    func canStartAutomaticImport(isPremium: Bool) -> Bool {
        refreshForCurrentMonth()
        return isPremium || remainingFreeImports > 0
    }

    func recordAutomaticImport(isPremium: Bool) {
        guard !isPremium else { return }
        refreshForCurrentMonth()
        automaticImportsThisMonth += 1
        defaults.set(automaticImportsThisMonth, forKey: importKey)
    }

    func canCreateCollection(existingCount: Int, isPremium: Bool) -> Bool {
        isPremium || existingCount < FreeTier.collections
    }

    static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private var importKey: String {
        "com.mise.usage.automaticImports.\(monthKey)"
    }
}
