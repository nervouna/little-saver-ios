import Combine
import CoreData
import Foundation

/// Main-actor publication is separate from the queue-confined repository.
@MainActor
public final class SnapshotModel<Key: Hashable, Value: Sendable>: ObservableObject {
    @Published public private(set) var value: Value?
    @Published public private(set) var error: String?
    @Published public private(set) var isLoading = false
    private var currentKey: Key?
    private var publishedKey: Key?
    private var lease: SnapshotLease?
    public init() {}

    public func value(for key: Key) -> Value? { publishedKey == key ? value : nil }

    public func load(key: Key, using loader: (Key) async throws -> Value) async {
        if currentKey == key, lease?.isCancelled != true, isLoading || publishedKey == key { return }
        lease?.cancel()
        let ticket = SnapshotLease()
        lease = ticket; currentKey = key; error = nil; isLoading = true
        await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let result = try await loader(key)
                try Task.checkCancellation()
                guard lease === ticket, !ticket.isCancelled else { return }
                publishedKey = key; value = result; isLoading = false
            } catch {
                guard lease === ticket else { return }
                currentKey = nil; isLoading = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        } onCancel: {
            ticket.cancel()
            Task { @MainActor [weak self] in
                guard let self, self.lease === ticket else { return }
                self.currentKey = nil; self.isLoading = false
            }
        }
    }
}

private final class SnapshotLease: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
}

public struct AnalyticsStamp: Hashable, Sendable {
    public let revision: UInt64
    public let now: Date
    public init(revision: UInt64 = 0, now: Date = .now) { self.revision = revision; self.now = now }
}

/// Currency, display precision and animations deliberately do not participate.
public struct AnalyticsEnvironment: Hashable, Sendable {
    public let stamp: AnalyticsStamp
    public let calendar: Calendar
    public let firstDayOfMonth: Int
    public var now: Date { stamp.now }
    public init(stamp: AnalyticsStamp, calendar: Calendar = .current, firstWeekday: Int = 1, firstDayOfMonth: Int = 1) {
        self.stamp = stamp
        var calendar = calendar
        calendar.firstWeekday = (1...7).contains(firstWeekday) ? firstWeekday : 1
        calendar.minimumDaysInFirstWeek = 4
        self.calendar = calendar
        self.firstDayOfMonth = (1...31).contains(firstDayOfMonth) ? firstDayOfMonth : 1
    }
}

public struct AnalyticsCategory: Identifiable, Hashable, Sendable {
    public let id: URL
    public let uuid: UUID?
    public let name: String
    public let emoji: String
    public let colour: String
    public let income: Bool
    init(_ category: Category) {
        id = category.objectID.uriRepresentation(); uuid = category.id
        name = category.wrappedName; emoji = category.wrappedEmoji; colour = category.wrappedColour; income = category.income
    }
}

/// Permanent references may be resolved only by the main-context presentation adapter.
public struct LedgerRowSnapshot: Identifiable, Sendable {
    public let id: URL
    public let uuid: UUID?
    public let date: Date?
    public let upcomingDate: Date?
    public let amount: Double
    public let income: Bool
    public let note: String
    public let category: AnalyticsCategory?
    init(_ transaction: Transaction, environment: AnalyticsEnvironment) {
        id = transaction.objectID.uriRepresentation(); uuid = transaction.id
        date = transaction.date.flatMap { LedgerCalendar.isValid($0) ? $0 : nil }
        amount = transaction.wrappedAmount; income = transaction.income; note = transaction.wrappedNote
        category = transaction.category.map(AnalyticsCategory.init)
        if let date, date > environment.now { upcomingDate = date }
        else if let next = transaction.nextScheduledDate, LedgerCalendar.isValid(next) { upcomingDate = next }
        else if let date {
            upcomingDate = try? RecurringSchedule.nextDate(after: date, type: transaction.recurringType, coefficient: transaction.recurringCoefficient, calendar: environment.calendar)
        } else { upcomingDate = nil }
    }
}

public struct LedgerDaySnapshot: Identifiable, Sendable {
    public var id: Date? { date }
    public let date: Date?
    public let rows: [LedgerRowSnapshot]
    public let net: Double
}

public struct LedgerListSnapshot: Sendable {
    public let rows: [LedgerRowSnapshot]
    public let days: [LedgerDaySnapshot]
    public let spent: Double
    public let income: Double
    public var net: Double { income - spent }

    init(rows: [LedgerRowSnapshot], calendar: Calendar) {
        self.rows = rows
        var groups: [Date: [LedgerRowSnapshot]] = [:]
        var undated: [LedgerRowSnapshot] = []
        var spent = 0.0; var income = 0.0
        for row in rows {
            if row.income { income += row.amount } else { spent += row.amount }
            if let date = row.date { groups[calendar.startOfDay(for: date), default: []].append(row) }
            else { undated.append(row) }
        }
        self.spent = spent; self.income = income
        func day(_ date: Date?, _ rows: [LedgerRowSnapshot]) -> LedgerDaySnapshot {
            var seen: Set<UUID> = []; var refs: Set<URL> = []
            let unique = rows.filter { row in
                guard refs.insert(row.id).inserted else { return false }
                return row.uuid.map { seen.insert($0).inserted } ?? true
            }
            return LedgerDaySnapshot(date: date, rows: unique, net: unique.reduce(0) { $0 + ($1.income ? $1.amount : -$1.amount) })
        }
        var days = groups.keys.sorted(by: >).map { day($0, groups[$0] ?? []) }
        if !undated.isEmpty { days.append(day(nil, undated)) }
        self.days = days
    }
}

public enum LedgerListQuery: Hashable, Sendable {
    case all, recurring, category(URL?), income(Bool), search(String), upcoming(limited: Bool)
    case interval(start: Date, end: Date, income: Bool?, category: URL?)

    public static func insightsDrilldown(date: Date, chartType: Int, income: Bool, environment: AnalyticsEnvironment) -> LedgerListQuery {
        let component: Calendar.Component = chartType == 3 ? .month : .day
        guard LedgerCalendar.isValid(date), let interval = environment.calendar.dateInterval(of: component, for: date) else {
            return .interval(start: .distantFuture, end: .distantFuture, income: income, category: nil)
        }
        return .interval(start: interval.start, end: interval.end, income: income, category: nil)
    }
}

public struct LedgerListRequest: Hashable, Sendable {
    public let query: LedgerListQuery
    public let environment: AnalyticsEnvironment
    public init(query: LedgerListQuery, environment: AnalyticsEnvironment) { self.query = query; self.environment = environment }
}

public struct CategoryTotalSnapshot: Identifiable, Sendable {
    public var id: URL { category.id }
    public let category: AnalyticsCategory
    public let amount: Double
    public let percent: Double
}

public struct PeriodTotals: Sendable {
    public let spent: Double
    public let income: Double
    public var net: Double { income - spent }
    public let average: Double
}

public struct BucketSnapshot: Sendable {
    public let dates: [Date]
    public let totals: [Date: Double]
    public let amount: Double
    public let maximum: Double
    public let average: Double
    public let nonzeroCount: Int
    public let categories: [CategoryTotalSnapshot]
}

public struct InsightsRequest: Hashable, Sendable {
    public let start: Date
    public let type: Int
    public let environment: AnalyticsEnvironment
    public init(start: Date, type: Int, environment: AnalyticsEnvironment) { self.start = start; self.type = type; self.environment = environment }
}

public struct InsightsSnapshot: Sendable {
    public let current: PeriodTotals
    public let previous: PeriodTotals
    public let expenses: BucketSnapshot
    public let income: BucketSnapshot
}

public struct LogRequest: Hashable, Sendable {
    public let timeframe: Int
    public let environment: AnalyticsEnvironment
    public init(timeframe: Int, environment: AnalyticsEnvironment) { self.timeframe = timeframe; self.environment = environment }
}

public struct LogSnapshot: Sendable {
    public let totals: PeriodTotals
    public let netPoints: [LineGraphDataPoint]
    public let incomePoints: [LineGraphDataPoint]
    public let expensePoints: [LineGraphDataPoint]
}

public struct BudgetSnapshot: Identifiable, Sendable {
    public let id: URL
    public let read: BudgetReadSnapshot?
}

public struct BudgetDashboardSnapshot: Sendable {
    public let budgets: [BudgetSnapshot]
    public let main: BudgetSnapshot?
    public let byReference: [URL: BudgetReadSnapshot]
}

public struct LedgerMetadataSnapshot: Sendable {
    public let earliestDate: Date?
    public let latestDate: Date?
    public let hasTransactions: Bool
    public let categories: [AnalyticsCategory]
}

public struct TransactionBoundaryRequest: Hashable, Sendable {
    public let category: URL?
    public let environment: AnalyticsEnvironment
    public init(category: URL?, environment: AnalyticsEnvironment) { self.category = category; self.environment = environment }
}

/// Current windows all end after the captured cutoff. A suffix index answers
/// heterogeneous start boundaries without budget-by-transaction scans or
/// subtracting large prefix sums (which would lose small recent amounts).
private struct ExpenseTimeline {
    let dates: [Date]
    let suffix: [Double]
    init(_ rows: [(Date, Double)]) {
        dates = rows.map { $0.0 }
        var suffix = Array(repeating: 0.0, count: rows.count + 1)
        for index in rows.indices.reversed() { suffix[index] = suffix[index + 1] + rows[index].1 }
        self.suffix = suffix
    }
    func spent(since start: Date) -> Double {
        var lower = 0; var upper = dates.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if dates[middle] < start { lower = middle + 1 } else { upper = middle }
        }
        return suffix[lower]
    }
}

public extension DataController {
    func earliestTransactionDate(_ request: TransactionBoundaryRequest) async throws -> Date? {
        try await performBackgroundRead { context in
            let fetch = Transaction.fetchRequest()
            fetch.fetchLimit = 1
            fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            var predicates = [NSPredicate(format: "date >= %@ AND date <= %@", Date.distantPast as NSDate, Date.distantFuture as NSDate)]
            if let category = request.category { predicates.append(self.categoryPredicate(category, context: context)) }
            fetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            return try self.analyticalFetch(fetch, in: context).first?.date
        }
    }

    func ledgerMetadataSnapshot(environment: AnalyticsEnvironment) async throws -> LedgerMetadataSnapshot {
        try await performBackgroundRead { context in
            let earliest = Transaction.fetchRequest()
            earliest.fetchLimit = 1
            earliest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            earliest.predicate = NSPredicate(format: "date >= %@ AND date <= %@", Date.distantPast as NSDate, Date.distantFuture as NSDate)
            let first = try self.analyticalFetch(earliest, in: context).first?.date
            let latest = Transaction.fetchRequest()
            latest.fetchLimit = 1
            latest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            latest.predicate = NSPredicate(format: "date >= %@ AND date <= %@", Date.distantPast as NSDate, environment.now as NSDate)
            let last = try self.analyticalFetch(latest, in: context).first?.date
            let any = Transaction.fetchRequest(); any.fetchLimit = 1
            let hasTransactions = try first != nil || !self.analyticalFetch(any, in: context).isEmpty
            let categories = Category.fetchRequest(); categories.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
            return LedgerMetadataSnapshot(earliestDate: first, latestDate: last, hasTransactions: hasTransactions, categories: try self.analyticalFetch(categories, in: context).map(AnalyticsCategory.init))
        }
    }

    func logSnapshot(_ request: LogRequest) async throws -> LogSnapshot {
        try await performBackgroundRead { context in
            let environment = request.environment
            let now = environment.now; let calendar = environment.calendar
            guard (1...5).contains(request.timeframe), LedgerCalendar.isValid(now) else { throw LedgerCommandError.invalidInput }
            if request.timeframe == 5 {
                let totals = try self.aggregateTotals(predicate: NSPredicate(format: "date >= %@ AND date <= %@", Date.distantPast as NSDate, now as NSDate), context: context)
                return LogSnapshot(totals: totals, netPoints: [], incomePoints: [], expensePoints: [])
            }
            let period = BudgetPeriod(rawValue: Int16(request.timeframe)) ?? .day
            let summaryStart = CalendarPeriodSelection().start(period: period, now: now, calendar: calendar, firstWeekday: calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth)
            let today = calendar.startOfDay(for: now)
            let component: Calendar.Component = request.timeframe == 4 ? .month : .day
            let graphStart: Date
            if request.timeframe < 3 { graphStart = calendar.date(byAdding: .day, value: -7, to: today)! }
            else if request.timeframe == 3 { graphStart = calendar.date(byAdding: .month, value: -1, to: today)! }
            else { graphStart = calendar.date(byAdding: .year, value: -1, to: calendar.dateInterval(of: .month, for: now)!.start)! }
            let graphEnd = calendar.dateInterval(of: component, for: now)!.end
            let count = calendar.dateComponents([component], from: graphStart, to: graphEnd).value(for: component) ?? 0
            guard count > 0, count <= 366 else { throw LedgerCommandError.invalidInput }
            let dates = (0..<count).compactMap { calendar.date(byAdding: component, value: $0, to: graphStart) }
            var expenses = Dictionary(uniqueKeysWithValues: dates.map { ($0, 0.0) })
            var incomes = expenses
            let fetch = Transaction.fetchRequest()
            fetch.predicate = LedgerCalendar.predicate(start: min(summaryStart, graphStart), end: graphEnd, now: now)
            var spent = 0.0; var income = 0.0
            for row in try self.analyticalFetch(fetch, in: context) {
                guard let date = row.date else { continue }
                if date >= summaryStart {
                    if row.income { income += row.amount } else { spent += row.amount }
                }
                if date >= graphStart, let bucket = calendar.dateInterval(of: component, for: date)?.start {
                    if row.income { incomes[bucket, default: 0] += row.amount }
                    else { expenses[bucket, default: 0] += row.amount }
                }
            }
            // A database aggregate retains carry-in without materializing the old ledger.
            var balance = try self.aggregateTotals(predicate: NSPredicate(format: "date >= %@ AND date < %@", Date.distantPast as NSDate, graphStart as NSDate), context: context).net
            let net = dates.map { date -> LineGraphDataPoint in
                balance += (incomes[date] ?? 0) - (expenses[date] ?? 0)
                return LineGraphDataPoint(date: date, amount: balance)
            }
            return LogSnapshot(totals: PeriodTotals(spent: spent, income: income, average: 0), netPoints: net, incomePoints: dates.map { LineGraphDataPoint(date: $0, amount: incomes[$0] ?? 0) }, expensePoints: dates.map { LineGraphDataPoint(date: $0, amount: expenses[$0] ?? 0) })
        }
    }

    private func aggregateTotals(predicate: NSPredicate, context: NSManagedObjectContext) throws -> PeriodTotals {
        if context.persistentStoreCoordinator?.persistentStores.contains(where: { $0.type == NSInMemoryStoreType }) == true {
            // NSInMemoryStoreType rejects GROUP BY with an Objective-C exception.
            // Preview/test stores use a queue-confined fallback; SQLite keeps its aggregate.
            let fetch = Transaction.fetchRequest()
            fetch.predicate = predicate
            var spent = 0.0; var income = 0.0
            for row in try analyticalFetch(fetch, in: context) {
                if row.income { income += row.amount } else { spent += row.amount }
            }
            return PeriodTotals(spent: spent, income: income, average: 0)
        }
        let sum = NSExpressionDescription()
        sum.name = "total"; sum.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "amount")]); sum.expressionResultType = .doubleAttributeType
        let fetch = NSFetchRequest<NSDictionary>(entityName: "Transaction")
        fetch.resultType = .dictionaryResultType
        fetch.predicate = predicate
        fetch.propertiesToFetch = ["income", sum]
        fetch.propertiesToGroupBy = ["income"]
        var spent = 0.0; var income = 0.0
        for row in try analyticalFetch(fetch, in: context) {
            let amount = (row["total"] as? NSNumber)?.doubleValue ?? 0
            if (row["income"] as? NSNumber)?.boolValue == true { income += amount } else { spent += amount }
        }
        return PeriodTotals(spent: spent, income: income, average: 0)
    }

    func analyticsInsightsSnapshot(_ request: InsightsRequest) async throws -> InsightsSnapshot {
        try await performBackgroundRead { context in
            let environment = request.environment
            let calendar = environment.calendar
            let start = request.start
            let component: Calendar.Component = request.type == 3 ? .month : .day
            guard (1...3).contains(request.type), LedgerCalendar.isValid(start),
                  let end = LedgerCalendar.insightsEnd(start: start, type: request.type, firstDayOfMonth: environment.firstDayOfMonth, calendar: calendar),
                  let previousStart = request.type == 2
                    ? LedgerCalendar.monthStart(in: start, day: environment.firstDayOfMonth, offset: -1, calendar: calendar)
                    : calendar.date(byAdding: request.type == 1 ? .day : .year, value: request.type == 1 ? -7 : -1, to: start) else { throw LedgerCommandError.invalidInput }
            let count = calendar.dateComponents([component], from: start, to: end).value(for: component) ?? 0
            guard count > 0, count <= 366 else { throw LedgerCommandError.invalidInput }
            let dates = (0..<count).compactMap { calendar.date(byAdding: component, value: $0, to: start) }
            let fetch = Transaction.fetchRequest()
            fetch.relationshipKeyPathsForPrefetching = ["category"]
            fetch.predicate = LedgerCalendar.predicate(start: previousStart, end: end, now: environment.now)
            var expenseBuckets = Dictionary(uniqueKeysWithValues: dates.map { ($0, 0.0) })
            var incomeBuckets = expenseBuckets
            var expenseCategories: [AnalyticsCategory: Double] = [:]
            var incomeCategories: [AnalyticsCategory: Double] = [:]
            var spent = 0.0; var income = 0.0; var previousSpent = 0.0; var previousIncome = 0.0
            for row in try self.analyticalFetch(fetch, in: context) {
                guard let date = row.date else { continue }
                if date < start {
                    if row.income { previousIncome += row.amount } else { previousSpent += row.amount }
                    continue
                }
                let bucket = calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
                if row.income { income += row.amount; incomeBuckets[bucket, default: 0] += row.amount }
                else { spent += row.amount; expenseBuckets[bucket, default: 0] += row.amount }
                if let category = row.category, category.income == row.income {
                    let value = AnalyticsCategory(category)
                    if row.income { incomeCategories[value, default: 0] += row.amount }
                    else { expenseCategories[value, default: 0] += row.amount }
                }
            }
            func periods(_ lower: Date, _ upper: Date) -> Double {
                let full = calendar.dateComponents([component], from: lower, to: upper).value(for: component) ?? 0
                let elapsed = calendar.dateComponents([component], from: lower, to: min(environment.now, upper)).value(for: component) ?? 0
                return Double(max(1, environment.now >= upper ? full : min(full, elapsed + 1)))
            }
            let divisor = periods(start, end)
            func buckets(_ amounts: [Date: Double], total: Double, categories: [AnalyticsCategory: Double]) -> BucketSnapshot {
                var shares: [CategoryTotalSnapshot] = []
                for (category, amount) in categories where amount != 0 {
                    shares.append(CategoryTotalSnapshot(category: category, amount: amount, percent: WidgetInsightMath.categoryShare(amount: amount, total: total)))
                }
                shares.sort { lhs, rhs in
                    if lhs.percent == rhs.percent { return lhs.id.absoluteString < rhs.id.absoluteString }
                    return lhs.percent > rhs.percent
                }
                return BucketSnapshot(dates: dates, totals: amounts, amount: total, maximum: amounts.values.filter(\.isFinite).max() ?? 0, average: total.isFinite ? total / divisor : .nan, nonzeroCount: amounts.values.filter { $0 != 0 }.count, categories: shares)
            }
            let net = income - spent; let priorNet = previousIncome - previousSpent
            return InsightsSnapshot(current: PeriodTotals(spent: spent, income: income, average: net.isFinite ? abs(net) / divisor : .nan), previous: PeriodTotals(spent: previousSpent, income: previousIncome, average: priorNet.isFinite ? abs(priorNet) / periods(previousStart, start) : .nan), expenses: buckets(expenseBuckets, total: spent, categories: expenseCategories), income: buckets(incomeBuckets, total: income, categories: incomeCategories))
        }
    }

    func ledgerListSnapshot(_ request: LedgerListRequest) async throws -> LedgerListSnapshot {
        try await performBackgroundRead { context in
            let environment = request.environment
            let fetch = Transaction.fetchRequest()
            fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false), NSSortDescriptor(key: "note", ascending: true)]
            fetch.relationshipKeyPathsForPrefetching = ["category"]
            var predicates: [NSPredicate] = []
            let cap = NSPredicate(format: "date <= %@", environment.now as NSDate)
            switch request.query {
            case .all: predicates = [cap]
            case .recurring: predicates = [cap, NSPredicate(format: "onceRecurring == YES")]
            case let .category(reference):
                predicates = [cap, self.categoryPredicate(reference, context: context)]
            case let .income(income): predicates = [cap, NSPredicate(format: "income == %d", income)]
            case let .interval(start, end, income, category):
                predicates = [LedgerCalendar.predicate(start: start, end: end, now: environment.now)]
                if let income { predicates.append(NSPredicate(format: "income == %d", income)) }
                if let category { predicates.append(self.categoryPredicate(category, context: context)) }
            case let .search(text):
                var matches = [NSPredicate(format: "note BEGINSWITH[cd] %@ OR note CONTAINS[cd] %@ OR category.name CONTAINS[cd] %@", text, text, text)]
                if let amount = Double(text), amount.isFinite { matches.append(NSPredicate(format: "amount == %@", NSNumber(value: amount))) }
                predicates = [NSCompoundPredicate(orPredicateWithSubpredicates: matches)]
            case .upcoming: predicates = [NSPredicate(format: "recurringType > 0 OR date > %@", environment.now as NSDate)]
            }
            fetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            var rows = try self.analyticalFetch(fetch, in: context).map { LedgerRowSnapshot($0, environment: environment) }
            if case let .upcoming(limited) = request.query {
                let limit = environment.calendar.date(byAdding: .day, value: 14, to: environment.calendar.startOfDay(for: environment.now)) ?? environment.now
                rows = rows.filter { row in row.upcomingDate.map { !limited || $0 < limit } ?? false }
                    .sorted { ($0.upcomingDate ?? .distantPast) > ($1.upcomingDate ?? .distantPast) }
            }
            return LedgerListSnapshot(rows: rows, calendar: environment.calendar)
        }
    }

    private func categoryPredicate(_ reference: URL?, context: NSManagedObjectContext) -> NSPredicate {
        guard let reference, let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: reference) else { return NSPredicate(value: false) }
        return NSPredicate(format: "category == %@", id)
    }

    func budgetDashboardSnapshot(environment: AnalyticsEnvironment) async throws -> BudgetDashboardSnapshot {
        try await performBackgroundRead { context in
            let request = Budget.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: true)]
            request.relationshipKeyPathsForPrefetching = ["category"]
            let budgets = try self.analyticalFetch(request, in: context)
            let main = LedgerMaintenance.currentMainBudget(from: try self.analyticalFetch(MainBudget.fetchRequest(), in: context))
            struct Definition {
                let url: URL
                let id: UUID?
                let category: URL?
                let name: String; let emoji: String; let colour: String
                let amount: Double; let type: Int
                let window: BudgetWindow?
            }
            var definitions = budgets.map { Definition(url: $0.objectID.uriRepresentation(), id: $0.id, category: $0.category?.objectID.uriRepresentation(), name: $0.wrappedName, emoji: $0.wrappedEmoji, colour: $0.wrappedColour, amount: $0.amount, type: Int($0.type), window: $0.currentWindow(now: environment.now, calendar: environment.calendar)) }
            if let main { definitions.append(Definition(url: main.objectID.uriRepresentation(), id: nil, category: nil, name: "", emoji: "", colour: "", amount: main.amount, type: Int(main.type), window: main.currentWindow(now: environment.now, calendar: environment.calendar))) }
            let windows = definitions.compactMap(\.window)
            var totals: [URL: Double] = [:]
            if let start = windows.map(\.start).min(), let end = windows.map(\.end).max() {
                let fetch = Transaction.fetchRequest()
                fetch.relationshipKeyPathsForPrefetching = ["category"]
                fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
                fetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [LedgerCalendar.predicate(start: start, end: end, now: environment.now), NSPredicate(format: "income == NO")])
                var byCategory: [URL: [(Date, Double)]] = [:]
                var overall: [(Date, Double)] = []
                for transaction in try self.analyticalFetch(fetch, in: context) {
                    guard let date = transaction.date else { continue }
                    if let category = transaction.category { byCategory[category.objectID.uriRepresentation(), default: []].append((date, transaction.amount)) }
                    if main != nil { overall.append((date, transaction.amount)) }
                }
                let timelines = byCategory.mapValues(ExpenseTimeline.init)
                let overallTimeline = ExpenseTimeline(overall)
                for definition in definitions {
                    guard let window = definition.window else { continue }
                    let timeline = definition.category.flatMap { timelines[$0] }
                    totals[definition.url] = definition.category == nil ? overallTimeline.spent(since: window.start) : (timeline?.spent(since: window.start) ?? 0)
                }
            }
            let snapshots = definitions.map { definition -> BudgetSnapshot in
                let spent = totals[definition.url] ?? 0
                let read: BudgetReadSnapshot?
                if let window = definition.window, spent.isFinite {
                    read = BudgetReadSnapshot(id: definition.id, identifier: definition.id?.uuidString ?? (definition.category == nil ? "overall" : definition.url.absoluteString), name: definition.name, emoji: definition.emoji, colour: definition.colour, amount: definition.amount, spent: spent, type: definition.type, startDate: window.start, endDate: window.end, readDate: environment.now)
                } else { read = nil }
                return BudgetSnapshot(id: definition.url, read: read)
            }
            return BudgetDashboardSnapshot(budgets: Array(snapshots.prefix(budgets.count)), main: main == nil ? nil : snapshots.last, byReference: Dictionary(uniqueKeysWithValues: snapshots.compactMap { row in row.read.map { (row.id, $0) } }))
        }
    }
}
