import CoreData
import LittleSaverCore
import XCTest
@testable import LittleSaver

final class CSVTransferTests: XCTestCase {
    @MainActor
    private func diskController() async throws -> DataController {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let controller = try DataController(configuration: .init(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: directory.appendingPathComponent("transfer.sqlite"), reloadWidgetsAfterSave: false))
        try await controller.waitUntilReady()
        // Do not detach/unlink SQLite stores that may still be owned by async callbacks.
        return controller
    }

    @MainActor
    func testLegacySampleAndExplicitFourColumnMappingRemainSupported() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LittleSaver/sample.csv")
        let sample = try CSVDocumentParser.parse(String(contentsOf: path))
        let mapping = try XCTUnwrap(CSVImportMapping.recognizedHeader(sample[0]))
        XCTAssertTrue(mapping.isCanonical)
        for name in Set(sample.dropFirst().map { $0[3] }) {
            let category = Category(context: controller.container.viewContext); category.id = UUID(); category.name = name; category.income = false
        }
        try controller.container.viewContext.save()
        let count = try await CSVTransactionImporter.importRows(Array(sample.dropFirst()), mapping: mapping, dateFormat: "", categoriesByName: [:], into: controller)
        XCTAssertEqual(count, sample.count - 1)
        let legacy = try XCTUnwrap(CSVImportMapping.recognizedHeader(["Category", "Note", "Date", "Amount"]))
        XCTAssertFalse(legacy.isCanonical, "The App must retain manual linking for recognized four-column headers")
        let income = try await controller.saveCategory(CategoryInput(name: "Salary", emoji: "💰", colour: "#123456", income: true))
        _ = try await CSVTransactionImporter.importRows([["Pay", "", "2026-01-01", "0.123456789"]], mapping: legacy, dateFormat: "yyyy-MM-dd", categoriesByName: ["Pay": income], into: controller)
        let rows = try controller.container.viewContext.fetch(Transaction.fetchRequest())
        XCTAssertTrue(rows.contains { $0.note == "" && $0.income && $0.amount == 0.123456789 })
        XCTAssertNil(try CSVImportMapping.recognizedHeader(["Category2026", "some text", "2026-01-01", "1"]))
        let ragged = try CSVImportTable(rows: [["a", "b", "c", "d"], ["1"], ["2", "3", "4", "5"]])
        XCTAssertEqual(ragged.columns[1], ["b", "", "3"])
    }

    @MainActor
    func testAmbiguousCategoriesAndUnrepresentableExportFieldsFailExplicitly() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let first = Category(context: context); first.id = UUID(); first.name = "Same"; first.income = false
        let second = Category(context: context); second.id = UUID(); second.name = "Same"; second.income = false
        try context.save()
        let mapping = try XCTUnwrap(CSVImportMapping.recognizedHeader(["Date", "Note", "Amount", "Category", "Type"]))
        do { _ = try await CSVTransactionImporter.importRows([["2001-01-01 00:00:00 +0000", "raw", "1", "Same", "Expense"]], mapping: mapping, dateFormat: "", categoriesByName: [:], into: controller); XCTFail("Ambiguous category must fail") } catch { XCTAssertEqual(error as? CSVImportError, .ambiguousCategory(row: 1, value: "Same")) }
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 0)
        let row = Transaction(context: context); row.id = UUID(); row.date = Date(timeIntervalSinceReferenceDate: 1); row.note = "raw"; row.amount = 1; row.income = false; row.category = first
        try context.save()
        do { _ = try await controller.csvExportText(); XCTFail("Ambiguous export must fail") } catch {}
        second.income = true
        for field in ["Category", "Note", "Date", "Amount", "Type"] {
            first.name = "Same"; first.income = false; row.income = false; row.note = "raw"; row.date = Date(timeIntervalSinceReferenceDate: 1); row.amount = 1
            switch field {
            case "Category": row.income = true // Must not silently match the other same-name income category.
            case "Note": row.note = nil
            case "Date": row.date = nil
            case "Amount": row.amount = .nan
            default: row.setValue(nil, forKey: "income")
            }
            try context.save()
            do { _ = try await controller.csvExportText(); XCTFail("Unsupported raw \(field) must fail") } catch { XCTAssertEqual(error as? CSVImportError, .invalidExportField(row: 1, field: field)) }
        }
        row.income = false; row.amount = 1; row.date = Date(timeIntervalSinceReferenceDate: 1); row.note = "raw"
        for name in ["", " \t "] {
            first.name = name; try context.save()
            do { _ = try await controller.csvExportText(); XCTFail("Blank real category must not become nil") } catch {}
        }
    }

    func testSecurityScopedFileReadReleasesAccessOnDecodeAndReadFailure() async throws {
        let probe = CSVAccessProbe()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for decodeFailure in [true, false] {
            do {
                _ = try await CSVImportFile.read(url, acquire: { _ in probe.acquire(); return true }, release: { _ in probe.release() }, load: { _ in
                    probe.recordRead()
                    if decodeFailure { return Data([0xff]) }
                    throw CocoaError(.fileReadUnknown)
                })
                XCTFail("Expected read/decode error")
            } catch {}
        }
        XCTAssertEqual(probe.counts.0, 2); XCTAssertEqual(probe.counts.1, 2)
        XCTAssertFalse(probe.usedMain)
        do { _ = try await CSVImportFile.read(url, acquire: { _ in false }, release: { _ in XCTFail("No scope was acquired") }); XCTFail("Expected denied-access error") } catch {}
        let text = try await CSVImportFile.read(url, acquire: { _ in probe.acquire(); return true }, release: { _ in probe.release() }, load: { _ in Data("a,\"b\r\nc\"".utf8) })
        XCTAssertEqual(text, "a,\"b\r\nc\"")
        XCTAssertEqual(probe.counts.0, 3); XCTAssertEqual(probe.counts.1, 3)
    }

    func testAppWiringRequiresCanonicalConfirmationAndManualLinkingWithoutHeaderGuessing() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: app.appendingPathComponent("LittleSaver/Views/ImportDataView.swift"))
        XCTAssertTrue(source.contains("let isCanonical = declared?.isCanonical == true"))
        XCTAssertTrue(source.contains("Button(\"Import Data\")"))
        XCTAssertTrue(source.contains("CSVImportPreviewSelection(rows: values, skipsHeader: declared != nil)"))
        XCTAssertFalse(source.contains("first.joined().containsDigits"))
        XCTAssertFalse(source.contains("guard data.containsDigits"))
        XCTAssertFalse(source.contains("catch {}"))
        let settings = try String(contentsOf: app.appendingPathComponent("LittleSaver/Views/Settings/SettingsView.swift"))
        XCTAssertTrue(settings.contains("ActivityViewController(activityItems: [url])"))
        XCTAssertTrue(settings.contains(".disabled(exportPreparation.isPreparing)"))
        XCTAssertFalse(settings.contains("export.csv"))
    }
    func testFailedHeaderSelectionRetainsTheOriginalPreviewAndSelection() throws {
        let row = ["Food", "Lunch", "2026-03-10", "1"]
        var selection = try CSVImportPreviewSelection(rows: [row], skipsHeader: false)
        XCTAssertThrowsError(try selection.setSkippingHeader(true))
        XCTAssertFalse(selection.skipsHeader)
        XCTAssertEqual(selection.table.rows, [row])
        XCTAssertEqual(selection.table.columns, [["Food"], ["Lunch"], ["2026-03-10"], ["1"]])
    }

    func testPairedCodecRoundTripsUnicodeWhitespaceQuotesAndEmptyRows() throws {
        let rows = [["Date", "Note"], ["", ""], [" \t ", "one\r\ntwo\rthree\nfour"], [",\u{301}", "\"\u{301}🙂"], ["尾", ""], ["\u{FEFF}value", "\\literal"]]
        XCTAssertEqual(try CSVDocumentParser.parse(CSVDocumentParser.encode(rows)), rows)
        XCTAssertEqual(try CSVDocumentParser.parse(CSVDocumentParser.encode([])), [])
        XCTAssertThrowsError(try CSVDocumentParser.encode([[]]))
        XCTAssertEqual(try CSVDocumentParser.parse("\u{FEFF}\"Date\",Note,Amount,Category,Type\r\n").first, ["Date", "Note", "Amount", "Category", "Type"])
        let literal = "\u{FEFF}literal"
        let decoded = try CSVDocumentParser.parse(CSVDocumentParser.encode([[literal]]))
        XCTAssertEqual(decoded.first?.first.map { Array($0.utf8) }, Array(literal.utf8))
    }

    @MainActor
    func testCanonicalTransferPreservesExactDatesMoneyNotesTypeAndNilCategory() async throws {
        let source = try DataController(configuration: .inMemory)
        let target = try await diskController()
        try await source.waitUntilReady(); try await target.waitUntilReady()
        let context = source.container.viewContext
        let name = " Food, \"餐\" "
        var categories: [LittleSaverCore.Category] = []
        for controller in [source, target] {
            for income in [false, true] {
                let category = Category(context: controller.container.viewContext)
                category.id = UUID(); category.name = name; category.income = income
                if controller === source { categories.append(category) }
            }
            try controller.container.viewContext.save()
        }
        let seconds = [0.123456789012345, -Double.leastNonzeroMagnitude, Double.leastNonzeroMagnitude, 1_234_567_890.1234567, Date.distantPast.timeIntervalSinceReferenceDate, Date.distantFuture.timeIntervalSinceReferenceDate]
        let amounts = [Double.leastNonzeroMagnitude, -0.12345678901234568, Double.greatestFiniteMagnitude, 1e-200, -1e20, -0.0]
        var expected: [String: (Double, Double, Bool, String?)] = [:]
        for index in seconds.indices {
            let row = Transaction(context: context); row.id = UUID()
            row.note = index == 0 ? "" : " \(index),\"🙂\"\r\n\r\n \t"
            row.date = Date(timeIntervalSinceReferenceDate: seconds[index]); row.amount = amounts[index]
            row.income = index % 2 == 1; row.category = index % 3 == 2 ? nil : categories[index % 2]
            expected[row.note!] = (seconds[index], amounts[index] == 0 ? 0 : amounts[index], row.income, row.category?.name)
        }
        try context.save()
        let originalIDs = Set(try context.fetch(Transaction.fetchRequest()).compactMap(\.id))
        let text = try await source.csvExportText()
        let table = try CSVDocumentParser.parse(text)
        XCTAssertEqual(table.first, ["Date", "Note", "Amount", "Category", "Type", "DateReferenceSeconds"])
        let mapping = try XCTUnwrap(CSVImportMapping.recognizedHeader(table[0]))
        let count = try await CSVTransactionImporter.importRows(Array(table.dropFirst()), mapping: mapping, dateFormat: "ignored", categoriesByName: [:], into: target)
        XCTAssertEqual(count, seconds.count)
        let imported = try target.container.viewContext.fetch(Transaction.fetchRequest())
        XCTAssertTrue(originalIDs.isDisjoint(with: Set(imported.compactMap(\.id))))
        for row in imported {
            let value = try XCTUnwrap(expected[row.note ?? "missing"])
            XCTAssertEqual(row.date?.timeIntervalSinceReferenceDate, value.0)
            XCTAssertEqual(row.amount, value.1)
            XCTAssertEqual(row.income, value.2)
            XCTAssertEqual(row.category?.name, value.3)
            XCTAssertEqual(row.category?.income, value.3 == nil ? nil : value.2)
            XCTAssertEqual(row.recurringType, 0)
        }
        let store = try XCTUnwrap(target.container.persistentStoreCoordinator.persistentStores.first?.url)
        let reopened = try DataController(configuration: .init(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: store, reloadWidgetsAfterSave: false, transactionAuthor: "independent-transfer-reader"))
        try await reopened.waitUntilReady()
        let persisted = try reopened.container.viewContext.fetch(Transaction.fetchRequest())
        XCTAssertEqual(persisted.count, expected.count)
        for row in persisted {
            let value = try XCTUnwrap(expected[row.note ?? "missing"])
            XCTAssertEqual(row.date?.timeIntervalSinceReferenceDate, value.0)
            XCTAssertEqual(row.amount, value.1)
        }
    }

    @MainActor
    func testInvalidMappingsRaggedRowsTypeDateAndCategoriesAreAtomic() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let header = ["Date", "Note", "Amount", "Category", "Type", "DateReferenceSeconds"]
        let canonical = try XCTUnwrap(CSVImportMapping.recognizedHeader(header))
        let good = ["2001-01-01 00:00:00 +0000", "exact", "1.23456789", "", "Expense", "0.125"]
        for (column, badValue) in [(0,"nonsense"), (2,"nan"), (2,"inf"), (3,"Unknown"), (4,"Refund"), (5,"86400"), (5,"1e300"), (5,"nan"), (5,"inf")] {
            var bad = good; bad[column] = badValue
            do { _ = try await CSVTransactionImporter.importRows([good, bad], mapping: canonical, dateFormat: "", categoriesByName: [:], into: controller); XCTFail("Expected row validation failure") } catch {}
            XCTAssertEqual(try controller.container.viewContext.count(for: Transaction.fetchRequest()), 0)
        }
        for mapping in [CSVImportMapping(categoryColumn: -1, noteColumn: 1, dateColumn: 2, amountColumn: 3), CSVImportMapping(categoryColumn: 0, noteColumn: 0, dateColumn: 2, amountColumn: 3)] {
            do { _ = try await CSVTransactionImporter.importRows([good], mapping: mapping, dateFormat: "", categoriesByName: [:], into: controller); XCTFail("Expected mapping failure") } catch { XCTAssertEqual(error as? CSVImportError, .invalidMapping) }
        }
        do { _ = try await CSVTransactionImporter.importRows([good, [""]], mapping: canonical, dateFormat: "", categoriesByName: [:], into: controller); XCTFail("Expected ragged-row failure") } catch { XCTAssertEqual(error as? CSVImportError, .missingColumn(row: 2)) }
        controller.commandSave = { _ in throw CocoaError(.fileWriteUnknown) }
        let stamp = controller.analyticsStamp
        do { _ = try await CSVTransactionImporter.importRows([good], mapping: canonical, dateFormat: "", categoriesByName: [:], into: controller); XCTFail("Expected commit failure") } catch {}
        XCTAssertEqual(try controller.container.viewContext.count(for: Transaction.fetchRequest()), 0)
        XCTAssertEqual(controller.analyticsStamp, stamp)
    }

    @MainActor
    func testCanonicalISODatesRequireRealDatesAndCompleteInputAtomically() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let normalized = try XCTUnwrap(formatter.date(from: "2026-03-02 12:34:56 +0000"))
        let march = try XCTUnwrap(formatter.date(from: "2026-03-10 12:34:56 +0000"))
        for exact in [false, true] {
            let header = ["Date", "Note", "Amount", "Category", "Type"] + (exact ? ["DateReferenceSeconds"] : [])
            let mapping = try XCTUnwrap(CSVImportMapping.recognizedHeader(header))
            let good = ["2026-03-10T20:34:56+08:00", "good", "-0.123456789", "", "Expense"] + (exact ? [String(march.timeIntervalSinceReferenceDate)] : [])
            for (invalid, normalizedDate) in [("2026-02-30T12:34:56Z", normalized), ("2026-03-10T12:34:56Zjunk", march), ("2026-13-10T12:34:56Z", march)] {
                let bad = [invalid, "bad", "1", "", "Expense"] + (exact ? [String(normalizedDate.timeIntervalSinceReferenceDate)] : [])
                let stamp = controller.analyticsStamp
                do {
                    _ = try await CSVTransactionImporter.importRows([good, bad], mapping: mapping, dateFormat: "", categoriesByName: [:], into: controller)
                    XCTFail("Invalid ISO timestamp must reject the whole import: \(invalid)")
                } catch { XCTAssertEqual(error as? CSVImportError, .invalidDate(row: 2, value: invalid)) }
                XCTAssertEqual(try controller.container.viewContext.count(for: Transaction.fetchRequest()), 0)
                XCTAssertEqual(controller.analyticsStamp, stamp)
            }
        }
        let mapping = try XCTUnwrap(CSVImportMapping.recognizedHeader(["Date", "Note", "Amount", "Category", "Type"]))
        let valid = ["2026-03-10T12:34:56Z", "2026-03-10T20:34:56+08:00", "2026-03-10T07:04:56-05:30", "2024-02-29T12:34:56Z"]
        _ = try await CSVTransactionImporter.importRows(valid.map { [$0, $0, "-0.123456789", "", "Expense"] }, mapping: mapping, dateFormat: "", categoriesByName: [:], into: controller)
        let imported = try controller.container.viewContext.fetch(Transaction.fetchRequest())
        XCTAssertEqual(imported.count, 4)
        XCTAssertTrue(imported.allSatisfy { $0.amount == -0.123456789 })
        XCTAssertTrue(imported.filter { $0.note != valid.last }.allSatisfy { $0.date == march })
    }

    @MainActor
    func testExportPreparationCannotShareAStaleFileAfterReadOrWriteFailure() async throws {
        let model = CSVExportPreparation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let first = try await CSVExportFile.prepare(directory: directory, read: { "first" })
        let second = try await CSVExportFile.prepare(directory: directory, read: { "second" })
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first), "first")
        await model.prepare { first }; XCTAssertEqual(model.url, first)
        await model.prepare { try await CSVExportFile.prepare(read: { throw CocoaError(.fileReadUnknown) }) }
        XCTAssertNil(model.url); XCTAssertNotNil(model.error); XCTAssertFalse(model.isPreparing)
        await model.prepare { try await CSVExportFile.prepare(read: { "new" }, write: { _, _ in throw CocoaError(.fileWriteUnknown) }) }
        XCTAssertNil(model.url); XCTAssertNotNil(model.error)
        var pending: CheckedContinuation<URL, Never>?
        let operation = Task { await model.prepare { await withCheckedContinuation { pending = $0 } } }
        while pending == nil { await Task.yield() }
        await model.prepare { XCTFail("Duplicate export while pending"); return first }
        pending?.resume(returning: second); await operation.value
        XCTAssertEqual(model.url, second); XCTAssertNil(model.error)
        XCTAssertTrue(Thread.isMainThread)
    }

    func testParserPreservesEmbeddedLineEndingsWithoutNormalization() throws {
        let note = " leading, \"quoted\"\r\nnext\rthen\n尾 🙂 "
        let encoded = "\" leading, \"\"quoted\"\"\r\nnext\rthen\n尾 🙂 \",tail\r\n"
        XCTAssertEqual(try CSVDocumentParser.parse(encoded), [[note, "tail"]])
    }

    func testParserPreservesEmptyRecordsAndQuotedEmptyAtEOF() throws {
        XCTAssertEqual(try CSVDocumentParser.parse("\"\""), [[""]])
        XCTAssertEqual(try CSVDocumentParser.parse("a,\r\n\r\n,,\r\n"), [["a", ""], [""], ["", "", ""]])
    }

    @MainActor
    func testManualImportRetainsRawNotesAndLegacyCategoryDirectedMoney() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let category = try await controller.saveCategory(CategoryInput(name: "Food", emoji: "🍎", colour: "#123456", income: false))
        let note = " \tcomma, quote\"\r\n尾\r "
        let rows = [["Food", note, "2026-03-10", "-0.12345678901234568"], ["Food", "", "2026-03-10", "1e-200"]]
        _ = try await CSVTransactionImporter.importRows(rows, mapping: CSVImportMapping(categoryColumn: 0, noteColumn: 1, dateColumn: 2, amountColumn: 3), dateFormat: "yyyy-MM-dd", categoriesByName: ["Food": category], into: controller, timeZone: TimeZone(secondsFromGMT: 0)!)
        let imported = try controller.container.viewContext.fetch(Transaction.fetchRequest()).sorted { $0.amount < $1.amount }
        XCTAssertEqual(imported.map(\.note), ["", note])
        XCTAssertEqual(imported.map(\.amount), [1e-200, 0.12345678901234568])
    }
}

private final class CSVAccessProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var ends = 0
    private var main = false
    var counts: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (starts, ends) }
    var usedMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
    func acquire() { lock.lock(); defer { lock.unlock() }; starts += 1; main = main || Thread.isMainThread }
    func release() { lock.lock(); defer { lock.unlock() }; ends += 1 }
    func recordRead() { lock.lock(); defer { lock.unlock() }; main = main || Thread.isMainThread }
}
