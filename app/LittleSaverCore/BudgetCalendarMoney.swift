import CoreData
import Foundation

/// V1 is a single-currency ledger. Currency preferences affect presentation only.
/// Normalization removes negative zero, not fractional precision.
public struct MoneyAmount: Sendable, Equatable {
    public let value: Double
    public init?(_ value: Double) {
        guard value.isFinite else { return nil }
        self.value = value == 0 ? 0 : value
    }

    /// Truncates only for an explicit keypad edit. Large integers already have no
    /// representable fractional digits, so avoid multiplying them into infinity.
    public static func truncating(_ value: Double, decimalPlaces: Int) -> Double {
        guard value.isFinite else { return 0 }
        let scale = decimalPlaces == 1 ? 10.0 : decimalPlaces == 2 ? 100.0 : 1.0
        guard abs(value) < Double.greatestFiniteMagnitude / scale else { return value }
        return (value * scale).rounded(.towardZero) / scale
    }

    public static func deletingLastDigit(_ value: Double, centsEntry: Bool) -> Double {
        guard value.isFinite else { return 0 }
        if centsEntry {
            // For huge values, one decimal digit is far below the Double ULP.
            guard abs(value) < Double.greatestFiniteMagnitude / 10 else { return value / 10 }
            return (value * 10).rounded(.towardZero) / 100
        }
        return (value / 10).rounded(.towardZero)
    }
}

/// Presentation selection stores a civil date, not a midnight instant in the
/// timezone where a screen happened to open. Nil follows the current period.
public struct CalendarPeriodSelection {
    private var civilDate: DateComponents?
    private var sourceCalendar: Calendar?

    public init() {}

    public init(start: Date, calendar: Calendar = .current) {
        guard LedgerCalendar.isValid(start) else { return }
        civilDate = calendar.dateComponents([.era, .year, .month, .day], from: start)
        sourceCalendar = calendar
    }

    public func start(period: BudgetPeriod, now: Date = .now, calendar: Calendar = .current, firstWeekday: Int = 1, firstDayOfMonth: Int = 1) -> Date {
        var calendar = calendar
        calendar.firstWeekday = (1...7).contains(firstWeekday) ? firstWeekday : 1
        calendar.minimumDaysInFirstWeek = 4
        var selected = now
        if let civilDate, var sourceCalendar {
            // Retain the source civil day even if the user's calendar system changes.
            sourceCalendar.timeZone = calendar.timeZone
            selected = sourceCalendar.date(from: civilDate) ?? now
        }
        switch period {
        case .day: return calendar.startOfDay(for: selected)
        case .week: return calendar.dateInterval(of: .weekOfYear, for: selected)?.start ?? calendar.startOfDay(for: selected)
        case .month:
            if civilDate == nil { return getStartOfMonth(startDay: firstDayOfMonth, now: now, calendar: calendar) }
            return LedgerCalendar.monthStart(in: selected, day: firstDayOfMonth, calendar: calendar) ?? calendar.startOfDay(for: selected)
        case .year: return calendar.dateInterval(of: .year, for: selected)?.start ?? calendar.startOfDay(for: selected)
        }
    }

    public mutating func select(_ date: Date, period: BudgetPeriod, now: Date = .now, calendar: Calendar = .current, firstWeekday: Int = 1, firstDayOfMonth: Int = 1) {
        let current = Self().start(period: period, now: now, calendar: calendar, firstWeekday: firstWeekday, firstDayOfMonth: firstDayOfMonth)
        self = date >= current ? Self() : Self(start: date, calendar: calendar)
    }
}

public enum LedgerCalendar {
    /// Keep damaged timestamps away from Foundation calendar arithmetic.
    public static func isValid(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && date >= .distantPast && date <= .distantFuture
    }

    public static func dayInterval(containing date: Date?, calendar: Calendar = .current) -> DateInterval? {
        guard let date, isValid(date), let interval = calendar.dateInterval(of: .day, for: date), interval.end > interval.start else { return nil }
        return interval
    }

    public static func predicate(start: Date, end: Date, now: Date? = nil) -> NSPredicate {
        guard isValid(start), isValid(end), end > start else { return NSPredicate(value: false) }
        let window = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        guard let now else { return window }
        guard isValid(now), now >= start else { return NSPredicate(value: false) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [window, NSPredicate(format: "date <= %@", now as NSDate)])
    }

    public static func dayPredicate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> NSPredicate {
        guard let interval = dayInterval(containing: date, calendar: calendar) else { return NSPredicate(value: false) }
        return predicate(start: interval.start, end: interval.end, now: now)
    }

    public static func groupedTransactions<S: Sequence>(_ transactions: S, calendar: Calendar = .current) -> [TransactionDayGroup] where S.Element == Transaction {
        var grouped: [Date: [Transaction]] = [:]
        var undated: [Transaction] = []
        for transaction in transactions {
            if let day = dayInterval(containing: transaction.date, calendar: calendar)?.start {
                grouped[day, default: []].append(transaction)
            } else { undated.append(transaction) }
        }
        var result = grouped.keys.sorted(by: >).map { TransactionDayGroup(date: $0, transactions: grouped[$0] ?? []) }
        if !undated.isEmpty { result.append(TransactionDayGroup(date: nil, transactions: undated)) }
        return result
    }

    /// Resolve a user-selected month-start day in that month, clamping only that
    /// occurrence; the original preferred day is retained for the next month.
    public static func monthStart(in date: Date, day: Int, offset: Int = 0, calendar: Calendar = .current) -> Date? {
        guard isValid(date), let month = calendar.dateInterval(of: .month, for: date)?.start,
              let shifted = calendar.date(byAdding: .month, value: offset, to: month), isValid(shifted),
              let range = calendar.range(of: .day, in: .month, for: shifted) else { return nil }
        let selectedDay = (1...31).contains(day) ? min(day, range.count) : 1
        return calendar.date(byAdding: .day, value: selectedDay - 1, to: shifted)
    }

    public static func monthlyScheduleAnchor(day: Int, onOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        guard (1...31).contains(day) else { return nil }
        // A clamped February occurrence cannot encode a requested day 31. Pick
        // a genuine occurrence as the stored anchor, without changing its day.
        for offset in 0 ... 24 {
            if let candidate = monthStart(in: date, day: day, offset: -offset, calendar: calendar),
               candidate <= date, calendar.component(.day, from: candidate) == day { return candidate }
        }
        return nil
    }

    public static func insightsEnd(start: Date, type: Int, firstDayOfMonth: Int, calendar: Calendar = .current) -> Date? {
        guard isValid(start) else { return nil }
        if type == 2 { return monthStart(in: start, day: firstDayOfMonth, offset: 1, calendar: calendar) }
        return calendar.date(byAdding: type == 1 ? .day : .year, value: type == 1 ? 7 : 1, to: start)
    }

    public static func insightsPredicate(start: Date, type: Int, now: Date = .now, firstDayOfMonth: Int = 1, calendar: Calendar = .current) -> NSPredicate {
        guard let end = insightsEnd(start: start, type: type, firstDayOfMonth: firstDayOfMonth, calendar: calendar) else { return NSPredicate(value: false) }
        return predicate(start: start, end: end, now: now)
    }
}

/// Managed objects remain on the caller's main-context presentation queue.
public struct TransactionDayGroup: Identifiable {
    public var id: Date? { date }
    public let date: Date?
    public let transactions: [Transaction]
}

public enum BudgetPeriod: Int16, CaseIterable, Sendable {
    case day = 1, week = 2, month = 3, year = 4

    private var component: Calendar.Component { self == .day || self == .week ? .day : self == .month ? .month : .year }

    public func window(anchor: Date, index: Int, calendar: Calendar = .current) -> BudgetWindow? {
        guard LedgerCalendar.isValid(anchor) else { return nil }
        let anchor = calendar.startOfDay(for: anchor)
        let next = index.addingReportingOverflow(1)
        let startOffset = index.multipliedReportingOverflow(by: self == .week ? 7 : 1)
        let endOffset = next.partialValue.multipliedReportingOverflow(by: self == .week ? 7 : 1)
        guard !next.overflow, !startOffset.overflow, !endOffset.overflow,
              // Any larger offset is outside the supported date domain.
              abs(Double(startOffset.partialValue)) <= 3_000_000,
              abs(Double(endOffset.partialValue)) <= 3_000_000,
              let start = calendar.date(byAdding: component, value: startOffset.partialValue, to: anchor),
              let end = calendar.date(byAdding: component, value: endOffset.partialValue, to: anchor),
              LedgerCalendar.isValid(start), LedgerCalendar.isValid(end), end > start else { return nil }
        return BudgetWindow(start: start, end: end, index: index)
    }

    public func window(anchor: Date, containing date: Date, calendar: Calendar = .current) -> BudgetWindow? {
        guard LedgerCalendar.isValid(anchor), LedgerCalendar.isValid(date) else { return nil }
        let anchor = calendar.startOfDay(for: anchor)
        guard
              let distance = calendar.dateComponents([component], from: anchor, to: date).value(for: component) else { return nil }
        guard let estimate = self == .week ? Int(exactly: floor(Double(distance) / 7)) : distance else { return nil }
        // DateComponents supplies a direct estimate. Calendar clamping/DST can
        // move its boundary by one occurrence; never iterate over elapsed periods.
        for offset in [0, -1, 1, -2, 2] {
            let candidate = estimate.addingReportingOverflow(offset)
            guard !candidate.overflow, let window = window(anchor: anchor, index: candidate.partialValue, calendar: calendar) else { continue }
            if window.start <= date && date < window.end { return window }
        }
        return nil
    }

    public func currentWindow(anchor: Date?, amount: Double, now: Date = .now, calendar: Calendar = .current) -> BudgetWindow? {
        guard let anchor, let amount = MoneyAmount(amount), amount.value > 0, LedgerCalendar.isValid(now) else { return nil }
        guard LedgerCalendar.isValid(anchor) else { return nil }
        return now < calendar.startOfDay(for: anchor) ? window(anchor: anchor, index: 0, calendar: calendar) : window(anchor: anchor, containing: now, calendar: calendar)
    }
}

public struct BudgetWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let index: Int
    public func transactionPredicate(now: Date = .now) -> NSPredicate { LedgerCalendar.predicate(start: start, end: end, now: now) }
    public func progress(at now: Date = .now) -> Double { Self.progress(startDate: start, endDate: end, now: now, calendar: .current) }
    public func daysRemaining(at now: Date = .now, calendar: Calendar = .current) -> Int {
        guard now < end else { return 0 }
        let lower = calendar.startOfDay(for: max(start, now))
        return max(1, calendar.dateComponents([.day], from: lower, to: end).day ?? 0)
    }
    public static func progress(startDate: Date, endDate: Date, now: Date, calendar: Calendar) -> Double {
        guard LedgerCalendar.isValid(startDate), LedgerCalendar.isValid(endDate), LedgerCalendar.isValid(now), endDate > startDate else { return 0 }
        return NumericSafety.clamped(NumericSafety.safeRatio(now.timeIntervalSince(startDate), endDate.timeIntervalSince(startDate)), to: 0...1)
    }
}

public extension Budget {
    func currentWindow(now: Date = .now, calendar: Calendar = .current) -> BudgetWindow? {
        guard category != nil else { return nil }
        return BudgetPeriod(rawValue: type)?.currentWindow(anchor: startDate, amount: amount, now: now, calendar: calendar)
    }
    func transactionPredicate(now: Date = .now, calendar: Calendar = .current) -> NSPredicate {
        guard let window = currentWindow(now: now, calendar: calendar), let category else { return NSPredicate(value: false) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [window.transactionPredicate(now: now), NSPredicate(format: "income == NO AND category == %@", category)])
    }
}

public extension MainBudget {
    func currentWindow(now: Date = .now, calendar: Calendar = .current) -> BudgetWindow? {
        BudgetPeriod(rawValue: type)?.currentWindow(anchor: startDate, amount: amount, now: now, calendar: calendar)
    }
    func transactionPredicate(now: Date = .now, calendar: Calendar = .current) -> NSPredicate {
        guard let window = currentWindow(now: now, calendar: calendar) else { return NSPredicate(value: false) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [window.transactionPredicate(now: now), NSPredicate(format: "income == NO")])
    }
}
