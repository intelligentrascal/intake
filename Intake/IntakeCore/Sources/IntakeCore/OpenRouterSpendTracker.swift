import Foundation

/// Persists OpenRouter API spend across relaunches.
/// Tracks total spend and current calendar month spend.
public struct OpenRouterSpendTracker: Equatable, Sendable {
    public static let defaultsKey = "intake.openRouterSpend"

    /// Total spend across all time
    public private(set) var totalSpend: Double

    /// Spend in the current calendar month
    public private(set) var monthlySpend: Double

    /// The month/year when monthlySpend was last reset
    public private(set) var lastResetDate: Date

    public init(totalSpend: Double = 0, monthlySpend: Double = 0, lastResetDate: Date = Date()) {
        self.totalSpend = totalSpend
        self.monthlySpend = monthlySpend
        self.lastResetDate = lastResetDate
    }

    /// Add a cost, updating total and monthly spend. If the month has rolled over, reset monthly spend.
    public mutating func addCost(_ cost: Double, now: Date = Date()) {
        totalSpend += cost
        if Self.hasMonthRolledOver(lastResetDate: lastResetDate, now: now) {
            monthlySpend = cost
            lastResetDate = now
        } else {
            monthlySpend += cost
        }
    }

    /// Reset the monthly spend counter without clearing total.
    public mutating func resetMonthly(now: Date = Date()) {
        monthlySpend = 0
        lastResetDate = now
    }

    /// Reset both total and monthly spend counters.
    public mutating func resetAll(now: Date = Date()) {
        totalSpend = 0
        monthlySpend = 0
        lastResetDate = now
    }

    /// Check if the calendar month has changed between two dates.
    private static func hasMonthRolledOver(lastResetDate: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        let lastComponents = calendar.dateComponents([.year, .month], from: lastResetDate)
        let nowComponents = calendar.dateComponents([.year, .month], from: now)
        return lastComponents.year != nowComponents.year || lastComponents.month != nowComponents.month
    }
}

// MARK: - Persistence

extension OpenRouterSpendTracker {
    public static func load(from defaults: UserDefaults) -> OpenRouterSpendTracker {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return OpenRouterSpendTracker()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CodableSpendTracker.self, from: data))
            .map { OpenRouterSpendTracker(totalSpend: $0.totalSpend, monthlySpend: $0.monthlySpend, lastResetDate: $0.lastResetDate) }
            ?? OpenRouterSpendTracker()
    }

    public func save(to defaults: UserDefaults) {
        let codable = CodableSpendTracker(
            totalSpend: totalSpend,
            monthlySpend: monthlySpend,
            lastResetDate: lastResetDate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(codable) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    public static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

// MARK: - Codable Support

private struct CodableSpendTracker: Codable {
    var totalSpend: Double
    var monthlySpend: Double
    var lastResetDate: Date
}
