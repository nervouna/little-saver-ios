import CoreData
import Foundation

public enum LedgerCommandError: LocalizedError {
    case invalidInput, missingRecord, duplicateCategory, restoreConflict, submissionPending
    public var errorDescription: String? {
        switch self {
        case .submissionPending: return String(localized: "Another change is being saved. Please try again.")
        case .invalidInput: return String(localized: "Please check the entered values.")
        case .missingRecord: return String(localized: "This record is no longer available.")
        case .duplicateCategory: return String(localized: "Duplicate Found")
        case .restoreConflict: return String(localized: "This transaction cannot be restored because its schedule has changed.")
        }
    }
}

/// References contain only immutable identifiers, never queue-confined managed objects.
public enum LedgerReference: Sendable {
    case object(URL)
    case category(UUID)
    public init(_ object: NSManagedObject) { self = .object(object.objectID.uriRepresentation()) }

    func resolve<T: NSManagedObject>(in context: NSManagedObjectContext, as type: T.Type) throws -> T {
        let object: NSManagedObject?
        switch self {
        case let .object(uri):
            guard let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri) else { throw LedgerCommandError.missingRecord }
            object = try context.existingObject(with: id)
        case let .category(id):
            let request = Category.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            object = try context.fetch(request).first
        }
        guard let result = object as? T, !result.isDeleted else { throw LedgerCommandError.missingRecord }
        return result
    }
}

public struct TransactionInput: Sendable {
    public let reference: LedgerReference?
    public let category: LedgerReference?
    public let note: String
    public let income: Bool
    public let amount: Double
    public let date: Date
    public let repeatType: Int
    public let repeatCoefficient: Int
    public init(reference: LedgerReference? = nil, category: LedgerReference?, note: String, income: Bool, amount: Double, date: Date, repeatType: Int = 0, repeatCoefficient: Int = 1) {
        self.reference = reference; self.category = category; self.note = note; self.income = income
        self.amount = amount; self.date = date; self.repeatType = repeatType; self.repeatCoefficient = repeatCoefficient
    }
}

public struct CategoryInput: Sendable {
    public let reference: LedgerReference?
    public let name: String
    public let emoji: String
    public let colour: String
    public let income: Bool
    public init(reference: LedgerReference? = nil, name: String, emoji: String, colour: String, income: Bool) {
        self.reference = reference; self.name = name; self.emoji = emoji; self.colour = colour; self.income = income
    }
}

private enum LedgerAttribute: Sendable {
    case string(String), date(Date), uuid(UUID), number(Double), integer(Int64), boolean(Bool)
    var value: Any {
        switch self {
        case let .string(value): return value
        case let .date(value): return value
        case let .uuid(value): return value
        case let .number(value): return value
        case let .integer(value): return value
        case let .boolean(value): return value
        }
    }
}

private struct LedgerRecordSnapshot: Sendable {
    let attributes: [String: LedgerAttribute]
    let reference: LedgerReference
    let category: LedgerReference?
    init(_ object: NSManagedObject) {
        reference = LedgerReference(object)
        category = (object.value(forKey: "category") as? Category).map(LedgerReference.init)
        var values: [String: LedgerAttribute] = [:]
        for (key, description) in object.entity.attributesByName {
            guard let value = object.value(forKey: key) else { continue }
            switch description.attributeType {
            case .stringAttributeType: values[key] = .string(value as! String)
            case .dateAttributeType: values[key] = .date(value as! Date)
            case .UUIDAttributeType: values[key] = .uuid(value as! UUID)
            case .booleanAttributeType: values[key] = .boolean((value as! NSNumber).boolValue)
            case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType: values[key] = .integer((value as! NSNumber).int64Value)
            default: values[key] = .number((value as! NSNumber).doubleValue)
            }
        }
        attributes = values
    }
    func apply(to object: NSManagedObject, in context: NSManagedObjectContext) throws {
        for key in object.entity.attributesByName.keys { object.setValue(attributes[key]?.value, forKey: key) }
        object.setValue(try category?.resolve(in: context, as: Category.self), forKey: "category")
    }
}

public struct TransactionDeletionSnapshot: Sendable {
    fileprivate let transaction: LedgerRecordSnapshot
    fileprivate let stoppedSeries: [LedgerRecordSnapshot]
    fileprivate let stoppedAt: Date
    fileprivate let predecessorKey: String
}

extension DataController {
    /// Commands and recurring maintenance share this queue. The private rollback never
    /// touches unsaved view-context editor changes.
    func performCommand<T: Sendable>(_ body: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await waitUntilReady()
        let context = maintenanceContext
        let save = commandSave
        let viewContext = container.viewContext
        let committed = try await context.perform { () throws -> (T, [String: [NSManagedObjectID]], Bool) in
            context.reset()
            let maintenanceMergePolicy = context.mergePolicy
            context.mergePolicy = NSErrorMergePolicy
            defer { context.mergePolicy = maintenanceMergePolicy }
            do {
                let value = try body(context)
                context.processPendingChanges()
                let changed = context.hasChanges
                try context.obtainPermanentIDs(for: Array(context.insertedObjects))
                let changes = [
                    NSInsertedObjectsKey: context.insertedObjects.map(\.objectID),
                    NSUpdatedObjectsKey: context.updatedObjects.map(\.objectID),
                    NSDeletedObjectsKey: context.deletedObjects.map(\.objectID)
                ]
                if changed { try save(context) }
                return (value, changes, changed)
            } catch {
                context.rollback()
                throw error
            }
        }
        await viewContext.perform {
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: committed.1, into: [viewContext])
        }
        if committed.2 { await MainActor.run { self.refreshAnalytics() } }
        if committed.2, configuration?.reloadWidgetsAfterSave == true {
            await MainActor.run { self.reloadWidgets() }
        }
        if committed.2 { continueMaintenance() }
        return committed.0
    }

    public func deleteAll() async throws {
        try await performCommand { context in
            for entity in context.persistentStoreCoordinator!.managedObjectModel.entities {
                guard let name = entity.name else { continue }
                for object in try context.fetch(NSFetchRequest<NSManagedObject>(entityName: name)) {
                    context.delete(object)
                }
            }
        }
    }

    @discardableResult
    public func saveCategory(_ input: CategoryInput) async throws -> LedgerReference {
        try await performCommand { context in
            let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
            guard !name.isEmpty, !input.emoji.isEmpty else { throw LedgerCommandError.invalidInput }
            let existing = try input.reference?.resolve(in: context, as: Category.self)
            let categories = try context.fetch(Category.fetchRequest()).filter { $0.income == input.income }
            guard !categories.contains(where: { $0 != existing && ($0.name?.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.emoji == input.emoji) }) else {
                throw LedgerCommandError.duplicateCategory
            }
            let category = existing ?? Category(context: context)
            if existing == nil {
                category.id = UUID(); category.dateCreated = Date()
                category.order = (categories.map(\.order).max() ?? -1) + 1
            }
            category.name = name; category.emoji = input.emoji
            category.colour = input.income ? "IncomeGreen" : input.colour
            category.income = input.income
            try context.obtainPermanentIDs(for: [category])
            return LedgerReference(category)
        }
    }

    public func deleteCategories(_ references: [LedgerReference]) async throws {
        try await performCommand { context in
            for reference in references { context.delete(try reference.resolve(in: context, as: Category.self)) }
        }
    }

    public func reorderCategories(_ references: [LedgerReference]) async throws {
        try await performCommand { context in
            for (order, reference) in references.enumerated() {
                try reference.resolve(in: context, as: Category.self).order = Int64(order)
            }
        }
    }

    @discardableResult
    public func saveTransaction(_ input: TransactionInput) async throws -> TransactionReadSnapshot {
        try await performCommand { context in
            let transaction = try Self.applyTransaction(input, in: context)
            try context.obtainPermanentIDs(for: [transaction])
            return TransactionReadSnapshot(transaction: transaction)
        }
    }

    static func applyTransaction(_ input: TransactionInput, in context: NSManagedObjectContext) throws -> Transaction {
        guard let amount = MoneyAmount(input.amount), amount.value >= 0, LedgerCalendar.isValid(input.date),
              (0...3).contains(input.repeatType), (1...Int(Int16.max)).contains(input.repeatCoefficient) else { throw LedgerCommandError.invalidInput }
        let category = try input.category?.resolve(in: context, as: Category.self)
        let existing = try input.reference?.resolve(in: context, as: Transaction.self)
        let transaction = existing ?? Transaction(context: context)
        if existing == nil {
            transaction.id = UUID()
            transaction.deduplicationToken = UUID().uuidString.lowercased()
        }
        else {
            LedgerMaintenance.markUserEdit(transaction)
            if transaction.seriesID != nil, transaction.date != input.date { transaction.scheduleDateOverridden = true }
        }
        transaction.note = input.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? category?.wrappedName ?? "" : input.note.trimmingCharacters(in: .whitespaces)
        transaction.category = category; transaction.income = input.income
        transaction.amount = amount.value; transaction.date = input.date
        let calendar = Calendar.current
        transaction.day = calendar.startOfDay(for: input.date)
        transaction.month = calendar.date(from: calendar.dateComponents([.month, .year], from: input.date))
        if input.repeatType == 0, transaction.recurringType > 0 { try LedgerMaintenance.stopSeries(for: transaction, in: context) }
        transaction.recurringType = Int16(input.repeatType)
        transaction.recurringCoefficient = Int16(input.repeatCoefficient)
        transaction.onceRecurring = input.repeatType > 0
        if input.repeatType > 0 { try LedgerMaintenance.replaceSeries(for: transaction, in: context) }
        return transaction
    }

    public func stopRecurringTransaction(_ reference: LedgerReference) async throws {
        try await performCommand { context in
            let transaction = try reference.resolve(in: context, as: Transaction.self)
            LedgerMaintenance.markUserEdit(transaction)
            try LedgerMaintenance.stopSeries(for: transaction, in: context)
        }
    }

    public func deleteTransaction(_ reference: LedgerReference) async throws -> TransactionDeletionSnapshot {
        try await performCommand { context in
            let transaction = try reference.resolve(in: context, as: Transaction.self)
            guard let predecessorKey = LedgerMaintenance.effectiveTransactionKey(transaction) else { throw LedgerCommandError.missingRecord }
            let snapshot = LedgerRecordSnapshot(transaction)
            let series = try context.fetch(RecurringSeries.fetchRequest()).filter {
                transaction.recurringType > 0 && $0.logicalID == transaction.seriesID && $0.stoppedAt == nil
            }
            let stopped = series.map(LedgerRecordSnapshot.init)
            let stoppedAt = Date()
            for item in series { item.stoppedAt = stoppedAt }
            let suppression = RecurringSuppression(context: context)
            suppression.occurrenceKey = predecessorKey
            context.delete(transaction)
            return TransactionDeletionSnapshot(transaction: snapshot, stoppedSeries: stopped, stoppedAt: stoppedAt, predecessorKey: predecessorKey)
        }
    }

    public func restoreTransaction(_ snapshot: TransactionDeletionSnapshot) async throws {
        try await performCommand { context in
            if case let .uuid(id)? = snapshot.transaction.attributes["id"],
               try context.fetch(Transaction.fetchRequest()).contains(where: { $0.id == id }) {
                throw LedgerCommandError.restoreConflict
            }
            let transaction = Transaction(context: context)
            try snapshot.transaction.apply(to: transaction, in: context)
            transaction.deduplicationToken = UUID().uuidString.lowercased()
            // The successor belongs to the predecessor, not to a local Undo event.
            // Concurrent peers therefore restore one logical incarnation, while each
            // physical row receives its own independent deduplication token above.
            // Keep every predecessor suppression, including across repeated Undo chains.
            let successor = snapshot.predecessorKey + "/undo:next"
            guard try !context.fetch(RecurringSuppression.fetchRequest()).contains(where: { $0.occurrenceKey == successor }) else {
                throw LedgerCommandError.restoreConflict
            }
            transaction.occurrenceKey = successor
            if let saved = snapshot.stoppedSeries.first {
                // Stopping is monotonic for an existing generation. Undo appends a new
                // generation with the exact saved plan, so a late stopped peer cannot
                // silently stop the restored schedule again.
                let old = try saved.reference.resolve(in: context, as: RecurringSeries.self)
                guard old.stoppedAt == snapshot.stoppedAt else { throw LedgerCommandError.restoreConflict }
                let latest = try context.fetch(RecurringSeries.fetchRequest()).filter {
                    ($0.familyID ?? $0.logicalID) == (old.familyID ?? old.logicalID)
                }.max {
                    if $0.createdAt != $1.createdAt { return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                    return ($0.logicalID ?? "") < ($1.logicalID ?? "")
                }
                guard latest?.logicalID == old.logicalID else { throw LedgerCommandError.restoreConflict }
                let replacement = RecurringSeries(context: context)
                try saved.apply(to: replacement, in: context)
                replacement.logicalID = UUID().uuidString.lowercased()
                replacement.deduplicationToken = UUID().uuidString.lowercased()
                replacement.createdAt = Date()
                replacement.stoppedAt = nil
                transaction.seriesID = replacement.logicalID
            }
            if transaction.seriesID != nil { LedgerMaintenance.markUserEdit(transaction) }
        }
    }

    public func saveTemplate(_ input: TransactionInput, order: Int) async throws {
        try await performCommand { context in
            guard let amount = MoneyAmount(input.amount), amount.value >= 0, (0...3).contains(input.repeatType),
                  (1...Int(Int16.max)).contains(input.repeatCoefficient), (0...Int(Int16.max)).contains(order) else { throw LedgerCommandError.invalidInput }
            let category = try input.category?.resolve(in: context, as: Category.self)
            let existing = try input.reference?.resolve(in: context, as: TemplateTransaction.self)
            let template = existing ?? TemplateTransaction(context: context)
            if existing == nil { template.id = UUID(); template.order = Int16(order) }
            template.category = category
            template.note = input.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category?.wrappedName ?? "" : input.note.trimmingCharacters(in: .whitespaces)
            template.income = input.income; template.amount = amount.value
            template.recurringType = Int16(input.repeatType); template.recurringCoefficient = Int16(input.repeatCoefficient)
        }
    }

    public func deleteTemplate(_ reference: LedgerReference) async throws {
        try await performCommand { context in context.delete(try reference.resolve(in: context, as: TemplateTransaction.self)) }
    }

    public func reorderTemplates(_ references: [(LedgerReference, Int)]) async throws {
        try await performCommand { context in
            for (reference, order) in references {
                guard (0...Int(Int16.max)).contains(order) else { throw LedgerCommandError.invalidInput }
                try reference.resolve(in: context, as: TemplateTransaction.self).order = Int16(order)
            }
        }
    }

    public func newTemplateTransaction(order: Int) async throws -> TransactionReadSnapshot {
        let result = try await performCommand { context in
            let request = TemplateTransaction.fetchRequest()
            request.predicate = NSPredicate(format: "order == %d", order)
            guard let template = try context.fetch(request).sorted(by: { $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString }).first,
                  let category = template.category else { throw LedgerCommandError.missingRecord }
            let input = TransactionInput(category: LedgerReference(category), note: template.note ?? "", income: template.income, amount: template.amount, date: Date(), repeatType: Int(template.recurringType), repeatCoefficient: max(1, Int(template.recurringCoefficient)))
            let transaction = try Self.applyTransaction(input, in: context)
            try context.obtainPermanentIDs(for: [transaction])
            return TransactionReadSnapshot(transaction: transaction)
        }
        await MainActor.run { self.addedTransaction = true }
        return result
    }

    public func saveBudget(reference: LedgerReference? = nil, category: LedgerReference, amount: Double, startDate: Date, type: Int16) async throws {
        try await performCommand { context in
            guard let money = MoneyAmount(amount), BudgetPeriod(rawValue: type)?.currentWindow(anchor: startDate, amount: money.value) != nil else { throw LedgerCommandError.invalidInput }
            let existing = try reference?.resolve(in: context, as: Budget.self)
            let budget = existing ?? Budget(context: context)
            if existing == nil { budget.id = UUID(); budget.dateCreated = Date() }
            budget.category = try category.resolve(in: context, as: Category.self)
            budget.amount = money.value; budget.startDate = startDate; budget.type = type
        }
    }

    public func deleteBudget(_ reference: LedgerReference) async throws {
        try await performCommand { context in context.delete(try reference.resolve(in: context, as: Budget.self)) }
    }

    public func upsertMainBudget(amount: Double, startDate: Date, type: Int16) async throws {
        try await performCommand { context in
            guard let money = MoneyAmount(amount), BudgetPeriod(rawValue: type)?.currentWindow(anchor: startDate, amount: money.value) != nil else { throw LedgerCommandError.invalidInput }
            try LedgerMaintenance.upsertMainBudget(in: context, amount: money.value, startDate: startDate, type: type)
        }
    }

    public func deleteMainBudget() async throws {
        try await performCommand { context in try LedgerMaintenance.deleteMainBudget(in: context) }
    }

}
