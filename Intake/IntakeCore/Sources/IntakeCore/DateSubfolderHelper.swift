import Foundation

extension SubfolderPattern {
    /// Returns the subfolder name for the given date in the user's current time zone,
    /// using zero-padded Gregorian calendar format. Returns empty string for `.none`.
    public func subfolder(for date: Date) -> String {
        switch self {
        case .none:
            return ""
        case .year:
            return yearComponent(of: date)
        case .yearMonth:
            let year = yearComponent(of: date)
            let month = monthComponent(of: date)
            return "\(year)-\(month)"
        }
    }

    private func yearComponent(of date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return String(format: "%04d", year)
    }

    private func monthComponent(of date: Date) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        return String(format: "%02d", month)
    }
}
