import CoreData
import Foundation

/// Thread-safe load completion shared by UI publication and async extension readers.
public final class PersistenceReadiness: @unchecked Sendable {
    private let lock = NSLock()
    private var current: DataController.PersistentStoreState = .loading
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    public init() {}

    public var state: DataController.PersistentStoreState {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func resolve(_ state: DataController.PersistentStoreState) {
        guard state != .loading else { return }
        lock.lock()
        current = state
        let pending = waiters.values
        waiters.removeAll()
        lock.unlock()
        for waiter in pending { resume(waiter, state: state) }
    }

    public func wait(timeout: TimeInterval = 10) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let state = current
            if state == .loading { waiters[id] = continuation }
            lock.unlock()
            if state == .loading {
                DispatchQueue.global().asyncAfter(deadline: .now() + max(0, timeout)) { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    let pending = self.waiters.removeValue(forKey: id)
                    self.lock.unlock()
                    pending?.resume(throwing: DataController.PersistentStoreAccessError.loading)
                }
            } else {
                resume(continuation, state: state)
            }
        }
        try Task.checkCancellation()
    }

    private func resume(_ continuation: CheckedContinuation<Void, Error>, state: DataController.PersistentStoreState) {
        switch state {
        case .loaded: continuation.resume()
        case .loading: continuation.resume(throwing: DataController.PersistentStoreAccessError.loading)
        case let .failed(message): continuation.resume(throwing: DataController.PersistentStoreAccessError.failed(message))
        }
    }
}

public enum ExtensionReadStatus: Equatable, Sendable {
    case loading, empty, loaded, failed(String)

    public init(error: Error) {
        if error as? DataController.PersistentStoreAccessError == .loading { self = .loading }
        else { self = .failed(error.localizedDescription) }
    }

    public func nextRefresh(after date: Date) -> Date {
        switch self {
        case .loading, .failed: return date.addingTimeInterval(60)
        case .empty, .loaded: return date.addingTimeInterval(900)
        }
    }

    public var isUnavailable: Bool {
        switch self {
        case .loading, .failed: return true
        case .empty, .loaded: return false
        }
    }
}

/// Every pass is chained, including its main-context merge and atomic token write.
/// Actor isolation alone would not serialize across those suspension points.
struct HistoryTokenWriteError: Error {
    let underlying: Error
    let mergedChanges: Bool
}

actor PersistentHistoryConsumer {
    private var tail: Task<Bool, Error>?

    private struct Changes: Sendable {
        var inserted: [NSManagedObjectID] = []
        var updated: [NSManagedObjectID] = []
        var deleted: [NSManagedObjectID] = []
    }

    func consume(container: NSPersistentContainer, configuration: DataController.Configuration?, localWriterContextName: String) async throws -> Bool {
        guard let configuration, configuration.mode != .inMemory, let storeURL = configuration.storeURL else { return false }
        let previous = tail
        let task = Task {
            _ = try? await previous?.value
            let author = configuration.transactionAuthor.replacingOccurrences(of: "/", with: "_")
            let tokenURL = storeURL.appendingPathExtension("\(author).history-token")
            let tokenData = try? Data(contentsOf: tokenURL)
            let context = container.newBackgroundContext()
            context.transactionAuthor = configuration.transactionAuthor
            let batch = try await context.perform { () throws -> ([Changes], Data?) in
                let token = tokenData.flatMap {
                    try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: $0)
                }
                func fetch(after token: NSPersistentHistoryToken?) throws -> [NSPersistentHistoryTransaction] {
                    let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
                    let result = try context.execute(request) as? NSPersistentHistoryResult
                    return result?.result as? [NSPersistentHistoryTransaction] ?? []
                }
                let transactions: [NSPersistentHistoryTransaction]
                do { transactions = try fetch(after: token) }
                catch {
                    guard token != nil else { throw error }
                    // Expired or store-replaced tokens must not permanently disable imports.
                    transactions = try fetch(after: nil)
                }
                let data = try transactions.last.map {
                    try NSKeyedArchiver.archivedData(withRootObject: $0.token, requiringSecureCoding: true)
                }
                // Local commands and maintenance already merge and publish after commit.
                // Still advance the history token over their transactions without reloading twice.
                let changes = transactions.filter { $0.contextName != localWriterContextName }.map { transaction in
                    var result = Changes()
                    for change in transaction.changes ?? [] {
                        switch change.changeType {
                        case .insert: result.inserted.append(change.changedObjectID)
                        case .update: result.updated.append(change.changedObjectID)
                        case .delete: result.deleted.append(change.changedObjectID)
                        @unknown default: break
                        }
                    }
                    return result
                }
                return (changes, data)
            }
            await container.viewContext.perform {
                for changes in batch.0 {
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [
                        NSInsertedObjectsKey: changes.inserted,
                        NSUpdatedObjectsKey: changes.updated,
                        NSDeletedObjectsKey: changes.deleted
                    ], into: [container.viewContext])
                }
            }
            let merged = batch.0.contains { !$0.inserted.isEmpty || !$0.updated.isEmpty || !$0.deleted.isEmpty }
            do {
                if let data = batch.1 { try data.write(to: tokenURL, options: .atomic) }
            } catch { throw HistoryTokenWriteError(underlying: error, mergedChanges: merged) }
            return merged
        }
        tail = task
        return try await task.value
    }
}

public struct CategorySnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let emoji: String
    public let colour: String
    public let income: Bool
}

public struct BudgetReadSnapshot: Sendable, Equatable {
    public let id: UUID?
    public let identifier: String
    public let name: String
    public let emoji: String
    public let colour: String
    public let amount: Double
    public let spent: Double
    public let type: Int
    public let startDate: Date
    public let endDate: Date
    public let readDate: Date
    public var progress: Double { BudgetWindow.progress(startDate: startDate, endDate: endDate, now: readDate, calendar: .current) }
}

public struct TransactionReadSnapshot: Sendable {
    public let note: String
    public let amount: Double
    public let income: Bool
    public let date: Date
    public let categoryID: UUID?
    public let emoji: String
    public let colour: String
    public let recurringType: Int16

    public init(transaction: Transaction) {
        note = transaction.wrappedNote
        amount = MoneyAmount(transaction.amount)?.value ?? transaction.amount
        income = transaction.income
        date = transaction.wrappedDate
        categoryID = transaction.category?.id
        emoji = transaction.category?.wrappedEmoji ?? ""
        colour = transaction.category?.wrappedColour ?? ""
        recurringType = transaction.recurringType
    }
}

public struct InsightsReadSnapshot: Sendable {
    public let startDate: Date
    public let categories: [CategorySnapshot]
    public let transactions: [TransactionReadSnapshot]
}

public extension DataController {
    func insightsSnapshot(period: LedgerInsightsPeriod, income: Bool) async throws -> InsightsReadSnapshot {
        try await performBackgroundRead { context in
            let request = self.fetchRequestForWidgetInsights(type: period, income: income)
            let transactions = try context.fetch(request.fetchRequest).map(TransactionReadSnapshot.init)
            let categories = try context.fetch(self.fetchRequestForCategories(income: income)).compactMap { category -> CategorySnapshot? in
                guard let id = category.id else { return nil }
                return CategorySnapshot(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, colour: category.wrappedColour, income: category.income)
            }
            return InsightsReadSnapshot(startDate: request.date, categories: categories, transactions: transactions)
        }
    }

    func recentTransactionSnapshots(period: LedgerTimePeriod, count: Int) async throws -> [TransactionReadSnapshot] {
        try await performBackgroundRead { context in
            try context.fetch(self.fetchRequestForRecentTransactionsWithCount(type: period, count: count)).map(TransactionReadSnapshot.init)
        }
    }
    func categorySnapshots(income: Bool) async throws -> [CategorySnapshot] {
        try await performBackgroundRead { context in
            try context.fetch(self.fetchRequestForCategories(income: income)).compactMap { category in
                guard let id = category.id else { return nil }
                return CategorySnapshot(id: id, name: category.wrappedName, emoji: category.wrappedEmoji, colour: category.wrappedColour, income: category.income)
            }
        }
    }

    func budgetSnapshots(now: Date = .now, calendar: Calendar = .current) async throws -> [BudgetReadSnapshot] {
        try await budgetDashboardSnapshot(environment: AnalyticsEnvironment(stamp: AnalyticsStamp(now: now), calendar: calendar)).budgets.compactMap(\.read)
    }

    func budgetSnapshot(identifier: String, now: Date = .now, calendar: Calendar = .current) async throws -> BudgetReadSnapshot? {
        try await performBackgroundRead { context in
            let budget: Budget?
            if let id = UUID(uuidString: identifier) {
                let request = Budget.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                budget = try context.fetch(request).first
            } else if let url = URL(string: identifier),
                      let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url) {
                // Existing widget selections remain usable on their original compatible store.
                budget = try context.existingObject(with: id) as? Budget
            } else { budget = nil }
            guard let budget else { return nil }
            return try self.snapshot(budget: budget, context: context, now: now, calendar: calendar)
        }
    }

    private func snapshot(budget: Budget, context: NSManagedObjectContext, now: Date, calendar: Calendar) throws -> BudgetReadSnapshot? {
        guard let window = budget.currentWindow(now: now, calendar: calendar) else { return nil }
        let spent = try analyticalFetch(fetchRequestForBudgetTransactions(budget: budget, now: now, calendar: calendar), in: context).reduce(0) { $0 + $1.amount }
        guard spent.isFinite, budget.amount.isFinite else { return nil }
        return BudgetReadSnapshot(id: budget.id, identifier: budget.id?.uuidString ?? budget.objectID.uriRepresentation().absoluteString,
                                  name: budget.wrappedName, emoji: budget.wrappedEmoji, colour: budget.wrappedColour,
                                  amount: budget.amount, spent: spent, type: Int(budget.type), startDate: window.start, endDate: window.end, readDate: now)
    }

    func mainBudgetSnapshot(now: Date = .now, calendar: Calendar = .current) async throws -> BudgetReadSnapshot? {
        try await performBackgroundRead { context in
            guard let budget = try LedgerMaintenance.currentMainBudget(in: context),
                  let window = budget.currentWindow(now: now, calendar: calendar) else { return nil }
            let spent = try context.fetch(self.fetchRequestForMainBudgetTransactions(budget: budget, now: now, calendar: calendar)).reduce(0) { $0 + $1.amount }
            guard spent.isFinite, budget.amount.isFinite else { return nil }
            return BudgetReadSnapshot(id: nil, identifier: "overall", name: "", emoji: "", colour: "", amount: budget.amount,
                                      spent: spent, type: Int(budget.type), startDate: window.start, endDate: window.end, readDate: now)
        }
    }

    func transactionSnapshots(type: Int, income: Bool?, categoryIDs: [UUID] = []) async throws -> [TransactionReadSnapshot] {
        try await performBackgroundRead { context in
            let request = self.fetchRequestForLogView(type: type, optionalIncome: income)
            if !categoryIDs.isEmpty {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    request.predicate ?? NSPredicate(value: true), NSPredicate(format: "category.id IN %@", categoryIDs)
                ])
            }
            return try context.fetch(request).map(TransactionReadSnapshot.init)
        }
    }
}
