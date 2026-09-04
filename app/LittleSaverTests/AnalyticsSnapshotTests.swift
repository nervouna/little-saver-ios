import CoreData
import LittleSaverCore
import XCTest

final class AnalyticsSnapshotTests: XCTestCase {
    @MainActor
    func testInMemoryLogAggregateMatchesBoundedAndAllTimeTotals() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let now = date(2026, 3, 10, 12)
        for (timestamp, amount, income) in [(date(2025, 1, 1), 100.0, true), (now, 7.0, false)] {
            let row = Transaction(context: context); row.id = UUID(); row.date = timestamp; row.income = income; row.amount = amount
        }
        try context.save()
        let environment = AnalyticsEnvironment(stamp: AnalyticsStamp(now: now), calendar: utc)
        let bounded = try await controller.logSnapshot(LogRequest(timeframe: 1, environment: environment))
        let all = try await controller.logSnapshot(LogRequest(timeframe: 5, environment: environment))
        XCTAssertEqual(bounded.totals.spent, 7)
        XCTAssertEqual(bounded.netPoints.last?.amount, 93)
        XCTAssertEqual(all.totals.net, 93)
    }

    @MainActor
    func testRefreshRetainsMountedContentButDoesNotExposeOldValueAsNewKey() async {
        let model = SnapshotModel<Int, Int>()
        await model.load(key: 1) { _ in 11 }
        var pending: CheckedContinuation<Int, Never>?
        let refresh = Task { await model.load(key: 2) { _ in await withCheckedContinuation { pending = $0 } } }
        while pending == nil { await Task.yield() }
        XCTAssertEqual(model.value, 11, "Mounted search/period containers retain identity while refreshing")
        XCTAssertNil(model.value(for: 2), "Old amounts must remain hidden for the new request")
        pending?.resume(returning: 22)
        await refresh.value
        XCTAssertEqual(model.value(for: 2), 22)
        XCTAssertTrue(Thread.isMainThread)
    }

    @MainActor
    func testOnlyCommittedChangesInvalidateAnalytics() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let initial = controller.analyticsStamp.revision
        _ = try await controller.saveCategory(CategoryInput(name: "Income", emoji: "💰", colour: "#000000", income: true))
        XCTAssertEqual(controller.analyticsStamp.revision, initial + 1)
        let committed = controller.analyticsStamp
        controller.commandSave = { _ in throw CocoaError(.fileWriteUnknown) }
        do {
            _ = try await controller.saveCategory(CategoryInput(name: "Failure", emoji: "❌", colour: "#000000", income: false))
            XCTFail("Expected injected commit failure")
        } catch {}
        XCTAssertEqual(controller.analyticsStamp, committed)
        try await controller.refreshPersistentHistory()
        XCTAssertEqual(controller.analyticsStamp, committed)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @MainActor
    private func diskController(author: String = "analytics-reader") async throws -> DataController {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep SQLite files until process teardown; asynchronous callbacks retain coordinators.
        let controller = try DataController(configuration: .init(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: directory.appendingPathComponent("fixture.sqlite"), reloadWidgetsAfterSave: false, transactionAuthor: author))
        try await controller.waitUntilReady()
        return controller
    }

    @MainActor
    func testMergedHistoryInvalidatesEvenWhenTokenPersistenceFails() async throws {
        let controller = try await diskController(author: "token-failure")
        let store = try XCTUnwrap(controller.container.persistentStoreCoordinator.persistentStores.first?.url)
        let tokenURL = store.appendingPathExtension("token-failure.history-token")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenURL.path))
        try FileManager.default.createDirectory(at: tokenURL, withIntermediateDirectories: false)
        let before = controller.analyticsStamp.revision
        let writer = controller.container.newBackgroundContext()
        writer.name = "external-token-fixture"
        try await writer.perform {
            let category = Category(context: writer); category.id = UUID(); category.name = "Merged despite token error"; category.income = false
            try writer.save()
        }
        do { try await controller.refreshPersistentHistory(); XCTFail("Expected token write failure") } catch {}
        XCTAssertGreaterThan(controller.analyticsStamp.revision, before)
        let categories = try controller.container.viewContext.fetch(Category.fetchRequest())
        XCTAssertEqual(categories.first?.name, "Merged despite token error")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tokenURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "A failed atomic write must not advance the token")
    }

    @MainActor
    func testSameAuthorExternalHistoryRefreshSurvivesSubsequentMaintenanceFailure() async throws {
        let controller = try await diskController(author: "same-author")
        let context = controller.container.viewContext
        let categoryReference = try await controller.saveCategory(CategoryInput(name: "Before", emoji: "🍎", colour: "#123456", income: false))
        try await controller.refreshPersistentHistory()
        let prior = controller.analyticsStamp.revision
        let storeURL = try XCTUnwrap(controller.container.persistentStoreCoordinator.persistentStores.first?.url)
        let external = NSPersistentContainer(name: AppIdentifiers.persistentModel, managedObjectModel: controller.container.managedObjectModel)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        external.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            external.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        controller.maintenanceSave = { _ in throw CocoaError(.fileWriteUnknown) }
        let writer = external.newBackgroundContext()
        writer.transactionAuthor = "same-author"
        writer.name = "independent-process-writer"
        try await writer.perform {
            let category = try writer.fetch(Category.fetchRequest()).first!
            category.name = "Imported"
            let seed = Transaction(context: writer)
            seed.id = UUID(); seed.date = Date().addingTimeInterval(-86400 * 2)
            seed.amount = 5; seed.income = false; seed.recurringType = 1; seed.recurringCoefficient = 1; seed.category = category
            try writer.save()
        }
        do { try await controller.refreshPersistentHistory(); XCTFail("Expected maintenance failure") } catch {}
        XCTAssertGreaterThan(controller.analyticsStamp.revision, prior, "Imported history must invalidate even when later maintenance fails")
        let categories = try context.fetch(Category.fetchRequest())
        XCTAssertEqual(categories.first?.name, "Imported")
        let failedStamp = controller.analyticsStamp
        do { try await controller.refreshPersistentHistory() } catch {}
        XCTAssertEqual(controller.analyticsStamp, failedStamp, "Consumed empty history and failed maintenance are not another successful update")
        controller.maintenanceSave = { try $0.save() }
        try await controller.refreshPersistentHistory()
        XCTAssertGreaterThan(controller.analyticsStamp.revision, failedStamp.revision)
        let after = controller.analyticsStamp
        try await controller.refreshPersistentHistory()
        XCTAssertEqual(controller.analyticsStamp, after)
        try await controller.deleteCategories([categoryReference])
        let metadata = try await controller.ledgerMetadataSnapshot(environment: AnalyticsEnvironment(stamp: controller.analyticsStamp))
        XCTAssertTrue(metadata.categories.isEmpty)
    }

    @MainActor
    func testRecurringMaintenanceAndMainBudgetReplacementRefreshCachedResults() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let seed = Transaction(context: context)
        seed.id = UUID(); seed.date = date(2026, 1, 1); seed.amount = 0.123456789; seed.income = false
        seed.recurringType = 1; seed.recurringCoefficient = 1
        try context.save()
        let before = controller.analyticsStamp.revision
        try await controller.catchUpRecurringTransactions(now: date(2026, 1, 3))
        XCTAssertGreaterThan(controller.analyticsStamp.revision, before)
        let after = controller.analyticsStamp
        try await controller.catchUpRecurringTransactions(now: date(2026, 1, 3))
        XCTAssertEqual(controller.analyticsStamp, after)
        let read = try await controller.ledgerListSnapshot(LedgerListRequest(query: .all, environment: AnalyticsEnvironment(stamp: after, calendar: utc)))
        XCTAssertEqual(read.spent, 0.123456789 * 3, accuracy: 1e-14)
        try await controller.upsertMainBudget(amount: 100, startDate: date(2026, 1, 1), type: 3)
        let first = try await controller.budgetDashboardSnapshot(environment: AnalyticsEnvironment(stamp: controller.analyticsStamp))
        try await controller.upsertMainBudget(amount: 200, startDate: date(2026, 1, 1), type: 3)
        let second = try await controller.budgetDashboardSnapshot(environment: AnalyticsEnvironment(stamp: controller.analyticsStamp))
        XCTAssertNotEqual(first.main?.id, second.main?.id)
        XCTAssertEqual(second.main?.read?.amount, 200)
    }

    @MainActor
    func testLargeHeterogeneousBudgetsAndInsightsMatchReferenceWithRealBoundedFetches() async throws {
        let controller = try await diskController()
        let context = controller.container.viewContext
        let now = date(2026, 3, 10, 12)
        var categories: [LittleSaverCore.Category] = []
        var definitions: [(URL, Int, BudgetWindow)] = []
        for index in 0..<100 {
            let category = Category(context: context); category.id = UUID(); category.name = "Category \(index)"; category.income = false
            categories.append(category)
            let budget = Budget(context: context); budget.id = UUID(); budget.category = category; budget.amount = 10000
            budget.type = Int16(index % 4 + 1); budget.startDate = date(2024, 1, 31)
            try context.obtainPermanentIDs(for: [budget])
            definitions.append((budget.objectID.uriRepresentation(), index, try XCTUnwrap(budget.currentWindow(now: now, calendar: utc))))
        }
        var rows: [(Int, Date, Double)] = []
        for index in 0..<6000 {
            let category = index % 100
            let timestamp = now.addingTimeInterval(Double(-(index / 100) * 86400))
            let amount = Double(index % 17) / 1000 + 0.123456789
            let row = Transaction(context: context); row.id = UUID(); row.date = timestamp; row.day = date(1999, 1, 1)
            row.category = categories[category]; row.income = false; row.amount = amount
            rows.append((category, timestamp, amount))
        }
        let main = MainBudget(context: context); main.amount = 100000; main.type = 4; main.startDate = date(2024, 2, 29)
        try context.save()
        let calls = FetchCalls()
        controller.analyticalFetchObserver = { entity, predicate, main in calls.record(main: main, entity: entity, predicate: predicate) }
        let environment = AnalyticsEnvironment(stamp: AnalyticsStamp(now: now), calendar: utc, firstWeekday: 2, firstDayOfMonth: 31)
        let dashboard = try await controller.budgetDashboardSnapshot(environment: environment)
        XCTAssertEqual(calls.count, 3)
        XCTAssertFalse(calls.usedMain)
        XCTAssertEqual(dashboard.budgets.count, 100)
        for (reference, category, window) in definitions {
            let expected = rows.filter { $0.0 == category && $0.1 >= window.start && $0.1 < window.end }.reduce(0) { $0 + $1.2 }
            XCTAssertEqual(try XCTUnwrap(dashboard.byReference[reference]?.spent), expected, accuracy: 1e-10)
        }
        let bounds = try XCTUnwrap(calls.predicates.first)
        XCTAssertFalse(bounds.evaluate(with: ["date": date(2020, 1, 1), "income": false]))
        XCTAssertFalse(bounds.evaluate(with: ["date": now.addingTimeInterval(1), "income": false]))
        calls.reset()
        let month = try await controller.analyticsInsightsSnapshot(InsightsRequest(start: date(2026, 2, 28), type: 2, environment: environment))
        let currentRows = rows.filter { $0.1 >= date(2026, 2, 28) }
        XCTAssertEqual(month.current.spent, currentRows.reduce(0) { $0 + $1.2 }, accuracy: 1e-9)
        XCTAssertEqual(month.expenses.categories.count, 100)
        XCTAssertEqual(month.expenses.categories.reduce(0) { $0 + $1.amount }, month.current.spent, accuracy: 1e-9)
        XCTAssertEqual(month.expenses.totals.values.reduce(0, +), month.current.spent, accuracy: 1e-9)
        XCTAssertEqual(calls.count, 1)
        let insightsBounds = try XCTUnwrap(calls.predicates.first)
        XCTAssertFalse(insightsBounds.evaluate(with: ["date": date(2026, 1, 30)]))
        XCTAssertTrue(insightsBounds.evaluate(with: ["date": date(2026, 1, 31)]))
        XCTAssertFalse(insightsBounds.evaluate(with: ["date": now.addingTimeInterval(1)]))
        let history = try await controller.ledgerListSnapshot(LedgerListRequest(query: .interval(start: date(2026, 2, 28), end: date(2026, 3, 31), income: false, category: nil), environment: environment))
        XCTAssertEqual(history.spent, month.current.spent, accuracy: 1e-9)
        XCTAssertEqual(Set(history.days.compactMap(\.date)), Set(currentRows.map { utc.startOfDay(for: $0.1) }))
    }

    @MainActor
    func testCivilHistorySelectionUsesOneWindowForSnapshotBarAndListAfterTimezoneRefresh() async throws {
        let controller = try await diskController()
        var taipei = utc; taipei.timeZone = TimeZone(identifier: "Asia/Taipei")!
        var losAngeles = utc; losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = date(2026, 5, 10)
        for preferred in [1, 29, 30, 31] {
            let original = try XCTUnwrap(LedgerCalendar.monthStart(in: date(2026, 2, 15), day: preferred, calendar: taipei))
            let selection = CalendarPeriodSelection(start: original, calendar: taipei)
            let projected = selection.start(period: .month, now: now, calendar: losAngeles, firstDayOfMonth: preferred)
            let end = try XCTUnwrap(LedgerCalendar.insightsEnd(start: projected, type: 2, firstDayOfMonth: preferred, calendar: losAngeles))
            let row = Transaction(context: controller.container.viewContext)
            row.id = UUID(); row.amount = Double(preferred); row.income = false
            row.date = projected.addingTimeInterval(3600); row.day = original
            try controller.container.viewContext.save()
            let environment = AnalyticsEnvironment(stamp: AnalyticsStamp(revision: UInt64(preferred), now: now), calendar: losAngeles, firstDayOfMonth: preferred)
            let snapshot = try await controller.analyticsInsightsSnapshot(InsightsRequest(start: projected, type: 2, environment: environment))
            let list = try await controller.ledgerListSnapshot(LedgerListRequest(query: .interval(start: projected, end: end, income: false, category: nil), environment: environment))
            XCTAssertEqual(snapshot.expenses.amount, list.spent)
            XCTAssertEqual(snapshot.expenses.totals.values.reduce(0, +), list.spent)
            XCTAssertTrue(list.rows.contains { $0.uuid == row.id })
            XCTAssertEqual(snapshot.expenses.dates.first, projected)
            XCTAssertEqual(losAngeles.component(.hour, from: projected), 0)
            XCTAssertEqual(losAngeles.component(.day, from: end), preferred)
        }
    }

    func testPresentationWiringKeepsRefreshContainersMountedAndAnalyticsOffMainFetchRequests() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let home = try String(contentsOf: app.appendingPathComponent("LittleSaver/Views/HomeView.swift"))
        let presentation = try String(contentsOf: app.appendingPathComponent("LittleSaver/Utilities/AnalyticsPresentation.swift"))
        XCTAssertTrue(home.contains(".environment(\\.ledgerMetadata, metadata.value)"))
        XCTAssertFalse(home.contains("metadata.value(for:"))
        XCTAssertTrue(presentation.contains("if let value = model.value {"))
        XCTAssertTrue(presentation.contains(".accessibilityHidden(model.value(for: key) == nil)"))
        let viewSources = [
            "LogView": "LittleSaver/Views/Log/LogView.swift",
            "InsightsView": "LittleSaver/Views/Insights/InsightsView.swift",
            "BudgetView": "LittleSaver/Views/Budget/BudgetView.swift",
        ]
        for (name, path) in viewSources {
            let source = try String(contentsOf: app.appendingPathComponent(path))
            XCTAssertFalse(source.contains("FetchedResults<Transaction>"), name)
            XCTAssertFalse(source.contains("NSManagedObjectContextDidSave"), name)
            XCTAssertFalse(source.contains("getLogViewTotal"), name)
            XCTAssertFalse(source.contains("getInsights("), name)
        }
    }

    @MainActor
    func testYearMarchDrilldownUsesTheSameNaturalMonthAsItsBar() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        for (timestamp, amount) in [(date(2026, 4, 1).addingTimeInterval(-1), 7.0), (date(2026, 4, 1), 11.0), (date(2026, 4, 14, 12), 13.0), (date(2026, 4, 15), 17.0)] {
            let row = Transaction(context: context); row.id = UUID(); row.date = timestamp; row.income = false; row.amount = amount
        }
        try context.save()
        let environment = AnalyticsEnvironment(stamp: AnalyticsStamp(now: date(2026, 5, 1)), calendar: utc, firstDayOfMonth: 15)
        let query = LedgerListQuery.insightsDrilldown(date: date(2026, 3, 1), chartType: 3, income: false, environment: environment)
        let drilldown = try await controller.ledgerListSnapshot(LedgerListRequest(query: query, environment: environment))
        XCTAssertEqual(drilldown.spent, 7)
        let year = try await controller.analyticsInsightsSnapshot(InsightsRequest(start: date(2026, 1, 1), type: 3, environment: environment))
        XCTAssertEqual(year.expenses.totals[date(2026, 3, 1)], drilldown.spent)
        XCTAssertEqual(year.expenses.totals[date(2026, 4, 1)], 41)
        let month = try await controller.analyticsInsightsSnapshot(InsightsRequest(start: date(2026, 3, 15), type: 2, environment: environment))
        XCTAssertEqual(month.expenses.amount, 31)
    }

    @MainActor
    func testLogGoldenRollingWindowsKeepCarryInSeparateFromSummary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let controller = try DataController(configuration: .init(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: directory.appendingPathComponent("analytics.sqlite"), reloadWidgetsAfterSave: false))
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let now = date(2026, 3, 10, 12)
        for (timestamp, amount, income) in [(date(2025, 1, 1, 12), 100.0, true), (date(2026, 3, 3), 10, false), (date(2026, 3, 4).addingTimeInterval(-1), 2, false), (date(2026, 3, 9, 9), 30, true), (now, 5, false), (now.addingTimeInterval(1), 999, false)] {
            let row = Transaction(context: context); row.id = UUID(); row.date = timestamp; row.amount = amount; row.income = income
        }
        try context.save()
        let environment = AnalyticsEnvironment(stamp: AnalyticsStamp(now: now), calendar: utc, firstWeekday: 2, firstDayOfMonth: 15)
        let expected: [(Double, Double)] = [(0,5),(30,5),(30,17),(30,17),(130,17)]
        for type in 1...5 {
            let snapshot = try await controller.logSnapshot(LogRequest(timeframe: type, environment: environment))
            XCTAssertEqual(snapshot.totals.income, expected[type-1].0)
            XCTAssertEqual(snapshot.totals.spent, expected[type-1].1)
            if type < 3 {
                XCTAssertEqual(snapshot.expensePoints.map(\.amount), [12,0,0,0,0,0,0,5])
                XCTAssertEqual(snapshot.incomePoints.map(\.amount), [0,0,0,0,0,0,30,0])
                XCTAssertEqual(snapshot.netPoints.map(\.amount), [88,88,88,88,88,88,118,113])
            } else if type == 3 {
                XCTAssertEqual(snapshot.netPoints.count, 29)
                XCTAssertEqual(snapshot.netPoints.first?.amount, 100)
                XCTAssertEqual(snapshot.netPoints.last?.amount, 113)
            } else if type == 4 {
                XCTAssertEqual(snapshot.netPoints.count, 13)
                XCTAssertEqual(snapshot.netPoints.dropLast().map(\.amount), Array(repeating: 100, count: 12))
                XCTAssertEqual(snapshot.netPoints.last?.amount, 113)
            } else { XCTAssertTrue(snapshot.netPoints.isEmpty) }
        }
    }

    @MainActor
    func testSameRequestIsLoadedOnlyOnceAndNewRequestOnce() async {
        let model = SnapshotModel<Int, Int>()
        var requests: [Int] = []
        let loader: (Int) async throws -> Int = { key in requests.append(key); return key }
        await model.load(key: 1, using: loader)
        await model.load(key: 1, using: loader)
        await model.load(key: 2, using: loader)
        await model.load(key: 2, using: loader)
        XCTAssertEqual(requests, [1, 2])
        XCTAssertEqual(model.value, 2)
    }

    @MainActor
    func testFailureAndCancelledRequestsCanRetryTheSameKey() async {
        let model = SnapshotModel<Int, Int>()
        await model.load(key: 1) { _ in throw CocoaError(.fileReadUnknown) }
        XCTAssertNotNil(model.error)
        await model.load(key: 1) { _ in 3 }
        XCTAssertEqual(model.value, 3)
        var pending: CheckedContinuation<Int, Never>?
        let old = Task { await model.load(key: 2) { _ in await withCheckedContinuation { pending = $0 } } }
        while pending == nil { await Task.yield() }
        old.cancel()
        await model.load(key: 2) { _ in 4 }
        pending?.resume(returning: 2)
        await old.value
        XCTAssertEqual(model.value, 4)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
    }

    @MainActor
    func testStaleCompletionCannotReplaceNewSelection() async {
        let model = SnapshotModel<Int, Int>()
        var first: CheckedContinuation<Int, Never>?
        let old = Task { await model.load(key: 1) { _ in await withCheckedContinuation { first = $0 } } }
        while first == nil { await Task.yield() }
        await model.load(key: 2) { $0 }
        first?.resume(returning: 1)
        await old.value
        XCTAssertEqual(model.value, 2)
    }

    @MainActor
    func testBudgetWindowIndexPreservesSmallRecentAmounts() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let category = Category(context: context); category.id = UUID(); category.name = "Shared"
        let now = date(2026, 3, 10, 12)
        // Category.budget is a to-one inverse. Exercise each valid period on its
        // single budget instead of accidentally orphaning 99 definitions.
        let budget = Budget(context: context); budget.id = UUID(); budget.amount = 100; budget.category = category
        budget.startDate = date(2024, 1, 1)
        for (timestamp, amount) in [(date(2026, 1, 1), 1e20), (now, 0.123456789)] {
            let row = Transaction(context: context); row.id = UUID(); row.date = timestamp; row.amount = amount; row.income = false; row.category = category
        }
        for type in 1...4 {
            budget.type = Int16(type)
            try context.save()
            let snapshot = try await controller.budgetDashboardSnapshot(environment: AnalyticsEnvironment(stamp: AnalyticsStamp(now: now), calendar: utc))
            XCTAssertEqual(snapshot.budgets.count, 1)
            let read = try XCTUnwrap(snapshot.budgets.first?.read)
            XCTAssertEqual(read.spent, read.type == 4 ? 1e20 : 0.123456789)
        }
    }

    @MainActor
    func testOverflowRemainsUnavailableAcrossSQLSnapshotsInsteadOfBecomingZero() async throws {
        let controller = try await diskController()
        let context = controller.container.viewContext
        let category = Category(context: context); category.id = UUID(); category.name = "Overflow"
        let now = date(2026, 3, 10, 12)
        let budget = Budget(context: context); budget.id = UUID(); budget.amount = 100; budget.category = category; budget.type = 1; budget.startDate = now
        for _ in 0..<2 {
            let row = Transaction(context: context); row.id = UUID(); row.date = now; row.amount = Double.greatestFiniteMagnitude; row.income = false; row.category = category
        }
        try context.save()
        let environment = AnalyticsEnvironment(stamp: AnalyticsStamp(now: now), calendar: utc)
        let dashboard = try await controller.budgetDashboardSnapshot(environment: environment)
        XCTAssertNil(dashboard.budgets.first?.read)
        let log = try await controller.logSnapshot(LogRequest(timeframe: 5, environment: environment))
        XCTAssertFalse(log.totals.spent.isFinite)
        let insights = try await controller.analyticsInsightsSnapshot(InsightsRequest(start: date(2026, 3, 1), type: 2, environment: environment))
        XCTAssertFalse(insights.current.spent.isFinite)
        let list = try await controller.ledgerListSnapshot(LedgerListRequest(query: .all, environment: environment))
        XCTAssertFalse(list.spent.isFinite)
    }

    @MainActor
    func testConcurrentIdenticalRequestsCoalesceAndRealQueryInputsChangeIdentity() async {
        let model = SnapshotModel<LogRequest, Int>()
        let stamp = AnalyticsStamp(now: date(2026, 3, 10, 12))
        let environment = AnalyticsEnvironment(stamp: stamp, calendar: utc, firstWeekday: 2, firstDayOfMonth: 31)
        let request = LogRequest(timeframe: 3, environment: environment)
        var pending: CheckedContinuation<Int, Never>?
        let first = Task { await model.load(key: request) { _ in await withCheckedContinuation { pending = $0 } } }
        while pending == nil { await Task.yield() }
        await model.load(key: request) { _ in XCTFail("Duplicate in-flight read"); return 2 }
        pending?.resume(returning: 1); await first.value
        XCTAssertEqual(model.value(for: request), 1)
        XCTAssertNotEqual(request, LogRequest(timeframe: 2, environment: environment))
        XCTAssertNotEqual(request, LogRequest(timeframe: 3, environment: AnalyticsEnvironment(stamp: stamp, calendar: utc, firstWeekday: 2, firstDayOfMonth: 30)))
        XCTAssertNotEqual(request, LogRequest(timeframe: 3, environment: AnalyticsEnvironment(stamp: AnalyticsStamp(revision: 1, now: stamp.now), calendar: utc, firstWeekday: 2, firstDayOfMonth: 31)))
        var changedZone = utc; changedZone.timeZone = TimeZone(identifier: "Asia/Taipei")!
        XCTAssertNotEqual(request, LogRequest(timeframe: 3, environment: AnalyticsEnvironment(stamp: stamp, calendar: changedZone, firstWeekday: 2, firstDayOfMonth: 31)))
    }

    @MainActor
    func testActualBudgetFetchCountDoesNotScaleWithRowCount() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        func addBudget() {
            let category = Category(context: context); category.id = UUID(); category.name = "Food"
            let budget = Budget(context: context); budget.id = UUID(); budget.category = category
            budget.amount = 100; budget.startDate = now.addingTimeInterval(-86400); budget.type = 1
        }
        addBudget(); try context.save()
        let calls = FetchCalls()
        controller.analyticalFetchObserver = { _, _, main in calls.record(main: main) }
        _ = try await controller.budgetSnapshots(now: now)
        let one = calls.count
        for _ in 1..<100 { addBudget() }
        try context.save(); calls.reset()
        _ = try await controller.budgetSnapshots(now: now)
        XCTAssertEqual(calls.count, one)
        XCTAssertLessThanOrEqual(calls.count, 4)
        XCTAssertFalse(calls.usedMain)
    }
}

private final class FetchCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var number = 0
    private var main = false
    private var capturedPredicates: [NSPredicate] = []
    var predicates: [NSPredicate] { lock.lock(); defer { lock.unlock() }; return capturedPredicates }
    var count: Int { lock.lock(); defer { lock.unlock() }; return number }
    var usedMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
    func record(main: Bool, entity: String? = nil, predicate: NSPredicate? = nil) {
        lock.lock(); defer { lock.unlock() }; number += 1; self.main = self.main || main
        if entity == "Transaction", let predicate { capturedPredicates.append(predicate) }
    }
    func reset() { lock.lock(); defer { lock.unlock() }; number = 0; main = false; capturedPredicates = [] }
}
