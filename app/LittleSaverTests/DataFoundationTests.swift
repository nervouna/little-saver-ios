import LittleSaverCore
import CoreData
import XCTest
@testable import LittleSaver

final class DataFoundationTests: XCTestCase {
    @MainActor
    func testSiblingReplacementOccurrencesConvergeAcrossImportOrdersAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep disk fixtures until process teardown; asynchronous history callbacks may still
        // retain a reopened coordinator after this method returns.
        let sourceID = UUID()
        let family = "legacy:\(sourceID.uuidString.lowercased())"
        let now = date(2099, 1, 3, 12)
        var snapshots: [[String: [[String: Any]]]] = []
        for identity in ["sibling-a", "sibling-b"] {
            let peer = try DataController(configuration: .inMemory)
            let context = peer.container.viewContext
            let seed = Transaction(context: context)
            seed.id = sourceID
            seed.occurrenceKey = "\(family)/0"
            seed.date = date(2099, 1, 1)
            seed.day = seed.date
            seed.recurringType = 1
            seed.recurringCoefficient = 1
            seed.amount = identity == "sibling-a" ? 10 : 20
            try LedgerMaintenance.attachSeries(to: seed, logicalID: identity, familyID: family, createdAt: now, timeZone: calendar.timeZone, in: context)
            try LedgerMaintenance.materialize(in: context, now: now)
            try context.save()
            snapshots.append(try ledgerAttributes(from: context, entities: ["RecurringSeries", "Transaction"]))
        }
        for (index, order) in [snapshots, snapshots.reversed().map { $0 }].enumerated() {
            let url = directory.appendingPathComponent("peer-\(index).sqlite")
            let configuration = DataController.Configuration(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: url, reloadWidgetsAfterSave: false)
            let merged = try DataController(configuration: configuration)
            try await merged.waitUntilReady()
            let context = merged.container.viewContext
            for snapshot in order { importLedgerAttributes(snapshot, into: context) }
            try LedgerMaintenance.reconcile(in: context)
            repeat { try LedgerMaintenance.materialize(in: context, now: now, limit: 1) }
            while try LedgerMaintenance.hasDueWork(in: context, now: now)
            XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 3)
            XCTAssertEqual(try context.fetch(Transaction.fetchRequest()).filter { $0.occurrenceIndex > 0 }.map(\.amount).sorted(), [20, 20])
            XCTAssertEqual(try context.fetch(Transaction.fetchRequest()).filter { $0.recurringType > 0 }.count, 1)
            try context.save()
            let expectedKeys = Set(try context.fetch(Transaction.fetchRequest()).compactMap(\.occurrenceKey))
            context.reset()
            for store in merged.container.persistentStoreCoordinator.persistentStores { try merged.container.persistentStoreCoordinator.remove(store) }
            let reopened = try DataController(configuration: configuration)
            try await reopened.waitUntilReady()
            XCTAssertEqual(Set(reopened.results(for: Transaction.fetchRequest()).compactMap(\.occurrenceKey)), expectedKeys)
            XCTAssertEqual(reopened.results(for: Transaction.fetchRequest()).count, 3)
        }
    }

    func testSiblingNamespaceSharesDeletionAndPreservesEditedFutureOccurrence() throws {
        let context = controller.container.viewContext
        let family = "same-family"
        let now = date(2099, 1, 4, 12)
        let seed = Transaction(context: context)
        seed.id = UUID()
        seed.occurrenceKey = "original/0"
        seed.date = date(2099, 1, 1)
        seed.day = seed.date
        seed.recurringType = 1
        seed.recurringCoefficient = 1
        let daily = try LedgerMaintenance.attachSeries(to: seed, logicalID: "a", familyID: family, createdAt: now, timeZone: calendar.timeZone, in: context)
        try LedgerMaintenance.materialize(in: context, now: now)
        let occurrences = try context.fetch(Transaction.fetchRequest()).filter { $0.occurrenceIndex > 0 }.sorted { $0.occurrenceIndex < $1.occurrenceIndex }
        let deleted = try XCTUnwrap(occurrences.first)
        let deletedKey = deleted.occurrenceKey
        try LedgerMaintenance.deleteTransaction(deleted, in: context)
        let edited = try XCTUnwrap(occurrences.dropFirst().first)
        LedgerMaintenance.markUserEdit(edited, at: now)
        edited.note = "Keep my entry even before the winning schedule is due"
        edited.amount = 99
        let editedDate = edited.date
        let category = LittleSaverCore.Category(context: context)
        category.id = UUID()
        category.name = "Manual category"
        edited.category = category
        let editedKey = edited.occurrenceKey
        let automatic = try XCTUnwrap(occurrences.last)
        let automaticKey = automatic.occurrenceKey
        seed.recurringType = 2
        let weekly = try LedgerMaintenance.attachSeries(to: seed, logicalID: "b", familyID: family, createdAt: now, timeZone: calendar.timeZone, in: context)
        XCTAssertEqual(daily.occurrenceNamespace, weekly.occurrenceNamespace)
        try LedgerMaintenance.reconcile(in: context)
        try LedgerMaintenance.materialize(in: context, now: now, limit: 1)
        XCTAssertFalse(try context.fetch(Transaction.fetchRequest()).contains { $0.occurrenceKey == automaticKey })
        XCTAssertFalse(try context.fetch(Transaction.fetchRequest()).contains { $0.occurrenceKey == deletedKey })
        XCTAssertEqual(edited.occurrenceKey, editedKey)
        XCTAssertEqual(edited.note, "Keep my entry even before the winning schedule is due")
        XCTAssertEqual(edited.amount, 99)
        XCTAssertEqual(edited.date, editedDate)
        XCTAssertEqual(edited.category, category)
        try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 20))
        XCTAssertFalse(try context.fetch(Transaction.fetchRequest()).contains { $0.occurrenceKey == deletedKey })
        XCTAssertEqual(try context.fetch(Transaction.fetchRequest()).filter { $0.occurrenceKey == editedKey }.count, 1)
        XCTAssertEqual(edited.amount, 99)
        XCTAssertEqual(edited.date, editedDate)
        XCTAssertEqual(edited.category, category)
    }

    func testStoppedSiblingWinnerNormalizesLateHistoryWithoutRevivingOrCreating() throws {
        let context = controller.container.viewContext
        let seed = Transaction(context: context)
        seed.id = UUID()
        seed.occurrenceKey = "source/0"
        seed.date = date(2099, 1, 1)
        seed.day = seed.date
        seed.recurringType = 1
        seed.recurringCoefficient = 1
        seed.amount = 10
        let now = date(2099, 1, 3, 12)
        try LedgerMaintenance.attachSeries(to: seed, logicalID: "a", familyID: "family", createdAt: now, timeZone: calendar.timeZone, in: context)
        try LedgerMaintenance.materialize(in: context, now: now)
        seed.amount = 20
        seed.recurringType = 2
        let winner = try LedgerMaintenance.attachSeries(to: seed, logicalID: "b", familyID: "family", createdAt: now, timeZone: calendar.timeZone, in: context)
        winner.stoppedAt = now
        try LedgerMaintenance.reconcile(in: context)
        repeat { try LedgerMaintenance.materialize(in: context, now: now, limit: 1) }
        while try LedgerMaintenance.hasDueWork(in: context, now: now)
        let history = try context.fetch(Transaction.fetchRequest()).filter { $0.occurrenceIndex > 0 }.sorted { $0.occurrenceIndex < $1.occurrenceIndex }
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 1)
        XCTAssertTrue(try context.fetch(Transaction.fetchRequest()).allSatisfy { $0.recurringType == 0 })
        try context.save()
        try LedgerMaintenance.materialize(in: context, now: date(2100, 1, 1))
        XCTAssertFalse(context.hasChanges)
    }

    func testInvalidSeriesQuarantineDoesNotWriteOnEveryMaintenancePass() throws {
        let context = controller.container.viewContext
        for invalidZone in [true, false] {
            let seed = Transaction(context: context)
            seed.id = UUID()
            seed.date = date(2099, 1, 1)
            seed.recurringType = 1
            seed.recurringCoefficient = 1
            let series = try LedgerMaintenance.attachSeries(to: seed, in: context)
            if invalidZone { series.timeZoneID = "Not/A-Time-Zone" }
            else { series.nextDate = nil }
        }
        try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 3))
        try context.save()
        try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 4))
        XCTAssertFalse(context.hasChanges)
        XCTAssertFalse(try LedgerMaintenance.hasDueWork(in: context, now: date(2099, 1, 4)))
    }

    func testDifferentCatchUpSourcesShareGlobalFamilyIndexAcrossImportOrders() throws {
        let sourceID = UUID()
        let family = "legacy:\(sourceID.uuidString.lowercased())"
        let now = date(2099, 1, 3, 12)
        var snapshots: [[String: [[String: Any]]]] = []
        for peerIndex in 0..<2 {
            let peer = try DataController(configuration: .inMemory)
            let context = peer.container.viewContext
            let seed = Transaction(context: context)
            seed.id = sourceID
            seed.date = date(2099, 1, 1)
            seed.day = seed.date
            seed.recurringType = 1
            seed.recurringCoefficient = 1
            seed.amount = 5
            try LedgerMaintenance.attachSeries(to: seed, timeZone: calendar.timeZone, in: context)
            if peerIndex == 1 { try LedgerMaintenance.materialize(in: context, now: date(2099, 1, 2, 12)) }
            let source = try XCTUnwrap(context.fetch(Transaction.fetchRequest()).max { $0.occurrenceIndex < $1.occurrenceIndex })
            LedgerMaintenance.markUserEdit(source, at: now)
            source.amount = peerIndex == 0 ? 10 : 20
            source.recurringType = 1
            source.recurringCoefficient = 1
            let replacement = try LedgerMaintenance.attachSeries(to: source, logicalID: peerIndex == 0 ? "a" : "b", familyID: family, createdAt: now, timeZone: calendar.timeZone, in: context)
            XCTAssertEqual(replacement.sourceIndex, Int64(peerIndex))
            try LedgerMaintenance.materialize(in: context, now: now)
            try context.save()
            snapshots.append(try ledgerAttributes(from: context, entities: ["RecurringSeries", "Transaction"]))
        }
        for order in [snapshots, snapshots.reversed().map { $0 }] {
            let merged = try DataController(configuration: .inMemory)
            let context = merged.container.viewContext
            for snapshot in order { importLedgerAttributes(snapshot, into: context) }
            try LedgerMaintenance.reconcile(in: context)
            repeat { try LedgerMaintenance.materialize(in: context, now: now, limit: 1) }
            while try LedgerMaintenance.hasDueWork(in: context, now: now)
            let rows = try context.fetch(Transaction.fetchRequest())
            XCTAssertEqual(rows.count, 3)
            XCTAssertEqual(rows.filter { $0.occurrenceIndex == 2 }.map(\.amount), [20])
            XCTAssertEqual(rows.filter { $0.occurrenceIndex == 1 }.map(\.amount), [20])
            XCTAssertEqual(Set(rows.compactMap(\.occurrenceKey)), Set((0...2).map { "\(family)/\($0)" }))
            XCTAssertEqual(rows.filter { $0.recurringType > 0 }.count, 1)
            importLedgerAttributes(snapshots[0], into: context)
            try LedgerMaintenance.reconcile(in: context)
            repeat { try LedgerMaintenance.materialize(in: context, now: now, limit: 1) }
            while try LedgerMaintenance.hasDueWork(in: context, now: now)
            XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 3)
            try context.save()
            try LedgerMaintenance.reconcile(in: context)
            try LedgerMaintenance.materialize(in: context, now: now)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testLegacyMainBudgetCandidatesNeverCrossDeleteAndVersionsProjectOne() async throws {
        let peers = try [DataController(configuration: .inMemory), DataController(configuration: .inMemory)]
        for (peerIndex, peer) in peers.enumerated() {
            let context = peer.container.viewContext
            // Two shared rows can be byte-for-byte indistinguishable in the V0 schema.
            let candidates = (0..<2).map { _ -> MainBudget in
                let budget = MainBudget(context: context)
                budget.amount = 100
                budget.startDate = date(2099, 1, 1)
                budget.type = 2
                return budget
            }
            try LedgerMaintenance.backfill(in: context)
            for (index, candidate) in candidates.enumerated() {
                candidate.deduplicationToken = (peerIndex == index) ? "a" : "z"
            }
            try LedgerMaintenance.reconcile(in: context)
            XCTAssertTrue(candidates.allSatisfy { !$0.isDeleted })
            XCTAssertEqual(try context.count(for: MainBudget.fetchRequest()), 2)
            XCTAssertEqual(try LedgerMaintenance.currentMainBudget(in: context)?.amount, 100)
            let revision = try LedgerMaintenance.upsertMainBudget(in: context, amount: peerIndex == 0 ? 200 : 300, startDate: date(2099, 1, 1), type: 2)
            revision.deduplicationToken = peerIndex == 0 ? "event-a" : "event-b"
            try context.save()
        }
        let snapshots = try peers.map { try ledgerAttributes(from: $0.container.viewContext, entities: ["MainBudget"]) }
        for order in [snapshots, snapshots.reversed().map { $0 }] {
            let merged = try DataController(configuration: .inMemory)
            let context = merged.container.viewContext
            for snapshot in order { importLedgerAttributes(snapshot, into: context) }
            try LedgerMaintenance.reconcile(in: context)
            XCTAssertEqual(try context.count(for: MainBudget.fetchRequest()), 6)
            XCTAssertEqual(try LedgerMaintenance.currentMainBudget(in: context)?.amount, 300)
            try LedgerMaintenance.deleteMainBudget(in: context)
            try context.save()
            XCTAssertNil(try LedgerMaintenance.currentMainBudget(in: context))
            let deletedSnapshot = try await merged.mainBudgetSnapshot()
            XCTAssertNil(deletedSnapshot)
            // A stale peer's legacy rows cannot resurrect a logical deletion.
            importLedgerAttributes(snapshots[0], into: context)
            try LedgerMaintenance.reconcile(in: context)
            XCTAssertNil(try LedgerMaintenance.currentMainBudget(in: context))
            try LedgerMaintenance.upsertMainBudget(in: context, amount: 400, startDate: date(2099, 1, 1), type: 2)
            XCTAssertEqual(try LedgerMaintenance.currentMainBudget(in: context)?.amount, 400)
        }
    }

    private func ledgerAttributes(from context: NSManagedObjectContext, entities: [String]) throws -> [String: [[String: Any]]] {
        try Dictionary(uniqueKeysWithValues: entities.map { entity in
            let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity)).map { object in
                Dictionary(uniqueKeysWithValues: object.entity.attributesByName.keys.compactMap { key in
                    object.value(forKey: key).map { (key, $0) }
                })
            }
            return (entity, rows)
        })
    }

    @MainActor
    func testLegacyMainBudgetV0CopiesRetainIndistinguishableRowsAfterReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Do not unlink live SQLite files retained by asynchronous history callbacks.
        let source = directory.appendingPathComponent("v0.sqlite")
        let modelURL = try XCTUnwrap(Bundle(for: DataController.self).url(forResource: AppIdentifiers.persistentModel, withExtension: "momd"))
        do {
            let legacy = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("LittleSaverDevelopmentV0.mom")))
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: legacy)
            let store = try coordinator.addPersistentStore(type: .sqlite, at: source)
            let legacyContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            legacyContext.persistentStoreCoordinator = coordinator
            for _ in 0..<2 {
                let budget = NSEntityDescription.insertNewObject(forEntityName: "MainBudget", into: legacyContext)
                budget.setValue(100, forKey: "amount")
                budget.setValue(date(2099, 1, 1), forKey: "startDate")
                budget.setValue(2, forKey: "type")
            }
            try legacyContext.save()
            legacyContext.reset()
            try coordinator.remove(store)
        }
        for peerIndex in 0..<2 {
            let url = directory.appendingPathComponent("copy-\(peerIndex).sqlite")
            try FileManager.default.copyItem(at: source, to: url)
            let configuration = DataController.Configuration(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel, storeURL: url, reloadWidgetsAfterSave: false)
            let peer = try DataController(configuration: configuration)
            try await peer.waitUntilReady()
            let context = peer.container.viewContext
            let rows = try context.fetch(MainBudget.fetchRequest())
            XCTAssertEqual(rows.count, 2)
            for (index, row) in rows.enumerated() { row.deduplicationToken = index == peerIndex ? "a" : "z" }
            try LedgerMaintenance.backfill(in: context)
            try LedgerMaintenance.reconcile(in: context)
            XCTAssertEqual(try context.count(for: MainBudget.fetchRequest()), 2)
            try LedgerMaintenance.deleteMainBudget(in: context)
            try context.save()
            context.reset()
            for loaded in peer.container.persistentStoreCoordinator.persistentStores { try peer.container.persistentStoreCoordinator.remove(loaded) }
            let reopened = try DataController(configuration: configuration)
            try await reopened.waitUntilReady()
            XCTAssertEqual(reopened.results(for: MainBudget.fetchRequest()).count, 3)
            XCTAssertNil(try LedgerMaintenance.currentMainBudget(in: reopened.container.viewContext))
            let snapshot = try await reopened.mainBudgetSnapshot()
            XCTAssertNil(snapshot)
        }
    }

    private func importLedgerAttributes(_ snapshot: [String: [[String: Any]]], into context: NSManagedObjectContext) {
        for (entity, rows) in snapshot {
            for attributes in rows {
                let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
                for (key, value) in attributes { object.setValue(value, forKey: key) }
            }
        }
    }

    @MainActor
    func testControllerDelayedLoadAndFailureDoNotBecomeEmptyQueries() async throws {
        var finishLoading: (() -> Void)?
        let delayed = try DataController(configuration: .inMemory) { container, completion in
            finishLoading = { container.loadPersistentStores(completionHandler: completion) }
        }
        XCTAssertEqual(delayed.persistentStoreState, .loading)
        do {
            try await delayed.waitUntilReady(timeout: 0.01)
            XCTFail("Unloaded controller must not report ready")
        } catch { XCTAssertEqual(error as? DataController.PersistentStoreAccessError, .loading) }
        finishLoading?()
        try await delayed.waitUntilReady()
        let values = try await delayed.categorySnapshots(income: false)
        XCTAssertTrue(values.isEmpty)

        let failed = try DataController(configuration: .inMemory) { _, completion in
            completion(NSPersistentStoreDescription(), NSError(domain: "Fixture", code: 1))
        }
        do {
            _ = try await failed.categorySnapshots(income: false)
            XCTFail("Store failure must propagate through DTO queries")
        } catch {
            guard case .failed = error as? DataController.PersistentStoreAccessError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testPersistentHistoryMergesExternalStoreChangesAndReopensWithToken() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("history.sqlite")
        let config = DataController.Configuration(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel,
                                                   storeURL: storeURL, reloadWidgetsAfterSave: false, transactionAuthor: "history-reader")
        let reader = try DataController(configuration: config)
        try await reader.waitUntilReady()
        let category = LittleSaverCore.Category(context: reader.container.viewContext)
        category.id = UUID()
        category.name = "Before"
        category.income = false
        try reader.container.viewContext.save()
        let uri = category.objectID.uriRepresentation()
        let writer = try DataController(configuration: .init(mode: .sharedLocal, modelName: AppIdentifiers.persistentModel,
                                                            storeURL: storeURL, reloadWidgetsAfterSave: false, transactionAuthor: "history-writer"))
        try await writer.waitUntilReady()
        let context = writer.container.newBackgroundContext()
        context.transactionAuthor = "external-test-writer"
        try await context.perform {
            let id = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri))
            let record = try context.existingObject(with: id) as! LittleSaverCore.Category
            record.name = "After external save"
            try context.save()
        }
        try await reader.refreshPersistentHistory()
        XCTAssertEqual(category.name, "After external save")
        XCTAssertEqual(reader.container.viewContext.transactionAuthor, "history-reader")
        let tokenURL = storeURL.appendingPathExtension("history-reader.history-token")
        let tokenData = try Data(contentsOf: tokenURL)
        XCTAssertNotNil(try NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: tokenData))

        let reopened = try DataController(configuration: config)
        try await reopened.waitUntilReady()
        let values = try await reopened.categorySnapshots(income: false)
        XCTAssertEqual(values.first?.name, "After external save")
        try await reopened.refreshPersistentHistory()
        XCTAssertEqual(try Data(contentsOf: tokenURL), tokenData)
        for controller in [reader, writer, reopened] {
            controller.container.viewContext.reset()
            for store in controller.container.persistentStoreCoordinator.persistentStores {
                try controller.container.persistentStoreCoordinator.remove(store)
            }
        }
    }

    @MainActor
    func testAppEntityQueryUsesOnlyValueSnapshotsAndPropagatesFailure() async throws {
        guard #available(iOS 16, *) else { return }
        let category = makeCategory(name: "Food")
        let id = category.id!
        let values = try await controller.categorySnapshots(income: false)
        let query = ExpenseCategoryQuery(load: { values })
        controller.container.viewContext.reset()
        let entities = try await query.entities(for: [id])
        XCTAssertEqual(entities.first?.name, "Food")
        XCTAssertTrue(Mirror(reflecting: entities[0]).children.allSatisfy { !($0.value is NSManagedObject) })
        let failure = ExpenseCategoryQuery(load: { throw DataController.PersistentStoreAccessError.failed("fixture") })
        do {
            _ = try await failure.suggestedEntities()
            XCTFail("Entity lookup must not hide load failure as an empty collection")
        } catch { XCTAssertEqual(error as? DataController.PersistentStoreAccessError, .failed("fixture")) }
    }

    func testConcurrencyDebugIsActuallyEnabledInTestProcess() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-com.apple.CoreData.ConcurrencyDebug"), index + 1 < arguments.count else {
            return XCTFail("Test process did not receive Core Data concurrency checking")
        }
        XCTAssertEqual(arguments[index + 1], "1")
    }
    func testReadinessWaitsForDelayedStoreAndReportsFailure() async throws {
        let gate = PersistenceReadiness()
        XCTAssertEqual(gate.state, .loading)
        do {
            try await gate.wait(timeout: 0.01)
            XCTFail("Loading must not become an empty result")
        } catch { XCTAssertEqual(error as? DataController.PersistentStoreAccessError, .loading) }
        gate.resolve(.failed("fixture load failure"))
        do {
            try await gate.wait()
            XCTFail("Load failure must propagate")
        } catch { XCTAssertEqual(error as? DataController.PersistentStoreAccessError, .failed("fixture load failure")) }
        let loaded = PersistenceReadiness()
        Task { loaded.resolve(.loaded) }
        try await loaded.wait()
    }

    @MainActor
    func testBackgroundSnapshotsAreValuesAndBudgetIdentityAcceptsLegacyURI() async throws {
        let category = makeCategory(name: "Food")
        let budget = Budget(context: controller.container.viewContext)
        budget.id = UUID()
        budget.category = category
        budget.startDate = Date()
        budget.type = 2
        budget.amount = 100
        controller.save()
        let uuid = budget.id!.uuidString
        let legacy = budget.objectID.uriRepresentation().absoluteString
        let snapshots = try await controller.categorySnapshots(income: false)
        XCTAssertEqual(snapshots.first?.name, "Food")
        let byUUID = try await controller.budgetSnapshot(identifier: uuid)
        let byURI = try await controller.budgetSnapshot(identifier: legacy)
        XCTAssertEqual(byUUID?.id, byURI?.id)
        XCTAssertEqual(byUUID?.id?.uuidString, uuid)
        func requireSendable<T: Sendable>(_: T) {}
        requireSendable(snapshots)
        requireSendable(byUUID)
        let isPrivate = try await controller.performBackgroundRead { $0.concurrencyType == .privateQueueConcurrencyType }
        XCTAssertTrue(isPrivate)
        let isOffMainThread = try await controller.performBackgroundRead { _ in !Thread.isMainThread }
        XCTAssertTrue(isOffMainThread)
    }

    func testWidgetUnavailableStatesRetrySoonerThanLoadedOrEmpty() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ExtensionReadStatus.loading.nextRefresh(after: now), now.addingTimeInterval(60))
        XCTAssertEqual(ExtensionReadStatus.failed("offline").nextRefresh(after: now), now.addingTimeInterval(60))
        XCTAssertEqual(ExtensionReadStatus.empty.nextRefresh(after: now), now.addingTimeInterval(900))
        XCTAssertEqual(ExtensionReadStatus.loaded.nextRefresh(after: now), now.addingTimeInterval(900))
    }

    @MainActor
    func testBudgetReadSnapshotsDoNotPublishNonFiniteAmounts() async throws {
        let category = makeCategory(name: "Food")
        let budget = Budget(context: controller.container.viewContext)
        budget.id = UUID()
        budget.category = category
        budget.startDate = Date()
        budget.type = 2
        budget.amount = .infinity
        let overall = MainBudget(context: controller.container.viewContext)
        overall.startDate = Date()
        overall.type = 2
        overall.amount = .infinity
        controller.save()
        let id = budget.id!.uuidString
        let categoryValue = try await controller.budgetSnapshot(identifier: id)
        let overallValue = try await controller.mainBudgetSnapshot()
        XCTAssertNil(categoryValue)
        XCTAssertNil(overallValue)
    }
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

    func testPersistenceModelHasOneFrameworkOwnerAndAdditiveVersions() throws {
        let bundle = Bundle(for: DataController.self)
        XCTAssertEqual(bundle.bundleIdentifier, "io.damao.littlesaver.core")
        let modelURL = try XCTUnwrap(bundle.url(forResource: AppIdentifiers.persistentModel, withExtension: "momd"))
        let legacy = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("LittleSaverDevelopmentV0.mom")))
        let current = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL.appendingPathComponent("LittleSaverV1.mom")))
        XCTAssertEqual(legacy.entityVersionHashesByName.mapValues { $0.base64EncodedString() }, [
            "Budget": "WWR9t6eXuyTBe1sTIZYn971Ajs5EBsBPJqyS0Imrc14=",
            "Category": "iEYH+1oF+usWYqsWUi6jzCk+yPnastVVSGUkPv0ALPk=",
            "MainBudget": "GQp/wtPoIWJIEad863g+pW/zd3/zPwPCn/RJvWH7NU8=",
            "TemplateTransaction": "swPZX6iFeiwAaoF8ioMjGCjZFIJvoNHgiBs4wx7cfd4=",
            "Transaction": "k3wKEeiDduXxONUNGYqhYCBTb+TXZm0IJNCpuF2KbQw="
        ])
        XCTAssertEqual(Set(legacy.entitiesByName.keys), Set(["Budget", "Category", "MainBudget", "TemplateTransaction", "Transaction"]))
        XCTAssertNotEqual(legacy.entityVersionHashesByName, current.entityVersionHashesByName)
        XCTAssertNotNil(current.entitiesByName["RecurringSeries"])
        for (name, entity) in legacy.entitiesByName {
            for (property, description) in entity.propertiesByName {
                XCTAssertEqual(description.versionHash, current.entitiesByName[name]?.propertiesByName[property]?.versionHash)
            }
        }
        XCTAssertEqual(current.entityVersionHashesByName, controller.container.managedObjectModel.entityVersionHashesByName)
    }

    func testRecurringBackfillAndBoundedMaterializationAreIdempotent() throws {
        let context = controller.container.viewContext
        let seed = Transaction(context: context)
        seed.id = UUID()
        seed.date = date(2026, 1, 1)
        seed.day = seed.date
        seed.recurringType = 1
        seed.recurringCoefficient = 1
        seed.amount = 12
        try LedgerMaintenance.backfill(in: context)
        try LedgerMaintenance.backfill(in: context)
        XCTAssertEqual(try context.count(for: RecurringSeries.fetchRequest()), 1)
        XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2026, 1, 5), limit: 2), 2)
        XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2026, 1, 5), limit: 2), 2)
        XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2026, 1, 5), limit: 2), 0)
        try LedgerMaintenance.reconcile(in: context)
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 5)
        XCTAssertEqual(Set(try context.fetch(Transaction.fetchRequest()).compactMap(\.occurrenceKey)).count, 5)
        try context.save()
        try LedgerMaintenance.backfill(in: context)
        try LedgerMaintenance.reconcile(in: context)
        try LedgerMaintenance.materialize(in: context, now: date(2026, 1, 5))
        XCTAssertFalse(context.hasChanges)
    }

    func testIndependentPeersConvergeOccurrenceAndSeriesByLogicalIdentity() throws {
        let seriesID = "legacy:\(UUID().uuidString.lowercased())"
        for token in ["peer-b", "peer-a"] {
            let peer = controller.container.newBackgroundContext()
            try peer.performAndWait {
                let seed = Transaction(context: peer)
                seed.id = UUID()
                seed.date = date(2026, 1, 1)
                seed.day = seed.date
                seed.recurringType = 1
                seed.recurringCoefficient = 1
                let series = try LedgerMaintenance.attachSeries(to: seed, logicalID: seriesID, in: peer)
                series.deduplicationToken = token
                // Both peers independently create the same occurrence before seeing the other.
                let occurrence = Transaction(context: peer)
                occurrence.id = UUID()
                occurrence.seriesID = seriesID
                occurrence.occurrenceKey = LedgerMaintenance.occurrenceKey(seriesID: seriesID, index: 1)
                occurrence.deduplicationToken = token
                occurrence.date = date(2026, 1, 2)
                try peer.save()
            }
        }
        let context = controller.container.viewContext
        try LedgerMaintenance.backfill(in: context)
        try LedgerMaintenance.reconcile(in: context)
        try context.save()
        XCTAssertEqual(try context.fetch(RecurringSeries.fetchRequest()).filter { $0.stoppedAt == nil }.count, 1)
        let request = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "occurrenceKey == %@", LedgerMaintenance.occurrenceKey(seriesID: seriesID, index: 1))
        XCTAssertEqual(try context.fetch(request).map(\.deduplicationToken), ["peer-a"])
        try LedgerMaintenance.reconcile(in: context)
        XCTAssertEqual(try context.count(for: request), 1)
    }

    func testInvalidRecurringScheduleStopsAndMainBudgetConverges() throws {
        let context = controller.container.viewContext
        let seed = Transaction(context: context)
        seed.id = UUID()
        seed.date = date(2026, 1, 1)
        seed.recurringType = 1
        seed.recurringCoefficient = 0
        try LedgerMaintenance.backfill(in: context)
        XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2026, 2, 1), limit: 10), 0)
        XCTAssertNotNil(try context.fetch(RecurringSeries.fetchRequest()).first?.stoppedAt)
        XCTAssertThrowsError(try LedgerMaintenance.materialize(in: context, now: Date(timeIntervalSince1970: .infinity)))
        XCTAssertThrowsError(try LedgerMaintenance.hasDueWork(in: context, now: Date(timeIntervalSince1970: .nan)))
        for token in ["b", "a"] {
            let budget = MainBudget(context: context)
            budget.singletonKey = LedgerMaintenance.mainBudgetKey
            budget.deduplicationToken = token
            budget.amount = token == "a" ? 200 : 300
        }
        try LedgerMaintenance.reconcile(in: context)
        XCTAssertEqual(try context.count(for: MainBudget.fetchRequest()), 2)
        XCTAssertNotNil(try LedgerMaintenance.currentMainBudget(in: context))
        _ = try LedgerMaintenance.upsertMainBudget(in: context, amount: 400, startDate: date(2026, 1, 1), type: 2)
        XCTAssertEqual(try LedgerMaintenance.currentMainBudget(in: context)?.amount, 400)
        XCTAssertEqual(try context.count(for: MainBudget.fetchRequest()), 3)
    }

    func testPeerTimeZonesConvergeDatesAcrossDSTAndRetainEditsAndDeletions() throws {
        let seedID = UUID()
        let seriesID = "legacy:\(seedID.uuidString.lowercased())"
        let anchor = date(2026, 10, 31, 7) // Midnight in Los Angeles before fall-back.
        let now = date(2026, 11, 4, 12)
        let peers = [controller.container.newBackgroundContext(), controller.container.newBackgroundContext()]
        for (index, peer) in peers.enumerated() {
            try peer.performAndWait {
                let seed = Transaction(context: peer)
                seed.id = seedID
                seed.date = anchor
                seed.day = anchor
                seed.recurringType = 1
                seed.recurringCoefficient = 1
                let series = try LedgerMaintenance.attachSeries(to: seed, timeZone: TimeZone(identifier: index == 0 ? "America/Los_Angeles" : "Asia/Tokyo")!, in: peer)
                series.deduplicationToken = index == 0 ? "a" : "b"
                try LedgerMaintenance.materialize(in: peer, now: now)
            }
        }
        // Save only after both peers generated their own complete candidate rows.
        for peer in peers { try peer.performAndWait { try peer.save() } }
        let context = controller.container.viewContext
        try LedgerMaintenance.reconcile(in: context)
        try LedgerMaintenance.materialize(in: context, now: now)
        let series = try XCTUnwrap(context.fetch(RecurringSeries.fetchRequest()).first)
        XCTAssertEqual(series.timeZoneID, "America/Los_Angeles")
        let secondKey = LedgerMaintenance.occurrenceKey(seriesID: seriesID, index: 2)
        let occurrence = try XCTUnwrap(context.fetch(Transaction.fetchRequest()).first { $0.occurrenceKey == secondKey })
        XCTAssertEqual(occurrence.date, date(2026, 11, 2, 8))
        let edited = try XCTUnwrap(context.fetch(Transaction.fetchRequest()).first { $0.occurrenceKey == LedgerMaintenance.occurrenceKey(seriesID: seriesID, index: 1) })
        edited.date = date(2026, 10, 20)
        edited.scheduleDateOverridden = true
        edited.note = "User edit"
        try LedgerMaintenance.deleteTransaction(occurrence, in: context)
        XCTAssertNil(series.stoppedAt) // A historical deletion does not stop the current schedule.
        let duplicateSeed = Transaction(context: context)
        duplicateSeed.id = seedID
        duplicateSeed.date = anchor
        duplicateSeed.day = anchor
        duplicateSeed.recurringType = 1
        duplicateSeed.recurringCoefficient = 1
        let late = try LedgerMaintenance.attachSeries(to: duplicateSeed, logicalID: seriesID, timeZone: TimeZone(identifier: "Asia/Tokyo")!, in: context)
        late.deduplicationToken = "z"
        try LedgerMaintenance.reconcile(in: context)
        try LedgerMaintenance.materialize(in: context, now: now)
        XCTAssertFalse(try context.fetch(Transaction.fetchRequest()).contains { $0.occurrenceKey == secondKey })
        XCTAssertEqual(edited.date, date(2026, 10, 20))
        XCTAssertEqual(edited.note, "User edit")
        XCTAssertNil(series.stoppedAt)
        let active = try XCTUnwrap(context.fetch(Transaction.fetchRequest()).first { $0.recurringType > 0 })
        XCTAssertEqual(active.nextTransactionDate, series.nextDate)
        try LedgerMaintenance.stopSeries(for: active, in: context)
        try LedgerMaintenance.reconcile(in: context)
        XCTAssertTrue(try context.fetch(Transaction.fetchRequest()).allSatisfy { $0.recurringType == 0 })
        XCTAssertEqual(try LedgerMaintenance.materialize(in: context, now: date(2027, 1, 1)), 0)
    }

    func testConcurrentEditGenerationsChooseOneFamilyAndStopDoesNotResurrect() throws {
        let context = controller.container.viewContext
        let family = UUID().uuidString
        let seed = Transaction(context: context)
        seed.id = UUID()
        seed.date = date(2026, 1, 1)
        seed.recurringType = 1
        seed.recurringCoefficient = 1
        for identity in ["generation-a", "generation-b"] {
            try LedgerMaintenance.attachSeries(to: seed, logicalID: identity, familyID: family, createdAt: date(2026, 1, 2), in: context)
        }
        seed.seriesID = "generation-a" // Transaction and series records can import in either order.
        try LedgerMaintenance.reconcile(in: context)
        let active = try context.fetch(RecurringSeries.fetchRequest()).filter { $0.stoppedAt == nil }
        XCTAssertEqual(active.map(\.logicalID), ["generation-b"])
        let winner = try XCTUnwrap(active.first)
        XCTAssertEqual(seed.seriesID, winner.logicalID)
        XCTAssertEqual(seed.nextTransactionDate, winner.nextDate)
        XCTAssertEqual(try context.fetch(Transaction.fetchRequest()).filter { $0.recurringType > 0 }.count, 1)
        winner.stoppedAt = date(2026, 1, 3)
        try LedgerMaintenance.reconcile(in: context)
        XCTAssertTrue(try context.fetch(RecurringSeries.fetchRequest()).allSatisfy { $0.stoppedAt != nil })
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 1)
    }

    func testNoncanonicalOccurrenceKeepsExplicitlyEditedPayloadOnMerge() throws {
        let context = controller.container.viewContext
        let category = LittleSaverCore.Category(context: context)
        category.id = UUID()
        category.name = "Edited category"
        let canonical = Transaction(context: context)
        canonical.id = UUID()
        canonical.occurrenceKey = "shared-series/1"
        canonical.deduplicationToken = "a"
        canonical.amount = 10
        canonical.note = "Generated"
        let edited = Transaction(context: context)
        edited.id = UUID()
        edited.occurrenceKey = canonical.occurrenceKey
        edited.deduplicationToken = "b"
        LedgerMaintenance.markUserEdit(edited, at: date(2026, 1, 2))
        edited.amount = 99
        edited.note = "Keep the explicit edit"
        edited.category = category
        edited.income = true
        edited.date = date(2026, 2, 3)
        edited.day = edited.date
        edited.month = date(2026, 2, 1)
        edited.scheduleDateOverridden = true
        let editToken = edited.userEditToken
        try LedgerMaintenance.reconcile(in: context)
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 1)
        XCTAssertEqual(canonical.deduplicationToken, "a")
        XCTAssertEqual(canonical.amount, 99)
        XCTAssertEqual(canonical.note, "Keep the explicit edit")
        XCTAssertEqual(canonical.category, category)
        XCTAssertTrue(canonical.income)
        XCTAssertEqual(canonical.date, date(2026, 2, 3))
        XCTAssertEqual(canonical.day, date(2026, 2, 3))
        XCTAssertEqual(canonical.month, date(2026, 2, 1))
        XCTAssertTrue(canonical.scheduleDateOverridden)
        XCTAssertEqual(canonical.userEditToken, editToken)
        try context.save()
        try LedgerMaintenance.reconcile(in: context)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testSerialCatchUpDrainsMoreThanOneBatchAndIsIdempotent() async throws {
        let context = controller.container.viewContext
        let seed = Transaction(context: context)
        seed.id = UUID()
        seed.date = date(2026, 1, 1)
        seed.day = seed.date
        seed.recurringType = 1
        seed.recurringCoefficient = 1
        try context.save()
        try await controller.catchUpRecurringTransactions(now: date(2027, 1, 1))
        let count = try await controller.performBackgroundRead { try $0.count(for: Transaction.fetchRequest()) }
        XCTAssertEqual(count, 366)
        try await controller.catchUpRecurringTransactions(now: date(2027, 1, 1))
        let secondCount = try await controller.performBackgroundRead { try $0.count(for: Transaction.fetchRequest()) }
        XCTAssertEqual(secondCount, count)
    }

    func testBackfillPreservesUnidentifiedRowsCustomColorsAndOrders() throws {
        let context = controller.container.viewContext
        for _ in 0..<2 {
            let transaction = Transaction(context: context)
            transaction.amount = 10
            transaction.note = "Same values are not identity"
            transaction.date = date(2026, 1, 1)
            transaction.recurringType = 1
            transaction.recurringCoefficient = 1
        }
        let custom = LittleSaverCore.Category(context: context)
        custom.colour = "#123456"
        custom.income = true
        custom.order = 17
        let legacy = LittleSaverCore.Category(context: context)
        legacy.colour = "1"
        legacy.order = 42
        try LedgerMaintenance.backfill(in: context)
        try LedgerMaintenance.reconcile(in: context)
        try LedgerMaintenance.backfill(in: context)
        XCTAssertEqual(try context.count(for: Transaction.fetchRequest()), 2)
        XCTAssertEqual(try context.count(for: RecurringSeries.fetchRequest()), 2)
        XCTAssertEqual(custom.colour, "#123456")
        XCTAssertEqual(custom.order, 17)
        XCTAssertEqual(legacy.colour, "#279AF4")
        XCTAssertEqual(legacy.order, 42)
    }

    @MainActor
    func testEraseSerializesWithQueuedRecurringCatchUp() async throws {
        let context = controller.container.viewContext
        let seed = Transaction(context: context)
        seed.id = UUID()
        seed.date = date(2020, 1, 1)
        seed.day = seed.date
        seed.recurringType = 1
        seed.recurringCoefficient = 1
        try context.save()
        let captured = controller!
        let pending = Task { try await captured.catchUpRecurringTransactions(now: date(2027, 1, 1)) }
        await Task.yield()
        captured.deleteAll()
        try await pending.value
        try await captured.catchUpRecurringTransactions(now: date(2027, 1, 1))
        let counts = try await captured.performBackgroundRead { context in
            try ["RecurringSeries", "RecurringSuppression", "Transaction", "TemplateTransaction", "Budget", "MainBudget", "Category"].map {
                try context.count(for: NSFetchRequest<NSManagedObject>(entityName: $0))
            }
        }
        XCTAssertTrue(counts.allSatisfy { $0 == 0 })
    }

    @MainActor
    func testLegacyDiskStoreReopensWithFrameworkModelAndPreservesRelationships() async throws {
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
            transaction.setValue(date(2099, 1, 1), forKey: "date")
            transaction.setValue(date(2099, 1, 1), forKey: "day")
            transaction.setValue(1, forKey: "recurringType")
            transaction.setValue(1, forKey: "recurringCoefficient")
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
        try await diskController.waitUntilReady()
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
        XCTAssertEqual(diskController.results(for: RecurringSeries.fetchRequest()).count, 1)
        let token = try XCTUnwrap(transaction.deduplicationToken)
        let occurrenceKey = try XCTUnwrap(transaction.occurrenceKey)
        let coordinator = diskController.container.persistentStoreCoordinator
        diskController.container.viewContext.reset()
        for store in coordinator.persistentStores { try coordinator.remove(store) }
        let reopened = try DataController(configuration: .init(mode: .sharedLocal,
            modelName: AppIdentifiers.persistentModel, storeURL: storeURL, reloadWidgetsAfterSave: false))
        try await reopened.waitUntilReady()
        let restored = try XCTUnwrap(reopened.results(for: Transaction.fetchRequest()).first)
        XCTAssertEqual(restored.deduplicationToken, token)
        XCTAssertEqual(restored.occurrenceKey, occurrenceKey)
        XCTAssertEqual(restored.category?.budget?.amount, 100)
        XCTAssertEqual(reopened.results(for: RecurringSeries.fetchRequest()).count, 1)
        XCTAssertEqual(reopened.results(for: MainBudget.fetchRequest()).first?.singletonKey, LedgerMaintenance.mainBudgetKey)
        reopened.container.viewContext.reset()
        for store in reopened.container.persistentStoreCoordinator.persistentStores {
            try reopened.container.persistentStoreCoordinator.remove(store)
        }
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
