import Foundation

public enum DeepLink: Equatable, Sendable {
    case search
    case newExpense
    case insights
    case budget(name: String?)
    case budgetUUID(UUID)

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == AppIdentifiers.urlScheme,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty, components.fragment == nil else {
            return nil
        }

        switch components.host {
        case "search" where components.queryItems == nil:
            self = .search
        case "newExpense" where components.queryItems == nil:
            self = .newExpense
        case "insights" where components.queryItems == nil:
            self = .insights
        case "budget":
            let items = components.queryItems ?? []
            guard items.count <= 1 else {
                return nil
            }
            if let item = items.first {
                guard let value = item.value else { return nil }
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                if item.name == "budgetUUID", let id = UUID(uuidString: value) { self = .budgetUUID(id) }
                else if item.name == "budget" { self = .budget(name: value) }
                else { return nil }
            } else {
                self = .budget(name: nil)
            }
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = AppIdentifiers.urlScheme
        switch self {
        case .search:
            components.host = "search"
        case .newExpense:
            components.host = "newExpense"
        case .insights:
            components.host = "insights"
        case let .budget(name):
            components.host = "budget"
            if let name {
                components.queryItems = [URLQueryItem(name: "budget", value: name)]
            }
        case let .budgetUUID(id):
            components.host = "budget"
            components.queryItems = [URLQueryItem(name: "budgetUUID", value: id.uuidString)]
        }
        return components.url!
    }
}

public enum BudgetDestinationTarget: Equatable, Sendable {
    case uuid(UUID)
    case legacyName(String)
}

public struct BudgetNavigationRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let target: BudgetDestinationTarget
    public init(target: BudgetDestinationTarget, id: UUID = UUID()) { self.target = target; self.id = id }
}

public struct BudgetNavigationState: Sendable {
    public private(set) var consumedRequest: UUID?
    public private(set) var reference: URL?
    public private(set) var isMainBudget = false
    public private(set) var unavailable = false
    public init() {}

    public mutating func resolve(_ request: BudgetNavigationRequest?, snapshot: BudgetDashboardSnapshot?) {
        guard let request, consumedRequest != request.id, let snapshot else { return }
        // Count invalid rows too; filtering them first could make an ambiguous name unique.
        let matches = snapshot.budgets.filter { budget in
            switch request.target {
            case let .uuid(id): return budget.businessID == id
            case let .legacyName(name): return budget.name == name
            }
        }
        consumedRequest = request.id; reference = nil; isMainBudget = false; unavailable = false
        guard matches.count == 1, let match = matches.first, match.read != nil else { unavailable = true; return }
        reference = match.id
    }

    public mutating func dismiss() { reference = nil }
    public mutating func select(_ reference: URL, isMainBudget: Bool = false) {
        self.reference = reference; self.isMainBudget = isMainBudget; unavailable = false
    }
}

public struct DeepLinkRouter: Equatable {
    public init() {}

    public private(set) var pendingLink: DeepLink?

    public mutating func receive(_ link: DeepLink, isLocked: Bool) -> DeepLink? {
        guard isLocked else {
            pendingLink = nil
            return link
        }
        pendingLink = link
        return nil
    }

    public mutating func unlock() -> DeepLink? {
        defer { pendingLink = nil }
        return pendingLink
    }
}
