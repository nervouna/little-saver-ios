import LittleSaverCore
import AppIntents
import Foundation

@available(iOS 16, *)
struct IncomeCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Category")
    typealias DefaultQueryType = IncomeCategoryQuery
    static var defaultQuery: IncomeCategoryQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Emoji")
    var emoji: String

    @Property(title: "Income")
    var income: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(id: UUID, name: String, emoji: String, income: Bool) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.income = income
    }
}

@available(iOS 16, *)
struct IncomeCategoryQuery: EntityStringQuery {
    var load: @Sendable () async throws -> [CategorySnapshot] = {
        try await DataController.platformShared.categorySnapshots(income: true)
    }

    func entities(matching query: String) async throws -> [IncomeCategoryEntity] {
        try await suggestedEntities().filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.emoji.localizedCaseInsensitiveContains(query)
        }
    }

    func entities(for identifiers: [IncomeCategoryEntity.ID]) async throws -> [IncomeCategoryEntity] {
        let values = try await suggestedEntities()
        return identifiers.compactMap { id in values.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [IncomeCategoryEntity] {
        try await load().map { value in
            return IncomeCategoryEntity(id: value.id, name: value.name, emoji: value.emoji, income: value.income)
        }
    }
}

@available(iOS 16, *)
struct ExpenseCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Category")
    typealias DefaultQueryType = ExpenseCategoryQuery
    static var defaultQuery: ExpenseCategoryQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Emoji")
    var emoji: String

    @Property(title: "Income")
    var income: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(id: UUID, name: String, emoji: String, income: Bool) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.income = income
    }
}

@available(iOS 16, *)
struct ExpenseCategoryQuery: EntityStringQuery {
    var load: @Sendable () async throws -> [CategorySnapshot] = {
        try await DataController.platformShared.categorySnapshots(income: false)
    }

    func entities(matching query: String) async throws -> [ExpenseCategoryEntity] {
        try await suggestedEntities().filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.emoji.localizedCaseInsensitiveContains(query)
        }
    }

    func entities(for identifiers: [ExpenseCategoryEntity.ID]) async throws -> [ExpenseCategoryEntity] {
        let values = try await suggestedEntities()
        return identifiers.compactMap { id in values.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [ExpenseCategoryEntity] {
        try await load().map { value in
            return ExpenseCategoryEntity(id: value.id, name: value.name, emoji: value.emoji, income: value.income)
        }
    }
}

@available(iOS 16, *)
struct BudgetEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Budget")
    typealias DefaultQueryType = BudgetQuery
    static var defaultQuery: BudgetQuery = .init()

    var id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Emoji")
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }

    init(id: UUID, name: String, emoji: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }
}

@available(iOS 16, *)
struct BudgetQuery: EntityStringQuery {
    var load: @Sendable () async throws -> [BudgetReadSnapshot] = {
        try await DataController.platformShared.budgetSnapshots()
    }

    func entities(matching query: String) async throws -> [BudgetEntity] {
        try await suggestedEntities().filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.emoji.localizedCaseInsensitiveContains(query)
        }
    }

    func entities(for identifiers: [BudgetEntity.ID]) async throws -> [BudgetEntity] {
        let values = try await suggestedEntities()
        return identifiers.compactMap { id in values.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [BudgetEntity] {
        try await load().compactMap { value in
            guard let id = value.id else { return nil }
            return BudgetEntity(id: id, name: value.name, emoji: value.emoji)
        }
    }
}
