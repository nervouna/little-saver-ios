import CoreData
import LittleSaverCore
import XCTest
@testable import LittleSaver

final class BudgetCalendarMoneyTests: XCTestCase {
    @MainActor
    func testDamagedBudgetEditorStartsAtCategoryRepair() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let budget = Budget(context: controller.container.viewContext)
        budget.id = UUID(); budget.type = 3; budget.amount = 123.456
        budget.startDate = date(2025, 1, 31)
        try controller.container.viewContext.save()
        let editor = BrandNewBudgetView(overallBudgetCreated: true, toEditBudget: budget, calendar: utc, preferredWeekday: 1, preferredMonthDay: 1)
        XCTAssertEqual(editor.progress, 2)
        XCTAssertEqual(editor.initialProgress, 2)
        XCTAssertTrue(editor.canGoBack(from: 3))
        XCTAssertFalse(editor.canGoBack(from: 2))
        XCTAssertEqual(editor.chosenDayMonth, 31)
        let originalID = budget.id
        _ = try await controller.saveCategory(CategoryInput(name: "Repair", emoji: "🍎", colour: "#123456", income: false))
        let category = try XCTUnwrap(controller.container.viewContext.fetch(Category.fetchRequest()).first)
        // Exercise the submission method used by the actual form after choosing a category.
        try await editor.saveCategoryBudget(using: controller, category: category, amount: 987.654321, proposedStart: date(2026, 3, 31), calendar: utc)
        let saved = try XCTUnwrap(controller.container.viewContext.fetch(Budget.fetchRequest()).first)
        XCTAssertEqual(try controller.container.viewContext.count(for: Budget.fetchRequest()), 1)
        XCTAssertEqual(saved.id, originalID)
        XCTAssertEqual(saved.category, category)
        XCTAssertEqual(saved.amount, 987.654321)
        XCTAssertEqual(saved.type, 3)
        XCTAssertEqual(saved.startDate, date(2025, 1, 31))
    }

    @MainActor
    func testOpenedMonthSelectionReprojectsAcrossTimezone() async throws {
        var taipei = utc; taipei.timeZone = TimeZone(identifier: "Asia/Taipei")!
        var losAngeles = utc; losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        // The same selection value is held by MonthGraph, not an old-zone instant.
        let selection = CalendarPeriodSelection(start: date(2026, 3, 1, calendar: taipei), calendar: taipei)
        let selectedStart = selection.start(period: .month, calendar: losAngeles)
        let end = try XCTUnwrap(LedgerCalendar.insightsEnd(start: selectedStart, type: 2, firstDayOfMonth: 1, calendar: losAngeles))
        XCTAssertEqual(selectedStart, date(2026, 3, 1, calendar: losAngeles))
        XCTAssertEqual(end, date(2026, 4, 1, calendar: losAngeles))
        let graph = controller.getInsights(type: 2, date: selectedStart, income: false, now: date(2026, 5, 1), calendar: losAngeles, firstDayOfMonth: 1)
        XCTAssertEqual(graph.dates.count, 31)
    }

    @MainActor
    func testEditorAmountOnlyPreservesWeekAndMonthScheduleThroughPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = DataController.Configuration(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: directory.appendingPathComponent("editor.sqlite"), reloadWidgetsAfterSave: false)
        let writer = try DataController(configuration: configuration)
        var ids: [UUID] = []
        for type: Int16 in [2, 3] {
            let reference = try await writer.saveCategory(CategoryInput(name: "Category \(type)", emoji: type == 2 ? "🍎" : "🚗", colour: "#123456", income: false))
            let anchor = date(2025, 1, 31)
            try await writer.saveBudget(category: reference, amount: 100.123, startDate: anchor, type: type)
            let budget = try XCTUnwrap(writer.container.viewContext.fetch(Budget.fetchRequest()).first { $0.type == type })
            let editor = BrandNewBudgetView(overallBudgetCreated: true, toEditBudget: budget, calendar: utc, preferredWeekday: 1, preferredMonthDay: 1)
            XCTAssertEqual(editor.progress, 3)
            XCTAssertFalse(editor.canGoBack(from: 3))
            XCTAssertEqual(type == 2 ? editor.chosenDayWeek : editor.chosenDayMonth, type == 2 ? 6 : 31)
            XCTAssertEqual(editor.retainedScheduleAnchor(proposed: date(2026, 3, 1), calendar: utc), anchor)
            ids.append(try XCTUnwrap(budget.id))
            try await editor.saveCategoryBudget(using: writer, category: editor.selectedCategory, amount: 234.56789123, proposedStart: date(2026, 3, 1), calendar: utc)
        }
        // Independent coordinator reopen, without detaching a store with pending callbacks.
        let reader = try DataController(configuration: configuration)
        try await reader.waitUntilReady()
        let rows = try reader.container.viewContext.fetch(Budget.fetchRequest())
        XCTAssertEqual(Set(rows.compactMap(\.id)), Set(ids))
        for row in rows {
            XCTAssertEqual(row.startDate, date(2025, 1, 31))
            XCTAssertEqual(row.amount, 234.56789123)
            XCTAssertNotNil(row.category)
        }
    }

    @MainActor
    func testCivilSelectionsKeepHistoryAndAllMonthQueryConsumersAligned() async throws {
        var taipei = utc; taipei.timeZone = TimeZone(identifier: "Asia/Taipei")!
        var losAngeles = utc; losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = date(2026, 5, 15, 12, calendar: losAngeles)
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        for preferredDay in [1, 29, 30, 31] {
            let original = date(2026, 2, min(28, preferredDay), calendar: taipei)
            var historical = CalendarPeriodSelection()
            historical.select(original, period: .month, now: now, calendar: taipei, firstDayOfMonth: preferredDay)
            let start = historical.start(period: .month, now: now, calendar: losAngeles, firstDayOfMonth: preferredDay)
            let end = try XCTUnwrap(LedgerCalendar.insightsEnd(start: start, type: 2, firstDayOfMonth: preferredDay, calendar: losAngeles))
            XCTAssertEqual(start, date(2026, 2, min(28, preferredDay), calendar: losAngeles))
            XCTAssertEqual(end, date(2026, 3, preferredDay, calendar: losAngeles))
            XCTAssertEqual(historical.start(period: .month, now: now, calendar: taipei, firstDayOfMonth: preferredDay), original)
            let predicate = LedgerCalendar.insightsPredicate(start: start, type: 2, now: now, firstDayOfMonth: preferredDay, calendar: losAngeles)
            for (timestamp, amount) in [(start, 2.0), (end.addingTimeInterval(-1), 3.0), (end, 7.0)] {
                let row = Transaction(context: context); row.id = UUID(); row.date = timestamp; row.income = false; row.amount = amount
            }
            try context.save()
            let request = controller.fetchRequestForInsights(type: 2, date: start, income: false, now: now, calendar: losAngeles, firstDayOfMonth: preferredDay)
            let rows = try context.fetch(request)
            XCTAssertEqual(rows.count, 2)
            XCTAssertTrue(rows.allSatisfy { predicate.evaluate(with: $0) })
            let graph = controller.getInsights(type: 2, date: start, income: false, now: now, calendar: losAngeles, firstDayOfMonth: preferredDay)
            XCTAssertEqual(graph.amount, 5)
            XCTAssertEqual(graph.dates.first, start)
            XCTAssertEqual(graph.dateDictionary.values.reduce(0, +), rows.reduce(0) { $0 + $1.amount })
            XCTAssertEqual(graph.dates.count, losAngeles.dateComponents([.day], from: start, to: end).day)
            for row in try context.fetch(Transaction.fetchRequest()) { context.delete(row) }
            try context.save()
            var current = CalendarPeriodSelection()
            current.select(getStartOfMonth(startDay: preferredDay, now: now, calendar: taipei), period: .month, now: now, calendar: taipei, firstDayOfMonth: preferredDay)
            XCTAssertEqual(current.start(period: .month, now: now, calendar: losAngeles, firstDayOfMonth: preferredDay), getStartOfMonth(startDay: preferredDay, now: now, calendar: losAngeles))
        }
        for period in [BudgetPeriod.day, .week, .year] {
            let source = CalendarPeriodSelection(start: date(2025, 3, 10, calendar: taipei), calendar: taipei)
            let local = CalendarPeriodSelection(start: date(2025, 3, 10, calendar: losAngeles), calendar: losAngeles)
            for weekday in [1, 2, 7] {
                XCTAssertEqual(source.start(period: period, now: now, calendar: losAngeles, firstWeekday: weekday), local.start(period: period, now: now, calendar: losAngeles, firstWeekday: weekday))
            }
        }
        // An open current-period selection follows the new local calendar across midnight.
        let boundaryNow = date(2026, 3, 1, calendar: taipei)
        XCTAssertEqual(CalendarPeriodSelection().start(period: .month, now: boundaryNow, calendar: losAngeles), date(2026, 2, 1, calendar: losAngeles))
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testAnchoredMonthAndLeapYearWindowsDoNotDrift() throws {
        let january = date(2025, 1, 31)
        let february = try XCTUnwrap(BudgetPeriod.month.window(anchor: january, index: 1, calendar: utc))
        XCTAssertEqual(february.start, date(2025, 2, 28))
        XCTAssertEqual(february.end, date(2025, 3, 31))
        XCTAssertEqual(BudgetPeriod.month.window(anchor: january, containing: date(2025, 3, 30), calendar: utc), february)
        XCTAssertEqual(BudgetPeriod.month.window(anchor: january, containing: february.end, calendar: utc)?.index, 2)
        XCTAssertEqual(BudgetPeriod.month.window(anchor: january, index: 2, calendar: utc)?.end, date(2025, 4, 30))
        let leap = date(2024, 2, 29)
        XCTAssertEqual(BudgetPeriod.year.window(anchor: leap, index: 1, calendar: utc)?.start, date(2025, 2, 28))
        XCTAssertEqual(BudgetPeriod.year.window(anchor: leap, index: 4, calendar: utc)?.start, date(2028, 2, 29))
        XCTAssertEqual(BudgetPeriod.year.window(anchor: leap, index: -1, calendar: utc)?.start, date(2023, 2, 28))
        XCTAssertNil(BudgetPeriod(rawValue: 0))
        XCTAssertNil(BudgetPeriod.day.window(anchor: january, index: Int.max, calendar: utc))
        XCTAssertNil(BudgetPeriod.year.window(anchor: january, index: Int.min, calendar: utc))
        XCTAssertNil(BudgetPeriod.day.window(anchor: Date(timeIntervalSince1970: .infinity), index: 0))
    }

    func testDailyWindowsUseCurrentLocalCalendarIncludingDSTAndMovedTimezone() throws {
        var losAngeles = utc; losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let anchor = date(2026, 1, 1, calendar: losAngeles)
        let spring = try XCTUnwrap(BudgetPeriod.day.window(anchor: anchor, containing: date(2026, 3, 8, 12, calendar: losAngeles), calendar: losAngeles))
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 3600)
        let fall = try XCTUnwrap(BudgetPeriod.day.window(anchor: anchor, containing: date(2026, 11, 1, 12, calendar: losAngeles), calendar: losAngeles))
        XCTAssertEqual(fall.end.timeIntervalSince(fall.start), 25 * 3600)
        let moved = try XCTUnwrap(BudgetPeriod.day.window(anchor: date(2026, 1, 1), containing: date(2026, 3, 8, 12, calendar: losAngeles), calendar: losAngeles))
        XCTAssertEqual(moved.start, spring.start)
        XCTAssertEqual(moved.end, spring.end)
        let selectedIndex = try XCTUnwrap(BudgetPeriod.month.window(anchor: date(2025, 1, 31), containing: date(2025, 3, 15), calendar: utc)).index
        let selectionAfterMove = try XCTUnwrap(BudgetPeriod.month.window(anchor: date(2025, 1, 31), index: selectedIndex, calendar: losAngeles))
        XCTAssertEqual(selectionAfterMove.index, selectedIndex)
        XCTAssertEqual(selectionAfterMove.start, losAngeles.startOfDay(for: selectionAfterMove.start))
        XCTAssertTrue(selectionAfterMove.transactionPredicate(now: selectionAfterMove.end).evaluate(with: ["date": selectionAfterMove.start]))
        let future = BudgetPeriod.month.currentWindow(anchor: date(2099, 1, 31), amount: 10, now: date(2026, 1, 1), calendar: utc)
        XCTAssertEqual(future?.index, 0)
        XCTAssertEqual(future?.progress(at: date(2026, 1, 1)), 0)
    }

    func testHalfOpenWindowAndInclusiveNowPredicate() throws {
        let start = date(2026, 1, 1)
        let end = date(2026, 1, 2)
        let now = date(2026, 1, 1, 12)
        let predicate = LedgerCalendar.predicate(start: start, end: end, now: now)
        XCTAssertTrue(predicate.evaluate(with: ["date": start]))
        XCTAssertTrue(predicate.evaluate(with: ["date": now]))
        XCTAssertFalse(predicate.evaluate(with: ["date": now.addingTimeInterval(1)]))
        XCTAssertFalse(LedgerCalendar.predicate(start: start, end: end).evaluate(with: ["date": end]))
        XCTAssertTrue(LedgerCalendar.predicate(start: start, end: end, now: start).evaluate(with: ["date": start]))
    }

    func testPreferredMonthStartClampsEachOccurrenceWithoutLosingPreferredDay() {
        for day in [29, 30, 31] {
            XCTAssertEqual(getStartOfMonth(startDay: day, now: date(2025, 2, 28, 12), calendar: utc), date(2025, 2, 28))
            XCTAssertEqual(getStartOfMonth(startDay: day, now: date(2025, 3, 1), calendar: utc), date(2025, 2, 28))
            XCTAssertEqual(getStartOfMonth(startDay: day, now: date(2025, 3, 31), calendar: utc), date(2025, 3, day))
            XCTAssertEqual(calculateStartOfMonthPeriod(earliestDate: date(2025, 3, 1), startOfMonthDay: day, calendar: utc), date(2025, 2, 28))
        }
        XCTAssertEqual(getStartOfMonth(startDay: 31, now: date(2024, 2, 29), calendar: utc), date(2024, 2, 29))
    }

    func testMoneyBoundaryPreservesPrecisionAndKeypadDeletionHandlesHugeFiniteValues() throws {
        let original = 123.456789012345
        XCTAssertEqual(try XCTUnwrap(MoneyAmount(original)).value, original)
        XCTAssertEqual(MoneyAmount(-0.0)?.value.sign, .plus)
        XCTAssertNil(MoneyAmount(.infinity))
        XCTAssertNil(MoneyAmount(.nan))
        let huge = Double.greatestFiniteMagnitude
        XCTAssertEqual(MoneyAmount.deletingLastDigit(huge, centsEntry: true), huge / 10)
        XCTAssertEqual(MoneyAmount.deletingLastDigit(huge, centsEntry: false), huge / 10)
        XCTAssertEqual(MoneyAmount.truncating(huge, decimalPlaces: 1), huge)
        XCTAssertEqual(MoneyAmount.deletingLastDigit(123.45, centsEntry: true), 12.34)
        XCTAssertEqual(MoneyAmount.deletingLastDigit(123.45, centsEntry: false), 12)
        XCTAssertEqual(MoneyAmount.truncating(123.45, decimalPlaces: 1), 123.4)
        for code in ["USD", "EUR", "JPY"] {
            XCTAssertFalse(localizedCurrencyAmount(original, currencyCode: code, showCents: true).isEmpty)
            XCTAssertEqual(MoneyAmount(original)?.value, original)
        }
    }

    @MainActor
    func testSQLiteDayQueriesAndGroupsIgnorePersistedMidnightFromPreviousTimezone() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = DataController.Configuration(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: directory.appendingPathComponent("calendar.sqlite"), reloadWidgetsAfterSave: false)
        let writer = try DataController(configuration: configuration)
        try await writer.waitUntilReady()
        var taipei = utc; taipei.timeZone = TimeZone(identifier: "Asia/Taipei")!
        var losAngeles = utc; losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let context = writer.container.viewContext
        let day = date(2026, 3, 8, calendar: losAngeles)
        let next = date(2026, 3, 9, calendar: losAngeles)
        for (note, timestamp) in [("before", day.addingTimeInterval(-1)), ("start", day), ("inside", next.addingTimeInterval(-1)), ("next", next)] {
            let row = Transaction(context: context)
            row.id = UUID(); row.note = note; row.date = timestamp; row.day = taipei.startOfDay(for: timestamp); row.amount = 1; row.income = false
        }
        let undated = Transaction(context: context)
        undated.id = UUID(); undated.note = "undated"; undated.day = day; undated.income = false
        try context.save()
        // Independent coordinator reopen: the writer remains alive until callbacks finish.
        let reader = try DataController(configuration: configuration)
        try await reader.waitUntilReady()
        let request = Transaction.fetchRequest()
        request.predicate = LedgerCalendar.dayPredicate(day, now: next, calendar: losAngeles)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LittleSaverCore.Transaction.date, ascending: true)]
        let found = try reader.container.viewContext.fetch(request)
        XCTAssertEqual(found.map(\.note), ["start", "inside"])
        XCTAssertNotEqual(found.first?.day, day)
        let groups = LedgerCalendar.groupedTransactions(found, calendar: losAngeles)
        XCTAssertEqual(groups.map(\.date), [day])
        XCTAssertEqual(groups.first?.transactions.count, 2)
        let all = try reader.container.viewContext.fetch(Transaction.fetchRequest())
        let grouped = LedgerCalendar.groupedTransactions(all, calendar: losAngeles)
        XCTAssertEqual(grouped.last?.transactions.first?.note, "undated")
        XCTAssertNil(grouped.last?.date)
        XCTAssertFalse(reader.container.viewContext.hasChanges)
        XCTAssertEqual(try reader.container.viewContext.count(for: Transaction.fetchRequest()), 5)
    }

    @MainActor
    func testMainBudgetReadsMatchCategoryWindowAndDoNotMintRevisions() async throws {
        let controller = try DataController(configuration: .inMemory)
        let categoryRef = try await controller.saveCategory(CategoryInput(name: "Food", emoji: "🍎", colour: "#123456", income: false))
        let anchor = date(2024, 1, 31)
        try await controller.saveBudget(category: categoryRef, amount: 100, startDate: anchor, type: 3)
        try await controller.upsertMainBudget(amount: 100, startDate: anchor, type: 3)
        let now = date(2026, 3, 31)
        for (note, timestamp, amount) in [("old", date(2026, 2, 28), 9.0), ("boundary", now, 3.0), ("future", now.addingTimeInterval(1), 20.0)] {
            try await controller.saveTransaction(TransactionInput(category: categoryRef, note: note, income: false, amount: amount, date: timestamp))
        }
        let context = controller.container.viewContext
        let budget = try XCTUnwrap(context.fetch(Budget.fetchRequest()).first)
        let main = try XCTUnwrap(LedgerMaintenance.currentMainBudget(in: context))
        let revision = main.revision
        let count = try context.count(for: MainBudget.fetchRequest())
        let category = try await controller.budgetSnapshot(identifier: budget.id!.uuidString, now: now, calendar: utc)
        let overall = try await controller.mainBudgetSnapshot(now: now, calendar: utc)
        XCTAssertEqual(category?.startDate, now)
        XCTAssertEqual(category?.endDate, date(2026, 4, 30))
        XCTAssertEqual(category?.spent, 3)
        XCTAssertEqual(overall?.spent, category?.spent)
        XCTAssertEqual(overall?.startDate, category?.startDate)
        XCTAssertEqual(overall?.endDate, category?.endDate)
        XCTAssertEqual(overall?.progress, 0)
        XCTAssertEqual(main.startDate, anchor)
        XCTAssertEqual(main.revision, revision)
        XCTAssertEqual(try context.count(for: MainBudget.fetchRequest()), count)
        XCTAssertFalse(context.hasChanges)
        for amount in [0.0, -1, .infinity, .nan] {
            main.amount = amount; try context.save()
            XCTAssertTrue(try context.fetch(controller.fetchRequestForMainBudgetTransactions(budget: main, now: now, calendar: utc)).isEmpty)
            let unavailable = try await controller.mainBudgetSnapshot(now: now, calendar: utc)
            XCTAssertNil(unavailable)
        }
        main.amount = 100; main.type = 0; try context.save()
        let invalidType = try await controller.mainBudgetSnapshot(now: now, calendar: utc)
        XCTAssertNil(invalidType)
        main.type = 3; main.startDate = nil; try context.save()
        let invalidAnchor = try await controller.mainBudgetSnapshot(now: now, calendar: utc)
        XCTAssertNil(invalidAnchor)
        try await controller.deleteMainBudget()
        let deleted = try await controller.mainBudgetSnapshot(now: now, calendar: utc)
        XCTAssertNil(deleted)
    }

    @MainActor
    func testCommandAndCSVPrecisionSurviveFormattingAndSQLiteReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = DataController.Configuration(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: directory.appendingPathComponent("money.sqlite"), reloadWidgetsAfterSave: false)
        let controller = try DataController(configuration: configuration)
        let category = try await controller.saveCategory(CategoryInput(name: "Food", emoji: "🍎", colour: "#123456", income: false))
        let original = 123.456789012345
        try await controller.saveTransaction(TransactionInput(category: category, note: "command", income: false, amount: original, date: date(2026, 1, 1)))
        try await controller.saveTemplate(TransactionInput(category: category, note: "template", income: false, amount: original, date: date(2026, 1, 1)), order: 0)
        try await controller.saveBudget(category: category, amount: original, startDate: date(2026, 1, 1), type: 1)
        try await controller.upsertMainBudget(amount: original, startDate: date(2026, 1, 1), type: 1)
        _ = try await CSVTransactionImporter.importRows([["Food", "csv", "2026-01-02", String(original)]], mapping: CSVImportMapping(categoryColumn: 0, noteColumn: 1, dateColumn: 2, amountColumn: 3), dateFormat: "yyyy-MM-dd", categoriesByName: ["Food": category], into: controller, timeZone: utc.timeZone)
        let suiteName = "T5-currency-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        for currency in ["USD", "EUR", "JPY"] {
            preferences.set(currency, forKey: "currency")
            let rows = try controller.container.viewContext.fetch(Transaction.fetchRequest())
            XCTAssertEqual(rows.count, 2)
            for row in rows {
                XCTAssertFalse(localizedCurrencyAmount(row.amount, currencyCode: currency, showCents: true).isEmpty)
                XCTAssertEqual(row.amount.bitPattern, original.bitPattern)
            }
        }
        let reopened = try DataController(configuration: configuration)
        try await reopened.waitUntilReady()
        let context = reopened.container.viewContext
        XCTAssertTrue(try context.fetch(Transaction.fetchRequest()).allSatisfy { $0.amount.bitPattern == original.bitPattern })
        XCTAssertEqual(try context.fetch(TemplateTransaction.fetchRequest()).first?.amount.bitPattern, original.bitPattern)
        XCTAssertEqual(try context.fetch(Budget.fetchRequest()).first?.amount.bitPattern, original.bitPattern)
        XCTAssertEqual(try LedgerMaintenance.currentMainBudget(in: context)?.amount.bitPattern, original.bitPattern)
    }

    @MainActor
    func testCustomMonthQueryAndBinsEndAtPreferredDayNotClampedDay() async throws {
        let controller = try DataController(configuration: .inMemory)
        for (day, amount) in [(28, 1.0), (30, 2), (31, 4)] {
            try await controller.saveTransaction(TransactionInput(category: nil, note: "march", income: false, amount: amount, date: date(2025, 3, day)))
        }
        let start = date(2025, 2, 28)
        let now = date(2025, 4, 1)
        let query = controller.fetchRequestForInsights(type: 2, date: start, income: false, now: now, calendar: utc, firstDayOfMonth: 31)
        XCTAssertEqual(try controller.container.viewContext.fetch(query).reduce(0) { $0 + $1.amount }, 3)
        let insights = controller.getInsights(type: 2, date: start, income: false, now: now, calendar: utc, firstDayOfMonth: 31)
        XCTAssertEqual(insights.amount, 3)
        XCTAssertEqual(insights.dates.count, 31)
        XCTAssertEqual(insights.dates.last, date(2025, 3, 30))
        XCTAssertEqual(insights.average, 3.0 / 31)
        XCTAssertEqual(LedgerCalendar.monthlyScheduleAnchor(day: 31, onOrBefore: date(2025, 2, 28), calendar: utc), date(2025, 1, 31))
    }

    func testHugeGraphValuesAndPercentagesNeverTrapOrPretendToBeZero() {
        for amount in [3_000_000_000.0, 1e20, Double.greatestFiniteMagnitude] {
            let maximum = NumericSafety.graphMaximum(amount)
            XCTAssertTrue(maximum.isFinite)
            XCTAssertGreaterThanOrEqual(maximum, amount)
            XCTAssertTrue(getBarHeight(point: amount, maxi: maximum).isFinite)
            XCTAssertGreaterThan(getBarHeight(point: amount, maxi: maximum), 0)
            XCTAssertFalse(BudgetMath.percentageText(spent: amount, budgetAmount: 1).hasPrefix("0"))
            XCTAssertFalse(getMaxText(maxi: maximum).isEmpty)
            XCTAssertFalse(getAverageText(average: amount).isEmpty)
        }
        XCTAssertEqual(BudgetMath.gaugeRatio(spent: .greatestFiniteMagnitude, budgetAmount: .leastNonzeroMagnitude), 1)
        XCTAssertEqual(BudgetMath.percentageText(spent: .greatestFiniteMagnitude, budgetAmount: .leastNonzeroMagnitude), ">999%")
        XCTAssertEqual(getBarHeight(point: 10, maxi: 0), 0)
        XCTAssertTrue(getOffset(maxi: 0, average: .infinity).isFinite)
        XCTAssertEqual(localizedCurrencyAmount(.infinity, currencyCode: "USD", showCents: true), String(localized: "Amount unavailable"))
        XCTAssertEqual(getAverageText(average: .nan), "—")
        XCTAssertTrue(NumericSafety.difference(.infinity, 1).isNaN)
    }

    @MainActor
    func testBudgetAggregateOverflowIsUnavailableWithoutModifyingFiniteTransactions() async throws {
        let controller = try DataController(configuration: .inMemory)
        let category = try await controller.saveCategory(CategoryInput(name: "Food", emoji: "🍎", colour: "#123456", income: false))
        let now = date(2026, 3, 3, 12)
        try await controller.saveBudget(category: category, amount: 100, startDate: date(2026, 3, 1), type: 3)
        try await controller.upsertMainBudget(amount: 100, startDate: date(2026, 3, 1), type: 3)
        for _ in 0..<2 { try await controller.saveTransaction(TransactionInput(category: category, note: "large", income: false, amount: .greatestFiniteMagnitude, date: now)) }
        let budget = try XCTUnwrap(controller.container.viewContext.fetch(Budget.fetchRequest()).first)
        let categorySnapshot = try await controller.budgetSnapshot(identifier: budget.id!.uuidString, now: now, calendar: utc)
        let mainSnapshot = try await controller.mainBudgetSnapshot(now: now, calendar: utc)
        XCTAssertNil(categorySnapshot)
        XCTAssertNil(mainSnapshot)
        XCTAssertEqual(try controller.container.viewContext.count(for: Transaction.fetchRequest()), 2)
        XCTAssertTrue(try controller.container.viewContext.fetch(Transaction.fetchRequest()).allSatisfy { $0.amount == .greatestFiniteMagnitude })
    }

    @MainActor
    func testInvalidRecurringMoneyIsRetainedAndQuarantinedIdempotently() async throws {
        for invalid in [Double.infinity, .nan, -1] {
            let controller = try DataController(configuration: .inMemory)
            try await controller.waitUntilReady()
            let context = controller.container.viewContext
            let seed = Transaction(context: context)
            seed.id = UUID(); seed.date = date(2099, 1, 1); seed.day = seed.date
            seed.income = false; seed.amount = 8; seed.recurringType = 1; seed.recurringCoefficient = 1
            let series = try LedgerMaintenance.attachSeries(to: seed, timeZone: utc.timeZone, in: context)
            series.amount = invalid
            try context.save()
            XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 2)), 0)
            XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 1)
            XCTAssertNotNil(series.stoppedAt)
            XCTAssertNil(series.nextDate)
            XCTAssertEqual(series.amount.bitPattern, invalid.bitPattern)
            try context.save()
            XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 3)), 0)
            XCTAssertFalse(context.hasChanges)
            XCTAssertFalse(try LedgerMaintenance.hasDueWork(in: context, now: date(2099, 1, 3)))
        }
    }

    @MainActor
    func testExtremeFiniteRecurringDateIsQuarantinedWithoutCalendarArithmetic() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let seed = Transaction(context: context)
        seed.id = UUID(); seed.date = date(2099, 1, 1); seed.day = seed.date
        seed.income = false; seed.amount = 8; seed.recurringType = 1; seed.recurringCoefficient = 1
        let series = try LedgerMaintenance.attachSeries(to: seed, timeZone: utc.timeZone, in: context)
        series.nextDate = Date(timeIntervalSince1970: .greatestFiniteMagnitude)
        try context.save()
        XCTAssertTrue(try LedgerMaintenance.hasDueWork(in: context, now: date(2099, 1, 2)))
        XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 2)), 0)
        XCTAssertNil(series.nextDate)
        XCTAssertNotNil(series.stoppedAt)
        try context.save()
        XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 3)), 0)
        XCTAssertFalse(context.hasChanges)
        XCTAssertFalse(try LedgerMaintenance.hasDueWork(in: context, now: date(2099, 1, 3)))
    }

    @MainActor
    func testRecurringMoneyCopyPreservesEveryStoredBit() async throws {
        let controller = try DataController(configuration: .inMemory)
        let original = 123.456789012345
        try await controller.saveTransaction(TransactionInput(category: nil, note: "future", income: false, amount: original, date: date(2099, 1, 1), repeatType: 1))
        let context = controller.container.viewContext
        XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 2)), 1)
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 2)
        XCTAssertTrue(try context.fetch(Transaction.fetchRequest()).allSatisfy { $0.amount.bitPattern == original.bitPattern })
    }

    @MainActor
    func testCurrentBudgetReadsDoNotIncludePreviousPeriodsOrMutateAnchor() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let category = Category(context: context)
        category.id = UUID()
        let budget = Budget(context: context)
        budget.id = UUID(); budget.category = category; budget.type = 1; budget.amount = 100
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = calendar.date(byAdding: .day, value: -5000, to: calendar.startOfDay(for: now))!
        budget.startDate = anchor
        let old = Transaction(context: context)
        old.id = UUID(); old.category = category; old.amount = 9; old.date = anchor; old.income = false
        let recent = Transaction(context: context)
        recent.id = UUID(); recent.category = category; recent.amount = 3; recent.date = now.addingTimeInterval(-1); recent.income = false
        try context.save()
        let rows = try context.fetch(controller.fetchRequestForBudgetTransactions(budget: budget, now: now, calendar: calendar))
        XCTAssertEqual(rows.map(\.amount), [3])
        let snapshot = try await controller.budgetSnapshot(identifier: budget.id!.uuidString, now: now, calendar: calendar)
        XCTAssertEqual(snapshot?.spent, 3)
        XCTAssertEqual(snapshot?.startDate, calendar.startOfDay(for: now))
        XCTAssertEqual(budget.startDate, anchor)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testInvalidBudgetAmountAndTypeAreUnavailableAndRetained() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let category = Category(context: context); category.id = UUID()
        let budget = Budget(context: context)
        budget.id = UUID(); budget.category = category; budget.startDate = .now.addingTimeInterval(-100)
        let transaction = Transaction(context: context)
        transaction.id = UUID(); transaction.category = category; transaction.amount = 2; transaction.date = .now.addingTimeInterval(-1); transaction.income = false
        for (type, amount) in [(Int16(0), 100.0), (Int16(1), 0.0), (Int16(1), -1.0)] {
            budget.type = type; budget.amount = amount
            try context.save()
            XCTAssertTrue(try context.fetch(controller.fetchRequestForBudgetTransactions(budget: budget)).isEmpty)
            let snapshot = try await controller.budgetSnapshot(identifier: budget.id!.uuidString)
            XCTAssertNil(snapshot)
            XCTAssertEqual(try context.count(for: Budget.fetchRequest()), 1)
        }
    }

    func testProgressIsBoundedBeforeAndAfterWindow() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(100)
        XCTAssertEqual(BudgetWindow.progress(startDate: start, endDate: end, now: start.addingTimeInterval(-1), calendar: .current), 0)
        XCTAssertEqual(BudgetWindow.progress(startDate: start, endDate: end, now: end.addingTimeInterval(100), calendar: .current), 1)
    }
}
