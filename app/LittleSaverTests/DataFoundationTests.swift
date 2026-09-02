import LittleSaverCore
import CoreData
import XCTest
@testable import LittleSaver

final class DataFoundationTests: XCTestCase {
    func testPlatformAdapterInstallsWidgetCallbackOnlyOnce() {
        let shared = DataController.platformShared
        let original = shared.reloadWidgets
        defer { shared.reloadWidgets = original }
        var reloadCount = 0
        shared.reloadWidgets = { reloadCount += 1 }
        XCTAssertTrue(DataController.platformShared === shared)
        DataController.platformShared.reloadWidgets()
        XCTAssertEqual(reloadCount, 1)
    }

    func testPersistenceModelHasOneFrameworkOwnerAndEquivalentBaselineVersions() throws {
        let bundle = Bundle(for: DataController.self)
        XCTAssertEqual(bundle.bundleIdentifier, "io.damao.littlesaver.core")
        let modelURL = try XCTUnwrap(bundle.url(forResource: AppIdentifiers.persistentModel, withExtension: "momd"))
        let legacy = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("LittleSaverDevelopmentV0.mom")))
        let current = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("LittleSaverV1.mom")))
        XCTAssertEqual(legacy.entityVersionHashesByName, current.entityVersionHashesByName)
        XCTAssertEqual(current.entityVersionHashesByName, controller.container.managedObjectModel.entityVersionHashesByName)
    }

    func testLegacyDiskStoreReopensWithFrameworkModelAndPreservesRelationships() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("ledger.sqlite")
        let modelURL = try XCTUnwrap(Bundle(for: DataController.self).url(forResource: AppIdentifiers.persistentModel, withExtension: "momd"))
        let categoryID = UUID()
        let transactionID = UUID()

        // Write the exact development model, then close its coordinator before opening V1.
        do {
            let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("LittleSaverDevelopmentV0.mom")))
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(type: .sqlite, at: storeURL)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
            category.setValue(categoryID, forKey: "id")
            category.setValue("Legacy food", forKey: "name")
            let transaction = NSEntityDescription.insertNewObject(forEntityName: "Transaction", into: context)
            transaction.setValue(transactionID, forKey: "id")
            transaction.setValue("Preserve me", forKey: "note")
            transaction.setValue(12.5, forKey: "amount")
            transaction.setValue(category, forKey: "category")
            let budget = NSEntityDescription.insertNewObject(forEntityName: "Budget", into: context)
            budget.setValue(category, forKey: "category")
            budget.setValue(100, forKey: "amount")
            let template = NSEntityDescription.insertNewObject(forEntityName: "TemplateTransaction", into: context)
            template.setValue(category, forKey: "category")
            template.setValue(7.5, forKey: "amount")
            let mainBudget = NSEntityDescription.insertNewObject(forEntityName: "MainBudget", into: context)
            mainBudget.setValue(500, forKey: "amount")
            try context.save()
            context.reset()
            try coordinator.remove(store)
        }

        let diskController = try DataController(configuration: .init(
            mode: .sharedLocal,
            modelName: AppIdentifiers.persistentModel,
            storeURL: storeURL,
            reloadWidgetsAfterSave: false
        ))
        XCTAssertEqual(diskController.persistentStoreState, .loaded)
        let transaction = try XCTUnwrap(diskController.results(for: Transaction.fetchRequest()).first)
        XCTAssertEqual(transaction.id, transactionID)
        XCTAssertEqual(transaction.note, "Preserve me")
        XCTAssertEqual(transaction.amount, 12.5)
        XCTAssertEqual(transaction.category?.id, categoryID)
        XCTAssertEqual(transaction.category?.name, "Legacy food")
        XCTAssertEqual(transaction.category?.budget?.amount, 100)
        XCTAssertEqual(transaction.category?.templates?.count, 1)
        XCTAssertEqual(diskController.results(for: TemplateTransaction.fetchRequest()).first?.amount, 7.5)
        XCTAssertEqual(diskController.results(for: MainBudget.fetchRequest()).first?.amount, 500)
        let coordinator = diskController.container.persistentStoreCoordinator
        diskController.container.viewContext.reset()
        for store in coordinator.persistentStores { try coordinator.remove(store) }
    }

    private var controller: DataController!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        controller = try DataController(configuration: .inMemory)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(controller.persistentStoreState, .loaded)
    }

    override func tearDown() {
        controller = nil
        calendar = nil
    }

    func testBundledThirdPartyLicensesAreReadableAndComplete() throws {
        XCTAssertEqual(BundledThirdPartyLicense.all.count, 4)

        for license in BundledThirdPartyLicense.all {
            let text = try license.text(in: .main)
            XCTAssertTrue(text.contains(license.attribution))
            XCTAssertTrue(text.contains("Permission is hereby granted"))
            XCTAssertTrue(text.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
        }
    }

    func testRuntimeRolesMapOnlyKnownBundleIdentifiers() throws {
        XCTAssertEqual(try AppRuntimeRole(bundleIdentifier: AppIdentifiers.appBundle), .mainApplication)
        XCTAssertEqual(try AppRuntimeRole(bundleIdentifier: AppIdentifiers.widgetBundle), .widget)
        XCTAssertEqual(try AppRuntimeRole(bundleIdentifier: AppIdentifiers.intentBundle), .intentService)
        XCTAssertEqual(try AppRuntimeRole(bundleIdentifier: AppIdentifiers.intentUIBundle), .intentUI)
        XCTAssertThrowsError(try AppRuntimeRole(bundleIdentifier: "example.invalid"))
        XCTAssertEqual(AppRuntimeRole.mainApplication.persistentStoreMode, .cloudSync)
        XCTAssertEqual(AppRuntimeRole.widget.persistentStoreMode, .sharedLocal)
        XCTAssertEqual(AppRuntimeRole.intentService.persistentStoreMode, .sharedLocal)
        XCTAssertNil(AppRuntimeRole.intentUI.persistentStoreMode)
    }

    func testInMemoryCRUDAndCascadeRelationship() throws {
        let category = makeCategory(name: "Food")
        let transaction = controller.newTransaction(
            note: "Lunch",
            category: category,
            income: false,
            amount: 12.5,
            date: date(2026, 1, 15),
            repeatType: 0,
            repeatCoefficient: 1,
            delay: false
        )

        XCTAssertEqual(category.transactionCount, 1)
        XCTAssertEqual(transaction.category, category)
        XCTAssertEqual(controller.results(for: Transaction.fetchRequest()).count, 1)

        controller.container.viewContext.delete(category)
        controller.save()
        XCTAssertTrue(controller.results(for: Transaction.fetchRequest()).isEmpty)
    }

    func testBudgetCRUDRelationshipAndTransactionWindow() throws {
        let category = makeCategory(name: "Food")
        let budget = Budget(context: controller.container.viewContext)
        budget.id = UUID()
        budget.amount = 200
        budget.dateCreated = date(2026, 1, 1)
        budget.startDate = date(2026, 1, 10)
        budget.type = 2
        budget.category = category
        controller.save()

        XCTAssertEqual(category.budget, budget)
        XCTAssertEqual(controller.results(for: Budget.fetchRequest()).count, 1)

        budget.amount = 250
        controller.save()
        XCTAssertEqual(controller.results(for: Budget.fetchRequest()).first?.amount, 250)

        _ = controller.newTransaction(note: "Before", category: category, income: false, amount: 10, date: date(2026, 1, 9), repeatType: 0, repeatCoefficient: 1, delay: false)
        _ = controller.newTransaction(note: "Inside", category: category, income: false, amount: 25, date: date(2026, 1, 12), repeatType: 0, repeatCoefficient: 1, delay: false)
        _ = controller.newTransaction(note: "Income", category: category, income: true, amount: 100, date: date(2026, 1, 12), repeatType: 0, repeatCoefficient: 1, delay: false)

        let windowTransactions = controller.results(for: controller.fetchRequestForBudgetTransactions(budget: budget))
        XCTAssertEqual(windowTransactions.map(\.wrappedNote), ["Inside"])
        XCTAssertEqual(
            BudgetWindow.progress(
                startDate: date(2026, 1, 10),
                endDate: date(2026, 1, 17),
                now: date(2026, 1, 13, 12),
                calendar: calendar
            ),
            0.5,
            accuracy: 0.000_001
        )

        controller.container.viewContext.delete(budget)
        controller.save()
        XCTAssertTrue(controller.results(for: Budget.fetchRequest()).isEmpty)
        XCTAssertNil(category.budget)
    }

    func testBudgetWithoutStartDateProducesEmptyWindow() {
        let budget = Budget(context: controller.container.viewContext)
        budget.category = makeCategory(name: "Food")
        budget.startDate = nil
        controller.save()

        XCTAssertTrue(controller.results(for: controller.fetchRequestForBudgetTransactions(budget: budget)).isEmpty)
        XCTAssertFalse(BudgetValidation.isUsable(startDate: nil, hasCategory: true))
        XCTAssertFalse(BudgetValidation.isUsable(startDate: date(2026, 1, 1), hasCategory: false))
        XCTAssertTrue(BudgetValidation.isUsable(startDate: date(2026, 1, 1), hasCategory: true))
    }

    func testBackgroundReadMapsManagedObjectsToValuesOnContextQueue() {
        let category = makeCategory(name: "Food")
        _ = controller.newTransaction(note: "Lunch", category: category, income: false, amount: 12, date: date(2026, 1, 12), repeatType: 0, repeatCoefficient: 1, delay: false)
        let expectation = expectation(description: "background read")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let notes = try self.controller.performViewContextRead { context in
                    try context.fetch(Transaction.fetchRequest()).map(\.wrappedNote)
                }
                XCTAssertEqual(notes, ["Lunch"])
            } catch {
                XCTFail("Unexpected read failure: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    func testBudgetMathRejectsZeroAndNonFiniteAmounts() {
        XCTAssertEqual(BudgetMath.spendingRatio(spent: 50, budgetAmount: 100), 0.5)
        XCTAssertEqual(BudgetMath.roundedPercentage(spent: 50, budgetAmount: 100), 50)
        XCTAssertEqual(BudgetMath.gaugeRatio(spent: 150, budgetAmount: 100), 1)
        XCTAssertEqual(BudgetMath.gaugeRatio(spent: -10, budgetAmount: 100), 0)

        XCTAssertEqual(BudgetMath.spendingRatio(spent: 10, budgetAmount: 0), 0)
        XCTAssertEqual(BudgetMath.roundedPercentage(spent: 10, budgetAmount: 0), 0)
        XCTAssertEqual(BudgetMath.spendingRatio(spent: .infinity, budgetAmount: 100), 0)
        XCTAssertEqual(BudgetMath.spendingRatio(spent: 10, budgetAmount: .infinity), 0)
        XCTAssertEqual(BudgetMath.spendingRatio(spent: .nan, budgetAmount: 100), 0)
        XCTAssertEqual(BudgetMath.roundedPercentage(spent: .greatestFiniteMagnitude, budgetAmount: .leastNonzeroMagnitude), 0)
        XCTAssertEqual(BudgetMath.roundedAmount(.infinity), 0)
        XCTAssertEqual(BudgetMath.roundedAmount(.nan), 0)
        XCTAssertEqual(NumericSafety.roundedInt(Double(Int.max)), 0)
        XCTAssertEqual(NumericSafety.roundedInt(Double(Int.min)), Int.min)
        XCTAssertEqual(BudgetMath.roundedPercentage(spent: Double(Int.max) / 100, budgetAmount: 1), 0)
        XCTAssertEqual(NumericSafety.finiteSum([Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]), 0)
        XCTAssertEqual(NumericSafety.safeRatio(10, 0), 0)
        XCTAssertEqual(NumericSafety.safeRatio(.infinity, 10), 0)
        XCTAssertEqual(NumericSafety.clamped(.nan, to: 0 ... 1), 0)
        XCTAssertEqual(WidgetInsightMath.total([Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]), 0)
        XCTAssertEqual(WidgetInsightMath.average(total: 100, periodCount: 0), 0)
        XCTAssertEqual(WidgetInsightMath.categoryShare(amount: 10, total: 0), 0)
        XCTAssertEqual(WidgetInsightMath.categoryShare(amount: .infinity, total: 10), 0)
    }

    func testRecurringDailyWeeklyMonthlyAndInvalidValues() throws {
        let start = date(2026, 1, 28)
        XCTAssertEqual(
            try RecurringSchedule.nextDate(after: start, type: 1, coefficient: 2, calendar: calendar),
            date(2026, 1, 30)
        )
        XCTAssertEqual(
            try RecurringSchedule.nextDate(after: start, type: 2, coefficient: 2, calendar: calendar),
            date(2026, 2, 11)
        )
        XCTAssertEqual(
            try RecurringSchedule.nextDate(after: start, type: 3, coefficient: 1, calendar: calendar),
            date(2026, 2, 28)
        )
        XCTAssertEqual(
            try RecurringSchedule.nextDate(after: date(2026, 1, 31), type: 3, coefficient: 1, calendar: calendar),
            date(2026, 2, 28)
        )
        XCTAssertThrowsError(
            try RecurringSchedule.nextDate(after: start, type: 0, coefficient: 1, calendar: calendar)
        )
        XCTAssertThrowsError(
            try RecurringSchedule.nextDate(after: start, type: 1, coefficient: 0, calendar: calendar)
        )
    }

    func testFixedClockDayFilterAndNetSummary() {
        let expense = makeCategory(name: "Food", income: false)
        let income = makeCategory(name: "Salary", income: true)
        _ = controller.newTransaction(note: "Yesterday", category: expense, income: false, amount: 100, date: date(2026, 3, 9, 23), repeatType: 0, repeatCoefficient: 1, delay: false)
        _ = controller.newTransaction(note: "Lunch", category: expense, income: false, amount: 30, date: date(2026, 3, 10, 10), repeatType: 0, repeatCoefficient: 1, delay: false)
        _ = controller.newTransaction(note: "Pay", category: income, income: true, amount: 80, date: date(2026, 3, 10, 11), repeatType: 0, repeatCoefficient: 1, delay: false)
        _ = controller.newTransaction(note: "Future", category: income, income: true, amount: 999, date: date(2026, 3, 10, 13), repeatType: 0, repeatCoefficient: 1, delay: false)

        let request = controller.fetchRequestForLogView(
            type: 1,
            optionalIncome: nil,
            now: date(2026, 3, 10, 12),
            calendar: calendar
        )
        let transactions = controller.results(for: request)
        XCTAssertEqual(Set(transactions.map(\.wrappedNote)), Set(["Lunch", "Pay"]))
        XCTAssertEqual(TransactionSummary.net(transactions), 50)
    }

    func testCSVParserSupportsQuotedCommasEscapedQuotesAndCRLF() throws {
        let rows = try CSVDocumentParser.parse("Food,\"Lunch, cafe\",2026-01-02,12.50\r\nFood,\"Say \"\"hi\"\"\",2026-01-03,3")
        XCTAssertEqual(rows.count, 2)
        guard rows.count == 2 else { return }
        XCTAssertEqual(rows[0][1], "Lunch, cafe")
        XCTAssertEqual(rows[1][1], "Say \"hi\"")
        XCTAssertThrowsError(try CSVDocumentParser.parse("Food,\"unfinished"))
        XCTAssertThrowsError(try CSVDocumentParser.parse("Food,\"closed\"suffix,1"))
    }

    func testCSVImportIsAllOrNothing() throws {
        let category = makeCategory(name: "Food")
        let rows = [
            ["Food", "Lunch", "2026-01-02", "12.50"],
            ["Food", "Broken", "not-a-date", "7"]
        ]
        XCTAssertThrowsError(try CSVTransactionImporter.importRows(
            rows,
            mapping: CSVImportMapping(categoryColumn: 0, noteColumn: 1, dateColumn: 2, amountColumn: 3),
            dateFormat: "yyyy-MM-dd",
            categoriesByName: ["Food": category],
            into: controller,
            timeZone: calendar.timeZone
        ))
        XCTAssertTrue(controller.results(for: Transaction.fetchRequest()).isEmpty)
    }

    func testCSVImportCommitsValidatedRows() throws {
        let category = makeCategory(name: "Food")
        let count = try CSVTransactionImporter.importRows(
            [["Food", "Lunch, cafe", "2026-01-02", "12.50"]],
            mapping: CSVImportMapping(categoryColumn: 0, noteColumn: 1, dateColumn: 2, amountColumn: 3),
            dateFormat: "yyyy-MM-dd",
            categoriesByName: ["Food": category],
            into: controller,
            timeZone: calendar.timeZone
        )
        XCTAssertEqual(count, 1)
        XCTAssertEqual(controller.results(for: Transaction.fetchRequest()).first?.wrappedNote, "Lunch, cafe")
    }

    func testDeepLinksEncodeAndRejectMalformedRoutes() {
        let link = DeepLink.budget(name: "Food & Drinks")
        XCTAssertEqual(DeepLink(url: link.url), link)
        XCTAssertEqual(DeepLink(url: DeepLink.search.url), .search)
        XCTAssertNil(DeepLink(url: URL(string: "https://search")!))
        XCTAssertNil(DeepLink(url: URL(string: "\(AppIdentifiers.urlScheme)://unknown")!))
        XCTAssertNil(DeepLink(url: URL(string: "\(AppIdentifiers.urlScheme)://budget?other=value")!))
        XCTAssertNil(DeepLink(url: URL(string: "\(AppIdentifiers.urlScheme)://budget?budget=")!))
    }

    func testDeepLinkRouterDefersWhileLockedAndRoutesAfterUnlock() {
        var router = DeepLinkRouter()

        XCTAssertNil(router.receive(.budget(name: "Food & Drinks"), isLocked: true))
        XCTAssertEqual(router.pendingLink, .budget(name: "Food & Drinks"))
        XCTAssertEqual(router.unlock(), .budget(name: "Food & Drinks"))
        XCTAssertNil(router.pendingLink)

        XCTAssertEqual(router.receive(.newExpense, isLocked: false), .newExpense)
        XCTAssertNil(router.pendingLink)

        XCTAssertNil(router.receive(.search, isLocked: true))
        XCTAssertEqual(router.receive(.insights, isLocked: false), .insights)
        XCTAssertNil(router.unlock())
    }

    func testCloudKitSchemaInitializationRequiresDebugCloudModeAndExplicitArgument() {
        let argument = ["LittleSaver", "--initialize-cloudkit-schema"]
        let policy = DataController.CloudKitSchemaInitializationPolicy.self

        XCTAssertTrue(policy.shouldInitialize(mode: .cloudSync, arguments: argument, isDebugBuild: true))
        XCTAssertFalse(policy.shouldInitialize(mode: .sharedLocal, arguments: argument, isDebugBuild: true))
        XCTAssertFalse(policy.shouldInitialize(mode: .inMemory, arguments: argument, isDebugBuild: true))
        XCTAssertFalse(policy.shouldInitialize(mode: .cloudSync, arguments: ["LittleSaver"], isDebugBuild: true))
        XCTAssertFalse(policy.shouldInitialize(mode: .cloudSync, arguments: argument, isDebugBuild: false))
    }

    func testUnknownProcessConfigurationFailsExplicitly() {
        XCTAssertThrowsError(try DataController.Configuration.currentProcess(bundleIdentifier: "example.invalid"))
    }

    func testInMemoryStoreDoesNotConfigureCloudKitOrDisk() throws {
        let description = try XCTUnwrap(controller.container.persistentStoreDescriptions.first)
        XCTAssertEqual(description.type, NSInMemoryStoreType)
        XCTAssertNil(controller.configuration?.storeURL)
        XCTAssertEqual(description.url?.path, "/dev/null")
        XCTAssertNil(description.cloudKitContainerOptions)
        XCTAssertEqual(
            (description.options[NSPersistentHistoryTrackingKey] as? NSNumber)?.boolValue,
            true
        )
        XCTAssertEqual(
            (description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber)?.boolValue,
            true
        )
    }

    private func makeCategory(name: String, income: Bool = false) -> LittleSaverCore.Category {
        let category = LittleSaverCore.Category(context: controller.container.viewContext)
        category.id = UUID()
        category.name = name
        category.emoji = "🍽"
        category.colour = "#FFFFFF"
        category.income = income
        category.dateCreated = date(2026, 1, 1)
        controller.save()
        return category
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
