import CoreData
import Foundation

/// Queue-confined maintenance. Identity never relies on a coordinator's object URI.
public enum LedgerMaintenance {
    public static let mainBudgetKey = "main-budget"
    public static let batchLimit = 256

    public static func occurrenceKey(seriesID: String, index: Int64) -> String {
        "\(seriesID)/\(index)"
    }

    @discardableResult
    public static func attachSeries(to transaction: Transaction, logicalID: String? = nil,
                                    familyID: String? = nil, createdAt: Date? = nil,
                                    timeZone: TimeZone = .current,
                                    in context: NSManagedObjectContext) throws -> RecurringSeries {
        if transaction.id == nil { transaction.id = UUID() }
        let identity = logicalID ?? "legacy:\(transaction.id!.uuidString.lowercased())"
        let series = RecurringSeries(context: context)
        series.logicalID = identity
        series.sourceTransactionID = transaction.id
        series.familyID = familyID ?? identity
        series.deduplicationToken = UUID().uuidString.lowercased()
        series.createdAt = createdAt ?? Date(timeIntervalSince1970: 0)
        series.timeZoneID = timeZone.identifier
        series.anchorDate = transaction.day ?? transaction.date
        series.sourceIndex = transaction.occurrenceIndex
        series.type = transaction.recurringType
        series.coefficient = transaction.recurringCoefficient
        series.note = transaction.note
        series.amount = transaction.amount
        series.income = transaction.income
        series.category = transaction.category
        transaction.seriesID = identity
        transaction.onceRecurring = true
        if transaction.occurrenceKey == nil {
            transaction.occurrenceKey = occurrenceKey(seriesID: series.occurrenceNamespace!, index: series.sourceIndex)
        }
        series.sourceOccurrenceKey = transaction.occurrenceKey
        if transaction.deduplicationToken == nil { transaction.deduplicationToken = UUID().uuidString.lowercased() }
        resetCursor(series)
        return series
    }

    public static func backfill(in context: NSManagedObjectContext) throws {
        let transactions = try context.fetch(Transaction.fetchRequest())
        let known = Set(try context.fetch(RecurringSeries.fetchRequest()).compactMap(\.logicalID))
        for transaction in transactions {
            if transaction.id == nil { transaction.id = UUID() }
            if transaction.deduplicationToken == nil { transaction.deduplicationToken = UUID().uuidString.lowercased() }
            if transaction.recurringType > 0 && transaction.seriesID == nil {
                let identity = "legacy:\(transaction.id!.uuidString.lowercased())"
                if known.contains(identity) {
                    transaction.seriesID = identity
                    transaction.occurrenceKey = occurrenceKey(seriesID: identity, index: 0)
                } else {
                    try attachSeries(to: transaction, logicalID: identity, in: context)
                }
            }
        }
        for budget in try context.fetch(MainBudget.fetchRequest()) {
            if budget.singletonKey == nil { budget.singletonKey = mainBudgetKey }
        }
        // Numeric colors identify legacy rows. Valid custom colors and ordering are never reset.
        let colors = ["#279AF4", "#EC7A58", "#A6678A", "#C56AF7", "#6E7BF1", "#F3BF56", "#ED80A2", "#F6D24A", "#E34D63", "#61C7FA", "#7014F5", "#EB7068", "#84B4EB", "#4088AD", "#B8D6FA", "#C38D5D", "#A0ACF9", "#7CB0AA", "#F6D489", "#88997A", "#F1AF8A", "#2D4B7B", "#5FAF9F", "#D46D7F"]
        for category in try context.fetch(Category.fetchRequest()) {
            if let value = category.colour, let number = Int(value), (1...colors.count).contains(number) {
                category.colour = category.income ? "#76FBB1" : colors[number - 1]
            }
        }
    }

    public static func reconcile(in context: NSManagedObjectContext) throws {
        let series = try context.fetch(RecurringSeries.fetchRequest())
        for group in Dictionary(grouping: series.filter { $0.logicalID != nil }, by: { $0.logicalID! }).values {
            let sorted = group.sorted { ($0.deduplicationToken ?? "") < ($1.deduplicationToken ?? "") }
            guard let canonical = sorted.first else { continue }
            if let stopped = group.compactMap(\.stoppedAt).max(), canonical.stoppedAt != stopped { canonical.stoppedAt = stopped }
            if sorted.count > 1 {
                // Replay the chosen schedule to normalize dates made by a peer in another zone.
                resetCursor(canonical)
                for duplicate in sorted.dropFirst() { context.delete(duplicate) }
            }
        }
        let live = series.filter { !$0.isDeleted && $0.familyID != nil }
        for family in Dictionary(grouping: live, by: { $0.familyID! }).values {
            let sorted = family.sorted {
                if $0.createdAt != $1.createdAt { return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                return ($0.logicalID ?? "") > ($1.logicalID ?? "")
            }
            for obsolete in sorted.dropFirst() where obsolete.stoppedAt == nil {
                obsolete.stoppedAt = sorted[0].createdAt ?? Date(timeIntervalSince1970: 0)
            }
        }
        let transactions = try context.fetch(Transaction.fetchRequest())
        let suppressed = Set(try context.fetch(RecurringSuppression.fetchRequest()).compactMap(\.occurrenceKey))
        for transaction in transactions where transaction.occurrenceKey.map(suppressed.contains) == true {
            context.delete(transaction)
        }
        for group in Dictionary(grouping: transactions.filter { !$0.isDeleted && $0.occurrenceKey != nil }, by: { $0.occurrenceKey! }).values {
            let sorted = group.sorted { ($0.deduplicationToken ?? "") < ($1.deduplicationToken ?? "") }
            if let canonical = sorted.first, let edited = sorted.filter({ $0.userEditedAt != nil }).max(by: {
                if $0.userEditedAt != $1.userEditedAt { return $0.userEditedAt! < $1.userEditedAt! }
                return ($0.userEditToken ?? "") < ($1.userEditToken ?? "")
            }), edited !== canonical {
                // Canonical object identity and canonical human-edited payload are independent.
                canonical.amount = edited.amount
                canonical.note = edited.note
                canonical.category = edited.category
                canonical.income = edited.income
                canonical.date = edited.date
                canonical.day = edited.day
                canonical.month = edited.month
                canonical.scheduleDateOverridden = edited.scheduleDateOverridden
                canonical.onceRecurring = edited.onceRecurring
                canonical.userEditedAt = edited.userEditedAt
                canonical.userEditToken = edited.userEditToken
            }
            if sorted.count > 1, let key = sorted.first?.occurrenceKey,
               let separator = key.lastIndex(of: "/"),
               let schedule = scheduleOwners(live).first(where: {
                   $0.occurrenceNamespace == String(key[..<separator])
                       && (sorted.first?.occurrenceIndex ?? 0) > $0.sourceIndex
                       && (sorted.first?.occurrenceIndex ?? 0) <= lastOwnedIndex($0, series: live)
               }) {
                // Occurrences may import after their duplicate series rows were already merged.
                resetCursor(schedule)
            }
            for duplicate in sorted.dropFirst() { context.delete(duplicate) }
        }
        // MainBudget candidates are intentionally retained. V0 has no portable row identity;
        // destructive deduplication of independently backfilled tokens can erase every copy.
        // Legacy UI projects the current series on its latest occurrence only.
        var projections: [NSManagedObjectID: RecurringSeries] = [:]
        for owner in scheduleOwners(live) {
            if transactions.contains(where: { !$0.isDeleted && needsNormalization($0, owner: owner, series: live) && $0.occurrenceIndex < owner.nextIndex }) {
                resetCursor(owner)
            }
        }
        for current in live where current.stoppedAt == nil {
            let latest = transactions.filter { !$0.isDeleted && belongsToNamespace($0, series: current) && $0.occurrenceIndex > current.sourceIndex }
                .max { $0.occurrenceIndex < $1.occurrenceIndex }
                ?? transactions.first {
                    !$0.isDeleted && (($0.id != nil && $0.id == current.sourceTransactionID)
                        || ($0.occurrenceKey != nil && $0.occurrenceKey == current.sourceOccurrenceKey))
                }
            if let latest {
                if latest.seriesID != current.logicalID { latest.seriesID = current.logicalID }
                projections[latest.objectID] = current
            }
        }
        for transaction in transactions where !transaction.isDeleted && transaction.seriesID != nil {
            let current = projections[transaction.objectID]
            let type = current?.type ?? 0
            if transaction.recurringType != type { transaction.recurringType = type }
            if let coefficient = current?.coefficient, transaction.recurringCoefficient != coefficient { transaction.recurringCoefficient = coefficient }
            if transaction.nextScheduledDate != current?.nextDate { transaction.nextScheduledDate = current?.nextDate }
        }
    }

    public static func hasDueWork(in context: NSManagedObjectContext, now: Date) throws -> Bool {
        guard now.timeIntervalSince1970.isFinite else { throw RecurringScheduleError.dateCalculationFailed }
        let series = try context.fetch(RecurringSeries.fetchRequest())
        let transactions = try context.fetch(Transaction.fetchRequest())
        return scheduleOwners(series).contains { owner in
            if owner.stoppedAt != nil {
                guard owner.nextDate != nil, calendar(for: owner) != nil else { return false }
                return transactions.contains { needsNormalization($0, owner: owner, series: series) }
            }
            // A final bounded pass must quarantine invalid rows even if the prior batch filled up.
            guard let next = owner.nextDate, next.timeIntervalSince1970.isFinite, let calendar = calendar(for: owner) else { return true }
            return calendar.startOfDay(for: next) <= calendar.startOfDay(for: now)
                || transactions.contains { isPrematureLosingOccurrence($0, owner: owner, series: series) }
        }
    }

    /// Work is bounded by visited slots, including slots already present from another peer.
    @discardableResult
    public static func materialize(in context: NSManagedObjectContext, now: Date = Date(), limit: Int = batchLimit) throws -> Int {
        guard now.timeIntervalSince1970.isFinite else { throw RecurringScheduleError.dateCalculationFailed }
        guard limit > 0 else { return 0 }
        let all = try context.fetch(Transaction.fetchRequest())
        var byKey: [String: Transaction] = [:]
        for transaction in all { if let key = transaction.occurrenceKey { byKey[key] = transaction } }
        let series = try context.fetch(RecurringSeries.fetchRequest())
        var visited = 0
        var inserted = 0
        let suppressed = Set(try context.fetch(RecurringSuppression.fetchRequest()).compactMap(\.occurrenceKey))
        for current in scheduleOwners(series) {
            guard let identity = current.logicalID, let namespace = current.occurrenceNamespace, let calendar = calendar(for: current) else {
                if current.stoppedAt == nil { current.stoppedAt = now }
                continue
            }
            let today = calendar.startOfDay(for: now)
            // Stopped winners normalize imported sibling records but never create occurrences.
            let replayOnly = current.stoppedAt != nil
            let pendingMaximum = all.filter { needsNormalization($0, owner: current, series: series) }.map(\.occurrenceIndex).max() ?? 0
            while visited < limit {
                if replayOnly && current.nextIndex > pendingMaximum { break }
                guard let due = current.nextDate, due.timeIntervalSince1970.isFinite,
                      current.nextIndex > 0, current.nextIndex < Int64.max else {
                    if current.stoppedAt == nil { current.stoppedAt = now }
                    if current.nextDate != nil { current.nextDate = nil }
                    break
                }
                if !replayOnly && calendar.startOfDay(for: due) > today { break }
                visited += 1
                let key = occurrenceKey(seriesID: namespace, index: current.nextIndex)
                if suppressed.contains(key) {
                    do {
                        current.nextDate = try RecurringSchedule.nextDate(after: due, type: current.type, coefficient: current.coefficient, calendar: calendar)
                        current.nextIndex += 1
                    } catch {
                        if current.stoppedAt == nil { current.stoppedAt = now }
                        current.nextDate = nil
                        break
                    }
                    continue
                }
                let transaction: Transaction
                if let existing = byKey[key] {
                    transaction = existing
                } else if replayOnly {
                    do {
                        current.nextDate = try RecurringSchedule.nextDate(after: due, type: current.type, coefficient: current.coefficient, calendar: calendar)
                        current.nextIndex += 1
                    } catch {
                        current.nextDate = nil
                        break
                    }
                    continue
                } else {
                    transaction = Transaction(context: context)
                    transaction.id = UUID()
                    transaction.deduplicationToken = UUID().uuidString.lowercased()
                    transaction.occurrenceKey = key
                    transaction.occurrenceIndex = current.nextIndex
                    transaction.seriesID = identity
                    transaction.materializedGenerationID = identity
                    transaction.normalizedGenerationID = identity
                    transaction.amount = current.amount
                    transaction.note = current.note
                    transaction.income = current.income
                    transaction.category = current.category
                    transaction.onceRecurring = true
                    byKey[key] = transaction
                    inserted += 1
                }
                if transaction.seriesID != identity { transaction.seriesID = identity }
                if transaction.occurrenceIndex != current.nextIndex { transaction.occurrenceIndex = current.nextIndex }
                if transaction.materializedGenerationID != nil {
                    if transaction.userEditedAt == nil && !transaction.scheduleDateOverridden,
                       let stop = current.stoppedAt, due > stop {
                        // This automatic occurrence would only become due after the plan stopped.
                        context.delete(transaction)
                    } else if transaction.userEditedAt == nil && !transaction.scheduleDateOverridden {
                        // The winning schedule owns automatic payload; human edits remain intact.
                        if transaction.amount != current.amount { transaction.amount = current.amount }
                        if transaction.note != current.note { transaction.note = current.note }
                        if transaction.income != current.income { transaction.income = current.income }
                        if transaction.category != current.category { transaction.category = current.category }
                        if transaction.date != due {
                            transaction.date = due
                            transaction.day = calendar.startOfDay(for: due)
                            transaction.month = calendar.dateInterval(of: .month, for: due)?.start
                        }
                    }
                    if !transaction.isDeleted && transaction.normalizedGenerationID != identity { transaction.normalizedGenerationID = identity }
                }
                do {
                    current.nextDate = try RecurringSchedule.nextDate(after: due, type: current.type, coefficient: current.coefficient, calendar: calendar)
                    current.nextIndex += 1
                } catch {
                    if current.stoppedAt == nil { current.stoppedAt = now }
                    current.nextDate = nil
                    break
                }
            }
            if !replayOnly && visited < limit {
                // Withdraw only proven losing-branch automatic rows whose scheduled date is
                // earlier than even the winner's first future slot. Never prune clock rollback
                // records already normalized to the winner, or any explicitly edited payload.
                let premature = all.filter { isPrematureLosingOccurrence($0, owner: current, series: series) }
                    .sorted { $0.occurrenceIndex < $1.occurrenceIndex }
                for transaction in premature.prefix(limit - visited) {
                    context.delete(transaction)
                    visited += 1
                }
            }
            if visited == limit { break }
        }
        try reconcile(in: context)
        return inserted
    }

    private static func scheduleOwners(_ series: [RecurringSeries]) -> [RecurringSeries] {
        let valid = series.filter { !$0.isDeleted && $0.occurrenceNamespace != nil }
        return valid.filter { $0.sourceIndex < lastOwnedIndex($0, series: valid) }.sorted {
            if $0.occurrenceNamespace != $1.occurrenceNamespace { return ($0.occurrenceNamespace ?? "") < ($1.occurrenceNamespace ?? "") }
            return $0.sourceIndex < $1.sourceIndex
        }
    }

    private static func lastOwnedIndex(_ owner: RecurringSeries, series: [RecurringSeries]) -> Int64 {
        series.filter {
            !$0.isDeleted && $0.occurrenceNamespace == owner.occurrenceNamespace
                && (($0.createdAt ?? .distantPast) > (owner.createdAt ?? .distantPast)
                    || ($0.createdAt == owner.createdAt && ($0.logicalID ?? "") > (owner.logicalID ?? "")))
        }.map(\.sourceIndex).min() ?? Int64.max
    }

    private static func belongsToNamespace(_ transaction: Transaction, series: RecurringSeries) -> Bool {
        guard transaction.occurrenceIndex > 0, let namespace = series.occurrenceNamespace else { return false }
        return transaction.occurrenceKey == occurrenceKey(seriesID: namespace, index: transaction.occurrenceIndex)
    }

    private static func needsNormalization(_ transaction: Transaction, owner: RecurringSeries, series: [RecurringSeries]) -> Bool {
        guard !transaction.isDeleted, belongsToNamespace(transaction, series: owner),
              transaction.occurrenceIndex > owner.sourceIndex,
              transaction.occurrenceIndex <= lastOwnedIndex(owner, series: series),
              let origin = transaction.materializedGenerationID else { return false }
        guard series.contains(where: { $0.logicalID == origin && $0.occurrenceNamespace == owner.occurrenceNamespace }) else { return false }
        if transaction.normalizedGenerationID != owner.logicalID { return true }
        if transaction.userEditedAt == nil, !transaction.scheduleDateOverridden,
           let stop = owner.stoppedAt, let date = transaction.date { return date > stop }
        return false
    }

    private static func isPrematureLosingOccurrence(_ transaction: Transaction, owner: RecurringSeries, series: [RecurringSeries]) -> Bool {
        guard needsNormalization(transaction, owner: owner, series: series),
              transaction.materializedGenerationID != owner.logicalID,
              transaction.userEditedAt == nil, !transaction.scheduleDateOverridden,
              transaction.occurrenceIndex >= owner.nextIndex,
              let date = transaction.date, let firstFuture = owner.nextDate else { return false }
        return date < firstFuture
    }

    public static func stopSeries(for transaction: Transaction, in context: NSManagedObjectContext) throws {
        if let identity = transaction.seriesID {
            for series in try context.fetch(RecurringSeries.fetchRequest()) where series.logicalID == identity && series.stoppedAt == nil {
                series.stoppedAt = Date()
            }
        }
        transaction.recurringType = 0
    }

    public static func deleteTransaction(_ transaction: Transaction, in context: NSManagedObjectContext) throws {
        if let key = transaction.occurrenceKey {
            let suppression = RecurringSuppression(context: context)
            suppression.occurrenceKey = key
        }
        if transaction.recurringType > 0 { try stopSeries(for: transaction, in: context) }
        context.delete(transaction)
    }

    public static func markUserEdit(_ transaction: Transaction, at date: Date = Date()) {
        transaction.userEditedAt = date
        transaction.userEditToken = UUID().uuidString.lowercased()
    }

    public static func replaceSeries(for transaction: Transaction, in context: NSManagedObjectContext) throws {
        let type = transaction.recurringType
        let old = try context.fetch(RecurringSeries.fetchRequest()).first { $0.logicalID == transaction.seriesID }
        try stopSeries(for: transaction, in: context)
        transaction.recurringType = type
        if type > 0 {
            if let old {
                try attachSeries(to: transaction, logicalID: UUID().uuidString.lowercased(), familyID: old.familyID ?? old.logicalID, createdAt: Date(), in: context)
            } else {
                try attachSeries(to: transaction, in: context)
            }
        }
    }

    @discardableResult
    public static func upsertMainBudget(in context: NSManagedObjectContext, amount: Double, startDate: Date, type: Int16) throws -> MainBudget {
        let budget = try appendMainBudgetRevision(in: context)
        budget.amount = amount
        budget.startDate = startDate
        budget.type = type
        return budget
    }

    public static func deleteMainBudget(in context: NSManagedObjectContext) throws {
        let tombstone = try appendMainBudgetRevision(in: context)
        tombstone.isDeletion = true
    }

    public static func currentMainBudget(in context: NSManagedObjectContext) throws -> MainBudget? {
        currentMainBudget(from: try context.fetch(MainBudget.fetchRequest()))
    }

    /// One logical projection, not a physical-row uniqueness claim. Legacy ranking selects
    /// display data only; it is never used to delete or identify any legacy object.
    public static func currentMainBudget(from candidates: [MainBudget]) -> MainBudget? {
        let rows = candidates.filter { !$0.isDeleted && ($0.singletonKey == nil || $0.singletonKey == mainBudgetKey) }
        let revisions = rows.filter { $0.revision > 0 && $0.deduplicationToken != nil }
        if let latest = revisions.max(by: {
            if $0.revision != $1.revision { return $0.revision < $1.revision }
            return $0.deduplicationToken! < $1.deduplicationToken!
        }) { return latest.isDeletion ? nil : latest }
        return rows.max { legacyBudgetRank($0).lexicographicallyPrecedes(legacyBudgetRank($1)) }
    }

    private static func legacyBudgetRank(_ budget: MainBudget) -> [String] {
        [budget.dateCreated.map { String($0.timeIntervalSince1970.bitPattern) } ?? "",
         budget.startDate.map { String($0.timeIntervalSince1970.bitPattern) } ?? "",
         String(budget.amount.bitPattern), String(budget.type), budget.green ? "1" : "0"]
    }

    private static func appendMainBudgetRevision(in context: NSManagedObjectContext) throws -> MainBudget {
        let candidates = try context.fetch(MainBudget.fetchRequest())
        let latestRevision = candidates.map(\.revision).max() ?? 0
        guard latestRevision < Int64.max else { throw RecurringScheduleError.dateCalculationFailed }
        let prior = currentMainBudget(from: candidates)
        let budget = MainBudget(context: context)
        budget.singletonKey = mainBudgetKey
        budget.revision = max(0, latestRevision) + 1
        budget.deduplicationToken = UUID().uuidString.lowercased()
        budget.dateCreated = prior?.dateCreated ?? Date()
        budget.green = prior?.green ?? false
        return budget
    }

    private static func calendar(for series: RecurringSeries) -> Calendar? {
        guard let identifier = series.timeZoneID, let zone = TimeZone(identifier: identifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func resetCursor(_ series: RecurringSeries) {
        guard series.sourceIndex >= 0, series.sourceIndex < Int64.max,
              let anchor = series.anchorDate, anchor.timeIntervalSince1970.isFinite,
              let calendar = calendar(for: series),
              let next = try? RecurringSchedule.nextDate(after: anchor, type: series.type, coefficient: series.coefficient, calendar: calendar) else {
            series.stoppedAt = series.stoppedAt ?? Date(timeIntervalSince1970: 0)
            series.nextDate = nil
            return
        }
        series.nextIndex = series.sourceIndex + 1
        series.nextDate = next
    }
}
