//
//  DataController.swift
//  Bonsai
//
//  Created by Rafael Soh on 3/6/22.
//

import CoreData
import Foundation
import SwiftUI
import WidgetKit

@available(iOS 16, *)
enum CustomError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notFound,
         coreDataSave,
         unknownId(id: String),
         unknownError(message: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unknownError(message): return "An unknown error occurred: \(message)"
        case let .unknownId(id): return "No category with an ID matching: \(id)"
        case .notFound: return "Category not found"
        case .coreDataSave: return "Couldn't save to CoreData"
        }
    }
}

class DataController: ObservableObject {
    enum CloudKitSchemaInitializationPolicy {
        static func shouldInitialize(
            mode: PersistentStoreMode,
            arguments: [String],
            isDebugBuild: Bool
        ) -> Bool {
            isDebugBuild
                && mode == .cloudSync
                && arguments.contains("--initialize-cloudkit-schema")
        }
    }

    private static let managedObjectModel: NSManagedObjectModel? = {
        guard let modelURL = Bundle.main.url(
            forResource: AppIdentifiers.persistentModel,
            withExtension: "momd"
        ) ?? Bundle(for: DataController.self).url(
            forResource: AppIdentifiers.persistentModel,
            withExtension: "momd"
        ) else {
            return nil
        }
        return NSManagedObjectModel(contentsOf: modelURL)
    }()

    enum PersistentStoreState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum PersistentStoreAccessError: LocalizedError {
        case loading
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .loading:
                return String(localized: "The persistent store is still loading.")
            case let .failed(message):
                return String(localized: "The persistent store is unavailable: \(message)")
            }
        }
    }

    struct Configuration {
        let mode: PersistentStoreMode
        let modelName: String
        let storeURL: URL?
        let reloadWidgetsAfterSave: Bool

        static func currentProcess(
            bundleIdentifier: String? = Bundle.main.bundleIdentifier,
            fileManager: FileManager = .default
        ) throws -> Configuration {
            let role = try AppRuntimeRole(bundleIdentifier: bundleIdentifier)
            guard let mode = role.persistentStoreMode else {
                throw AppConfigurationError.unknownBundleIdentifier(bundleIdentifier)
            }
            guard let groupURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup
            ) else {
                throw AppConfigurationError.unavailableAppGroup(AppIdentifiers.appGroup)
            }
            return Configuration(
                mode: mode,
                modelName: AppIdentifiers.persistentModel,
                storeURL: groupURL.appendingPathComponent(AppIdentifiers.persistentStore),
                reloadWidgetsAfterSave: true
            )
        }

        static var inMemory: Configuration {
            Configuration(
                mode: .inMemory,
                modelName: AppIdentifiers.persistentModel,
                storeURL: nil,
                reloadWidgetsAfterSave: false
            )
        }
    }

    static let shared: DataController = {
        do {
            if ProcessInfo.processInfo.isRunningUnitTests {
                return try DataController(configuration: .inMemory)
            }
            return try DataController(configuration: .currentProcess())
        } catch {
            return DataController(configurationError: error)
        }
    }()

    let container: NSPersistentCloudKitContainer
    let configuration: Configuration?
    @Published private(set) var persistentStoreState: PersistentStoreState = .loading

    private init(configurationError error: Error) {
        configuration = nil
        container = NSPersistentCloudKitContainer(
            name: AppIdentifiers.persistentModel,
            managedObjectModel: NSManagedObjectModel()
        )
        persistentStoreState = .failed(error.localizedDescription)
    }

    init(configuration: Configuration) throws {
        self.configuration = configuration

        guard configuration.modelName == AppIdentifiers.persistentModel,
              let model = Self.managedObjectModel else {
            throw AppConfigurationError.unavailableManagedObjectModel(configuration.modelName)
        }

        container = NSPersistentCloudKitContainer(
            name: configuration.modelName,
            managedObjectModel: model
        )

        let description = NSPersistentStoreDescription()

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        switch configuration.mode {
        case .cloudSync:
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: AppIdentifiers.cloudKitContainer
            )
            description.url = configuration.storeURL
        case .sharedLocal:
            description.cloudKitContainerOptions = nil
            description.url = configuration.storeURL
        case .inMemory:
            description.type = NSInMemoryStoreType
            description.cloudKitContainerOptions = nil
        }

        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in

            if let error {
                self.publishPersistentStoreState(.failed(error.localizedDescription))
                return
            }

            #if DEBUG
            if CloudKitSchemaInitializationPolicy.shouldInitialize(
                mode: configuration.mode,
                arguments: ProcessInfo.processInfo.arguments,
                isDebugBuild: true
            ) {
                do {
                    try self.container.initializeCloudKitSchema(options: [])
                } catch {
                    NSLog("CloudKit schema initialization failed: %@", error.localizedDescription)
                    self.publishPersistentStoreState(.failed(String(localized: "CloudKit schema initialization failed.")))
                    return
                }
            }
            #endif

            self.container.viewContext.performAndWait {
                self.container.viewContext.automaticallyMergesChangesFromParent = true
                self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            }
            self.publishPersistentStoreState(.loaded)
        }

    }

    private func publishPersistentStoreState(_ state: PersistentStoreState) {
        if Thread.isMainThread {
            persistentStoreState = state
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.persistentStoreState = state
            }
        }
    }

    // internal variables

    var addedTransaction: Bool {
        get {
            UserDefaults(suiteName: AppIdentifiers.appGroup)?.bool(forKey: "newTransactionAdded") ?? false
        }

        set {
            UserDefaults(suiteName: AppIdentifiers.appGroup)?.set(newValue, forKey: "newTransactionAdded")
        }
    }

    // adding or deleting

    func deleteAll() {
        guard persistentStoreState == .loaded else { return }
        let fetchRequest1: NSFetchRequest<NSFetchRequestResult> = Transaction.fetchRequest()
        let batchDeleteRequest1 = NSBatchDeleteRequest(fetchRequest: fetchRequest1)
        _ = try? container.viewContext.executeAndMergeChanges(using: batchDeleteRequest1)

        let fetchRequest2: NSFetchRequest<NSFetchRequestResult> = Category.fetchRequest()
        let batchDeleteRequest2 = NSBatchDeleteRequest(fetchRequest: fetchRequest2)
        _ = try? container.viewContext.executeAndMergeChanges(using: batchDeleteRequest2)

        let fetchRequest3: NSFetchRequest<NSFetchRequestResult> = Budget.fetchRequest()
        let batchDeleteRequest3 = NSBatchDeleteRequest(fetchRequest: fetchRequest3)
        _ = try? container.viewContext.executeAndMergeChanges(using: batchDeleteRequest3)

        let fetchRequest4: NSFetchRequest<NSFetchRequestResult> = MainBudget.fetchRequest()
        let batchDeleteRequest4 = NSBatchDeleteRequest(fetchRequest: fetchRequest4)
        _ = try? container.viewContext.executeAndMergeChanges(using: batchDeleteRequest4)
    }

    func save() {
        guard persistentStoreState == .loaded else { return }
        if container.viewContext.hasChanges {
            try? container.viewContext.save()
            if configuration?.reloadWidgetsAfterSave == true {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    func updateRecurringTransaction(transaction: Transaction) {
        if transaction.nextTransactionDate < Calendar.current.startOfDay(for: Date.now) {
            var holdingDate = transaction.nextTransactionDate

            while holdingDate <= Calendar.current.startOfDay(for: Date.now) {
                let newTransaction = Transaction(context: container.viewContext)
                newTransaction.note = transaction.wrappedNote
                newTransaction.category = transaction.category
                newTransaction.amount = transaction.wrappedAmount
                newTransaction.date = holdingDate
                newTransaction.id = UUID()
                newTransaction.income = transaction.income
                newTransaction.day = holdingDate

                let calendar = Calendar(identifier: .gregorian)

                let dateComponents = calendar.dateComponents([.month, .year], from: holdingDate)

                newTransaction.month = calendar.date(from: dateComponents)!

                newTransaction.onceRecurring = true

                guard let newDate = try? RecurringSchedule.nextDate(
                    after: holdingDate,
                    type: transaction.recurringType,
                    coefficient: transaction.recurringCoefficient,
                    calendar: .current
                ) else {
                    transaction.recurringType = 0
                    break
                }

                if newDate > Calendar.current.startOfDay(for: Date.now) {
                    newTransaction.recurringType = transaction.recurringType
                    newTransaction.recurringCoefficient = transaction.recurringCoefficient
                } else {
                    newTransaction.recurringType = 0
                }

                holdingDate = newDate
            }

            transaction.recurringType = 0

            save()

        } else if Calendar.current.isDateInToday(transaction.nextTransactionDate) {
            let newTransaction = Transaction(context: container.viewContext)
            newTransaction.note = transaction.wrappedNote
            newTransaction.category = transaction.category
            newTransaction.amount = transaction.wrappedAmount
            newTransaction.date = transaction.nextTransactionDate
            newTransaction.id = UUID()
            newTransaction.income = transaction.income
            newTransaction.day = transaction.nextTransactionDate

            let calendar = Calendar(identifier: .gregorian)

            let dateComponents = calendar.dateComponents([.month, .year], from: transaction.nextTransactionDate)

            newTransaction.month = calendar.date(from: dateComponents)!

            newTransaction.onceRecurring = true
            newTransaction.recurringType = transaction.recurringType
            newTransaction.recurringCoefficient = transaction.recurringCoefficient

            transaction.recurringType = 0

            save()
        }
    }

    func updateRecurringTransactions() {
        let recurringTransactions = results(for: fetchRequestForRecurringTransactions())

        recurringTransactions.forEach { transaction in
            updateRecurringTransaction(transaction: transaction)
        }
    }

    func updateBudgetDates() {
        let budgets = results(for: fetchRequestForBudgets())
        let mainBudget = results(for: fetchRequestForMainBudget())

        budgets.forEach { budget in
            while budget.endDate <= Date.now {
                budget.startDate = budget.endDate
            }
        }

        mainBudget.forEach { budget in
            while budget.endDate <= Date.now {
                budget.startDate = budget.endDate
            }
        }

        save()
    }

    func newTransaction(note: String, category: Category?, income: Bool, amount: Double, date: Date, repeatType: Int, repeatCoefficient: Int, delay _: Bool) -> Transaction {
        let transaction = Transaction(context: container.viewContext)

        if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            transaction.note = category?.wrappedName ?? ""
        } else {
            transaction.note = note.trimmingCharacters(in: .whitespaces)
        }

        transaction.income = income

        if let unwrappedCategory = category {
            transaction.category = unwrappedCategory
        }

        transaction.amount = amount
        transaction.date = date
        transaction.id = UUID()

        let calendar = Calendar(identifier: .gregorian)

        transaction.day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now

        let dateComponents = calendar.dateComponents([.month, .year], from: date)

        transaction.month = calendar.date(from: dateComponents) ?? Date.now

        if repeatType > 0 {
            transaction.onceRecurring = true
            transaction.recurringType = Int16(repeatType)
            transaction.recurringCoefficient = Int16(repeatCoefficient)
            updateRecurringTransaction(transaction: transaction)
        }

        save()

        return transaction
    }

    func newTemplateTransaction(order: Int) {
        if let match = getTemplateTransaction(order: order) {
            if let unwrappedCategory = match.category {
                _ = newTransaction(note: match.note ?? "", category: unwrappedCategory, income: match.income, amount: match.amount, date: Date.now, repeatType: Int(match.recurringType), repeatCoefficient: Int(match.recurringCoefficient), delay: false)

                addedTransaction = true
            }
        }
    }

    // fetching

    func fetchRequestForRecurringTransactions() -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "%K > %i", #keyPath(Transaction.recurringType), 0)
        return itemRequest
    }

    func getTemplateTransaction(order: Int) -> TemplateTransaction? {
        let itemRequest: NSFetchRequest<TemplateTransaction> = TemplateTransaction.fetchRequest()

        itemRequest.predicate = NSPredicate(format: "order == %d", order)

        let results = results(for: itemRequest)

        if results.count > 1 {
            let output = results.first

            for i in 1 ..< results.count {
                container.viewContext.delete(results[i])
            }

            save()

            return output
        } else {
            return results.first
        }
    }

    func getAllTemplateTransactions() -> [TemplateTransaction] {
        let itemRequest: NSFetchRequest<TemplateTransaction> = TemplateTransaction.fetchRequest()

        return results(for: itemRequest)
    }

    func fetchRequestForRecentTransactions(type: TimePeriod) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstWeekday") ?? 1
        calendar.minimumDaysInFirstWeek = 4

        switch type {
        case .unknown:
            return itemRequest
        case .day:
            let today = calendar.startOfDay(for: Date.now)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: today)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextDay as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let thisWeek = calendar.date(from: dateComponents)!
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: thisWeek)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextWeek as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .month:
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)

            let thisMonth = calendar.date(from: dateComponents)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextMonth as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let thisYear = calendar.date(from: dateComponents)!
            let nextYear = calendar.date(byAdding: .year, value: 1, to: thisYear)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), nextYear as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]

            return itemRequest
        }
    }

    func fetchRequestForExport() -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return itemRequest
    }

    func fetchRequestForCategoriesMigration(income: Bool? = nil) -> NSFetchRequest<Category> {
        let itemRequest: NSFetchRequest<Category> = Category.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: true)]

        if let unwrappedIncome = income {
            itemRequest.predicate = NSPredicate(format: "income = %d", unwrappedIncome)
            return itemRequest
        } else {
            return itemRequest
        }
    }

    func fetchRequestForCategories(income: Bool) -> NSFetchRequest<Category> {
        let itemRequest: NSFetchRequest<Category> = Category.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        itemRequest.predicate = NSPredicate(format: "income = %d", income)
        return itemRequest
    }

    func getAllCategories(income: Bool) -> [Category] {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        request.predicate = NSPredicate(format: "income = %d", income)

        return results(for: request)
    }

    func getSuggestedNotes(searchQuery: String, category: Category?, income: Bool) -> [Transaction] {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]

        let beginPredicate = NSPredicate(format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), searchQuery)
        let containPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), searchQuery)
        let compound = NSCompoundPredicate(orPredicateWithSubpredicates: [beginPredicate, containPredicate])

        let incomePredicate = NSPredicate(format: "income = %d", income)

        if let unwrappedCategory = category {
            let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [compound, categoryPredicate, incomePredicate])

            itemRequest.predicate = andPredicate
        } else {
            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [compound, incomePredicate])
            itemRequest.predicate = andPredicate
        }

        let transactions = results(for: itemRequest)

        var seen = [Transaction]()
        let filtered = transactions.filter { entity -> Bool in
            if seen.contains(where: { $0.wrappedNote == entity.wrappedNote }) {
                return false
            } else {
                seen.append(entity)
                return true
            }
        }

        return filtered
//
//        let notes = transactions.map { $0.wrappedNote }
//
//        return Array(Set(notes))
    }

    @available(iOS 16, *)
    func findCategory(withId id: UUID) throws -> Category {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id = %@", id as CVarArg)

        do {
            guard let foundCategory = try container.viewContext.fetch(request).first else {
                throw CustomError.notFound
            }
            return foundCategory
        } catch {
            throw CustomError.notFound
        }
    }

    func getAllBudgets() -> [Budget] {
        let request: NSFetchRequest<Budget> = Budget.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: true)]
        return results(for: request)
    }

    @available(iOS 16, *)
    func findBudget(withId id: UUID) throws -> Budget {
        let request: NSFetchRequest<Budget> = Budget.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id = %@", id as CVarArg)

        do {
            guard let foundBudget = try container.viewContext.fetch(request).first else {
                throw CustomError.notFound
            }
            return foundBudget
        } catch {
            throw CustomError.notFound
        }
    }

    func categoryCheck(name: String, emoji: String, income: Bool) -> (error: CategoryError, order: Int64) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" && emoji == "" {
            return (CategoryError.incomplete, 0)
        } else if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            return (CategoryError.missingName, 0)
        } else if emoji == "" {
            return (CategoryError.missingEmoji, 0)
        }

        if income {
            let fetchRequest = fetchRequestForCategories(income: true)
            let incomeCategories = results(for: fetchRequest)

            var emojiArray = [String]()
            var nameArray = [String]()

            incomeCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (incomeCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        } else {
            let fetchRequest = fetchRequestForCategories(income: false)
            let expenseCategories = results(for: fetchRequest)

            var emojiArray = [String]()
            var nameArray = [String]()

            expenseCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (expenseCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        }
    }

    func categoryCheckEdit(name: String, emoji: String, toEdit: Category) -> (error: CategoryError, order: Int64) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" && emoji == "" {
            return (CategoryError.incomplete, 0)
        } else if name.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            return (CategoryError.missingName, 0)
        } else if emoji == "" {
            return (CategoryError.missingEmoji, 0)
        }

        if toEdit.income {
            let fetchRequest = fetchRequestForCategories(income: true)
            var incomeCategories = results(for: fetchRequest)

            if let position = incomeCategories.firstIndex(of: toEdit) {
                incomeCategories.remove(at: position)
            }

            var emojiArray = [String]()
            var nameArray = [String]()

            incomeCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (incomeCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        } else {
            let fetchRequest = fetchRequestForCategories(income: false)
            var expenseCategories = results(for: fetchRequest)

            if let position = expenseCategories.firstIndex(of: toEdit) {
                expenseCategories.remove(at: position)
            }

            var emojiArray = [String]()
            var nameArray = [String]()

            expenseCategories.forEach { category in
                emojiArray.append(category.wrappedEmoji)
                nameArray.append(category.wrappedName)
            }

            if emojiArray.contains(emoji) && nameArray.contains(name) {
                return (CategoryError.duplicate, 0)
            } else if emojiArray.contains(emoji) {
                return (CategoryError.duplicateEmoji, 0)
            } else if nameArray.contains(name) {
                return (CategoryError.duplicateName, 0)
            } else {
                let newItemOrder = (expenseCategories.last?.order ?? 0) + 1
                return (CategoryError.none, newItemOrder)
            }
        }
    }

    func fetchRequestForBudgets() -> NSFetchRequest<Budget> {
        let itemRequest: NSFetchRequest<Budget> = Budget.fetchRequest()

        return itemRequest
    }

    func fetchRequestForMainBudget() -> NSFetchRequest<MainBudget> {
        let itemRequest: NSFetchRequest<MainBudget> = MainBudget.fetchRequest()

        return itemRequest
    }

    func fetchRequestForLogView(
        type: Int,
        optionalIncome: Bool?,
        categoryFilters: [Category] = [],
        now: Date = .now,
        calendar injectedCalendar: Calendar? = nil,
        firstDayOfMonth injectedFirstDayOfMonth: Int? = nil
    ) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = injectedCalendar ?? Calendar(identifier: .gregorian)

        let storedFirstWeekday = UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstWeekday") ?? 0
        if injectedCalendar == nil, storedFirstWeekday > 0 {
            calendar.firstWeekday = storedFirstWeekday
        }
        calendar.minimumDaysInFirstWeek = 4

        let dateCapPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), now as CVarArg)

        // all time
        if type == 5 {
            let andPredicate: NSCompoundPredicate
            let superPredicate: NSCompoundPredicate

            var categoryPredicates = [NSPredicate]()

            for category in categoryFilters {
                categoryPredicates.append(NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category))
            }

            let categoryCompoundPredicate = NSCompoundPredicate(type: .or, subpredicates: categoryPredicates)

            if let income = optionalIncome {
                let incomePredicate = NSPredicate(format: "income = %d", income)

                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [incomePredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            } else {
                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            }

            if categoryFilters.isEmpty {
                itemRequest.predicate = andPredicate
            } else {
                itemRequest.predicate = superPredicate
            }

            return itemRequest
        } else {
            let startPredicate: NSPredicate

            if type == 1 {
                let today = calendar.startOfDay(for: now)
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            } else if type == 2 {
                let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
                let thisWeek = calendar.date(from: dateComponents)!
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            } else if type == 3 {
                let startOfMonth = injectedFirstDayOfMonth
                    ?? UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstDayOfMonth")
                    ?? 1
                let thisMonth = getStartOfMonth(startDay: startOfMonth, now: now, calendar: calendar)
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            } else {
                let dateComponents = calendar.dateComponents([.year], from: now)
                let thisYear = calendar.date(from: dateComponents)!
                startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            }

            let andPredicate: NSCompoundPredicate
            let superPredicate: NSCompoundPredicate

            var categoryPredicates = [NSPredicate]()

            for category in categoryFilters {
                categoryPredicates.append(NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category))
            }

            let categoryCompoundPredicate = NSCompoundPredicate(type: .or, subpredicates: categoryPredicates)

            if let income = optionalIncome {
                let incomePredicate = NSPredicate(format: "income = %d", income)

                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, incomePredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            } else {
                andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, dateCapPredicate])

                superPredicate = NSCompoundPredicate(type: .and, subpredicates: [andPredicate, categoryCompoundPredicate])
            }

            if categoryFilters.isEmpty {
                itemRequest.predicate = andPredicate
            } else {
                itemRequest.predicate = superPredicate
            }

            return itemRequest
        }

    }

    func getShortcutInsights(type: Int, timeframe: Int, optionalIncome: Bool?, categories: [Category]) -> Double {
        let fetchRequest = fetchRequestForLogView(type: timeframe, optionalIncome: optionalIncome, categoryFilters: categories)
        let allTransactions = results(for: fetchRequest)

        if type == 1 {
            var total = 0.0

            allTransactions.forEach { transaction in
                if transaction.income {
                    total += transaction.amount
                } else {
                    total -= transaction.amount
                }
            }

            return total
        } else {
            var total = 0.0

            allTransactions.forEach { transaction in
                total += transaction.amount
            }

            return total
        }
    }

    func getLogViewTotalSpent(type: Int) -> Double {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: false)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            total += transaction.amount
        }

        return total
    }

    func getLogViewTotalIncome(type: Int) -> Double {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: true)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            total += transaction.amount
        }

        return total
    }

    func getLogViewTotalNet(type: Int) -> (value: Double, positive: Bool) {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: nil)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            if transaction.income {
                total += transaction.amount
            } else {
                total -= transaction.amount
            }
        }

        if total >= 0 {
            return (total, true)
        } else {
            return (abs(total), false)
        }
    }

    func getLineGraphDataNet(type: Int) -> [LineGraphDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: nil)
        let transactions = results(for: fetchRequest)

        var holdingDataPoints = [LineGraphDataPoint]()
        var totalForDay = 0.0

        if type < 3 {
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastWeek)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 3 {
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastMonth)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 4 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
            let thisMonth = calendar.date(from: dateComponents)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
            var changingDate = calendar.date(byAdding: .year, value: -1, to: nextMonth)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let newDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                        let anotherNewData = LineGraphDataPoint(date: newDataDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
            let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < nextMonth {
                changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                while changingDate < nextMonth {
                    let anotherDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let anotherNewData = LineGraphDataPoint(date: anotherDataDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        }

        return holdingDataPoints
    }

    func getLineGraphData(income: Bool, type: Int) -> [LineGraphDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: income)
        let transactions = results(for: fetchRequest)

        var holdingDataPoints = [LineGraphDataPoint]()
        var totalForDay = 0.0

        if type < 3 {
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastWeek)!

            for transaction in transactions {
                if transaction.wrappedDate > lastWeek {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)
            totalForDay = 0

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 3 {
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastMonth)!

            for transaction in transactions {
                if transaction.wrappedDate > lastMonth {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: 0)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 4 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
            let thisMonth = calendar.date(from: dateComponents)!
            let thisMonthLastYear = calendar.date(byAdding: .year, value: -1, to: thisMonth)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
            var changingDate = calendar.date(byAdding: .year, value: -1, to: nextMonth)!

            for transaction in transactions {
                if transaction.wrappedDate > thisMonthLastYear {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                        let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let newDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                            let anotherNewData = LineGraphDataPoint(date: newDataDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
            let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < nextMonth {
                changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                while changingDate < nextMonth {
                    let anotherDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let anotherNewData = LineGraphDataPoint(date: anotherDataDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: 0)
                holdingDataPoints.append(finalDate)
            }
        }

        return holdingDataPoints
    }

    func getBudgetLeftover(budget: Budget? = nil, overallBudget: MainBudget? = nil) -> Double {
        let itemRequest: NSFetchRequest<Transaction>
        let budgetAmount: Double

        if let unwrappedOverallBudget = overallBudget {
            itemRequest = fetchRequestForMainBudgetTransactions(budget: unwrappedOverallBudget)
            budgetAmount = unwrappedOverallBudget.amount
        } else if let unwrappedBudget = budget {
            itemRequest = fetchRequestForBudgetTransactions(budget: unwrappedBudget)
            budgetAmount = unwrappedBudget.amount
        } else {
            itemRequest = Transaction.fetchRequest()
            budgetAmount = 0
        }

        let transactions = results(for: itemRequest)

        var totalSpent = 0.0

        transactions.forEach { transaction in
            totalSpent += transaction.wrappedAmount
        }

        return budgetAmount - totalSpent
    }

    func fetchRequestForMainBudgetTransactions(budget: MainBudget) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        guard let startDate = budget.startDate else {
            itemRequest.predicate = NSPredicate(value: false)
            return itemRequest
        }

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        let endPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)
        let incomePredicate = NSPredicate(format: "income = %d", false)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, incomePredicate])

        itemRequest.predicate = andPredicate

        return itemRequest
    }

    func fetchRequestForBudgetTransactions(budget: Budget) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        guard let startDate = budget.startDate, let category = budget.category else {
            itemRequest.predicate = NSPredicate(value: false)
            return itemRequest
        }

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        let endPredicate = NSPredicate(format: "%K <= %@", #keyPath(Transaction.date), Date.now as CVarArg)
        let categoryPredicate = NSPredicate(format: "%K == %@", #keyPath(Transaction.category), category)
        let incomePredicate = NSPredicate(format: "income = %d", false)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, categoryPredicate, incomePredicate])

        itemRequest.predicate = andPredicate

        return itemRequest
    }

    func fetchRequestForLineGraph(optionalIncome: Bool?) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)]

        if let income = optionalIncome {
            itemRequest.predicate = NSPredicate(format: "income = %d", income)
            return itemRequest
        } else {
            return itemRequest
        }
    }

    func fetchRequestForLogViewCategoryFilter(income: Bool) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "income = %d", income)
        return itemRequest
    }

    func getInsights(type: Int, date: Date, income: Bool) -> (amount: Double, maximum: Double, average: Double, numberOfDays: Int, dates: [Date], dateDictionary: [Date: Double]) {
        let currentItemRequest: NSFetchRequest<Transaction> = fetchRequestForInsights(type: type, date: date, income: income)
        let currentTransactions = results(for: currentItemRequest)

        var iterativeDate = date

        if type == 1 {
            // tracking dates
            var dates = [Date]()
            var nextDate = date

            // calendar initialization
            var calendar = Calendar(identifier: .gregorian)

            calendar.firstWeekday = UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstWeekday") ?? 1
            calendar.minimumDaysInFirstWeek = 4

            var dictionary = [Date: Double]()
            var totalForWeek = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var weekAverage = 0.0

            for _ in 1 ... 7 {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForWeek += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let currentWeek = calendar.date(from: dateComponents)!

            if currentWeek == date {
//                let fromDate = Calendar.current.startOfDay(for: currentWeek)
//                let toDate = Calendar.current.startOfDay(for: Date.now)
                let numberOfDays = Calendar.current.dateComponents([.day], from: currentWeek, to: Date.now)

                weekAverage = totalForWeek / Double((numberOfDays.day! + 1))
            } else {
                weekAverage = totalForWeek / 7
            }

            return (totalForWeek, maximum, weekAverage, numberOfDays, dates, dictionary)
        } else if type == 2 {
            // tracking dates
            var dates = [Date]()
            var nextDate = date

            let calendar = Calendar(identifier: .gregorian)
            let range = calendar.range(of: .day, in: .month, for: iterativeDate)!

            var dictionary = [Date: Double]()
            var totalForMonth = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var monthAverage = 0.0

            for _ in 1 ... range.count {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForMonth += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                monthAverage = totalForMonth / Double((numDays.day! + 1))
            } else {
                monthAverage = totalForMonth / Double(range.count)
            }

            return (totalForMonth, maximum, monthAverage, numberOfDays, dates, dictionary)
        } else if type == 3 {
            // trackin dates
            var dates = [Date]()
            var nextDate = date

            let calendar = Calendar(identifier: .gregorian)

            var dictionary = [Date: Double]()
            var totalForYear = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var monthAverage = 0.0

            for _ in 1 ... 12 {
                nextDate = calendar.date(byAdding: .month, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForYear += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let currentYear = calendar.date(from: dateComponents)!

            if currentYear == date {
                let fromDate = Calendar.current.startOfDay(for: currentYear)
                let toDate = Calendar.current.startOfDay(for: Date.now)
                let numDays = Calendar.current.dateComponents([.month], from: fromDate, to: toDate)

                monthAverage = totalForYear / Double((numDays.month! + 1))
            } else {
                monthAverage = totalForYear / 12
            }

            return (totalForYear, maximum, monthAverage, numberOfDays, dates, dictionary)
        } else {
            return (0, 0, 0, 0, [Date](), [Date: Double]())
        }
    }

    func fetchRequestForInsights(type: Int, date: Date, income: Bool? = nil) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstWeekday") ?? 1
        calendar.minimumDaysInFirstWeek = 4

        let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), date as CVarArg)

        let endPredicate: NSPredicate

        if type == 1 {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .day, value: 7, to: date) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        } else if type == 2 {
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

//            let endOfPeriod = calendar.date(byAdding: .day, value: -1, to: next) ?? Date.now
//
            if next > Date.now {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
//
//            if calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
//                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
//            } else {
//
//                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
//            }
        } else {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
            } else {
                let next = calendar.date(byAdding: .year, value: 1, to: date) ?? Date.now
                endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), next as CVarArg)
            }
        }

        let andPredicate: NSCompoundPredicate

        if let unwrappedIncome = income {
            let incomePredicate = NSPredicate(format: "income = %d", unwrappedIncome)

            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, incomePredicate, endPredicate])
        } else {
            andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])
        }

        itemRequest.predicate = andPredicate

        return itemRequest
    }

    func getInsightsSummary(type: Int, date: Date) -> (spent: Double, income: Double, net: Double, positive: Bool, average: Double) {
        let itemRequest: NSFetchRequest<Transaction> = fetchRequestForInsights(type: type, date: date)
        let currentTransactions = results(for: itemRequest)

        var holdingSpent = 0.0
        var holdingIncome = 0.0

        currentTransactions.forEach { transaction in
            if transaction.income {
                holdingIncome += transaction.amount
            } else {
                holdingSpent += transaction.amount
            }
        }

        let net = holdingIncome - holdingSpent
        let absoluteNet: Double
        let positive: Bool

        if net < 0 {
            absoluteNet = abs(net)
            positive = false
        } else {
            absoluteNet = net
            positive = true
        }

        let calendar = Calendar.current

        if type == 1 {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                let numberOfDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numberOfDays.day! + 1))
            } else {
                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / 7)
            }
        } else if type == 2 {
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
            } else {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: next)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
            }
//            if calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
//                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)
//
//                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
//            } else {
//
//                let range = calendar.range(of: .day, in: .month, for: date)!
//                let numDays = range.count
//
//                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays))
//            }
        } else {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                let numDays = Calendar.current.dateComponents([.month], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.month! + 1))
            } else {
                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / 12)
            }
        }
    }

    func fetchRequestForWidgetInsights(type: InsightsTimePeriod, income: Bool) -> (fetchRequest: NSFetchRequest<Transaction>, date: Date) {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstWeekday") ?? 1
        calendar.minimumDaysInFirstWeek = 4

        let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

        let incomePredicate = NSPredicate(format: "income = %d", income)

        let startDate: Date
        let startPredicate: NSPredicate

        switch type {
        case .unknown:
            startDate = Date.now
            startPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            startDate = calendar.date(from: dateComponents)!

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        case .month:
            let startOfMonth = UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstDayOfMonth") ?? 1

            startDate = getStartOfMonth(startDay: startOfMonth)

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            startDate = calendar.date(from: dateComponents)!

            startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), startDate as CVarArg)
        }

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate, incomePredicate])

        itemRequest.predicate = andPredicate
        itemRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
        ]

        return (itemRequest, startDate)
    }

    func fetchRequestForRecentTransactionsWithCount(type: TimePeriod, count: Int) -> NSFetchRequest<Transaction> {
        let itemRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()

        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstWeekday") ?? 1
        calendar.minimumDaysInFirstWeek = 4

        switch type {
        case .unknown:
            return itemRequest
        case .day:
            let today = calendar.startOfDay(for: Date.now)

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), today as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .week:
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let thisWeek = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisWeek as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .month:
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)

            let thisMonth = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisMonth as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        case .year:
            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let thisYear = calendar.date(from: dateComponents)!

            let startPredicate = NSPredicate(format: "%K >= %@", #keyPath(Transaction.date), thisYear as CVarArg)
            let endPredicate = NSPredicate(format: "%K < %@", #keyPath(Transaction.date), Date.now as CVarArg)

            let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [startPredicate, endPredicate])

            itemRequest.predicate = andPredicate
            itemRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Transaction.date, ascending: false)
            ]
            itemRequest.fetchLimit = count

            return itemRequest
        }
    }

    func fetchRequestForMainBudgetWidget() -> (found: Bool, totalSpent: Double, budgetAmount: Double, percentage: Double, type: Int, startDate: Date) {
        do {
            return try performViewContextRead { context in
                guard let budget = try context.fetch(fetchRequestForMainBudget()).first,
                      let startDate = budget.startDate else {
                    return (false, 0, 0, 0, 0, Date.now)
                }
                let transactions = try context.fetch(fetchRequestForMainBudgetTransactions(budget: budget))
                let total = transactions.reduce(0) { $0 + $1.wrappedAmount }
                guard total.isFinite, budget.amount.isFinite else {
                    return (false, 0, 0, 0, 0, Date.now)
                }
                let percentage = BudgetWindow.progress(
                    startDate: startDate,
                    endDate: budget.endDate,
                    now: .now,
                    calendar: .current
                )
                return (true, total, budget.amount, percentage, Int(budget.type), startDate)
            }
        } catch {
            return (false, 0, 0, 0, 0, Date.now)
        }
    }

    func performViewContextRead<T>(_ body: (NSManagedObjectContext) throws -> T) throws -> T {
        try container.viewContext.performAndWait {
            switch persistentStoreState {
            case .loading:
                throw PersistentStoreAccessError.loading
            case let .failed(message):
                throw PersistentStoreAccessError.failed(message)
            case .loaded:
                return try body(container.viewContext)
            }
        }
    }

    func results<T: NSManagedObject>(for fetchRequest: NSFetchRequest<T>) -> [T] {
        (try? performViewContextRead { try $0.fetch(fetchRequest) }) ?? []
    }
}

extension ProcessInfo {
    var isRunningUnitTests: Bool {
        environment.keys.contains { $0.hasPrefix("XCTest") }
    }
}

enum TransactionSummary {
    static func net<S: Sequence>(_ transactions: S) -> Double where S.Element == Transaction {
        transactions.reduce(into: 0) { result, transaction in
            result += transaction.income ? transaction.amount : -transaction.amount
        }
    }
}

enum BudgetWindow {
    static func progress(
        startDate: Date,
        endDate: Date,
        now: Date,
        calendar: Calendar
    ) -> Double {
        let duration = calendar.dateComponents([.second], from: startDate, to: endDate).second ?? 0
        let elapsed = calendar.dateComponents([.second], from: startDate, to: now).second ?? 0
        guard duration > 0 else { return 0 }
        return Double(elapsed) / Double(duration)
    }
}

enum NumericSafety {
    static func finiteOrZero(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    static func safeRatio(_ numerator: Double, _ denominator: Double) -> Double {
        guard numerator.isFinite, denominator.isFinite, denominator != 0 else { return 0 }
        return finiteOrZero(numerator / denominator)
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(finiteOrZero(value), range.lowerBound), range.upperBound)
    }

    static func roundedInt(_ value: Double, fallback: Int = 0) -> Int {
        guard value.isFinite else { return fallback }
        return Int(exactly: value.rounded()) ?? fallback
    }

    static func finiteSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
        finiteOrZero(values.reduce(0, +))
    }
}

enum WidgetInsightMath {
    static func total<S: Sequence>(_ amounts: S) -> Double where S.Element == Double {
        NumericSafety.finiteSum(amounts)
    }

    static func average(total: Double, periodCount: Int) -> Double {
        NumericSafety.safeRatio(total, Double(periodCount))
    }

    static func categoryShare(amount: Double, total: Double) -> Double {
        NumericSafety.clamped(NumericSafety.safeRatio(amount, total), to: 0 ... 1)
    }
}

enum BudgetValidation {
    static func isUsable(startDate: Date?, hasCategory: Bool) -> Bool {
        startDate != nil && hasCategory
    }
}

enum BudgetMath {
    static func spendingRatio(spent: Double, budgetAmount: Double) -> Double {
        guard spent.isFinite, budgetAmount.isFinite, budgetAmount > 0 else { return 0 }
        return NumericSafety.safeRatio(spent, budgetAmount)
    }

    static func gaugeRatio(spent: Double, budgetAmount: Double) -> Double {
        NumericSafety.clamped(spendingRatio(spent: spent, budgetAmount: budgetAmount), to: 0 ... 1)
    }

    static func roundedPercentage(spent: Double, budgetAmount: Double) -> Int {
        let percentage = spendingRatio(spent: spent, budgetAmount: budgetAmount) * 100
        return NumericSafety.roundedInt(percentage)
    }

    static func roundedAmount(_ amount: Double) -> Int {
        NumericSafety.roundedInt(amount)
    }
}

public extension NSManagedObjectContext {
    func executeAndMergeChanges(using batchDeleteRequest: NSBatchDeleteRequest) throws {
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        let result = try execute(batchDeleteRequest) as? NSBatchDeleteResult
        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
    }
}

struct LineGraphDataPoint: Equatable {
    let date: Date
    let amount: Double

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")

        return dateFormatter.string(from: date)
    }

    var monthString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("MMMyy")

        return dateFormatter.string(from: date)
    }

    var amountString: String {
        if abs(amount) < 1000 {
            return String(format: "%.2f", amount)
        } else {
            return String(format: "%.0f", amount)
        }
    }
}

func getStartOfMonth(
    startDay: Int,
    now: Date = .now,
    calendar: Calendar = .current
) -> Date {

    guard startDay > 0 && startDay <= calendar.maximumRange(of: .day)!.upperBound else {
        let dateComponents = calendar.dateComponents([.month, .year], from: now)
        return calendar.date(from: dateComponents) ?? now
    }

    let today = calendar.startOfDay(for: now)
    let currentDay = calendar.component(.day, from: today)

    var startComponents = DateComponents()
    startComponents.month = currentDay >= startDay ? 0 : -1

    startComponents.day = startDay - currentDay

    return calendar.date(byAdding: startComponents, to: today) ?? now
}

func calculateStartOfMonthPeriod(earliestDate: Date, startOfMonthDay: Int) -> Date {
    var components = Calendar.current.dateComponents([.year, .month, .day], from: earliestDate)
    components.day = startOfMonthDay

    let startOfMonth = Calendar.current.date(from: components) ?? Date.now
    return (earliestDate < startOfMonth) ? (Calendar.current.date(byAdding: .month, value: -1, to: startOfMonth) ?? Date.now) : startOfMonth
}
