import Foundation

public enum DeepLink: Equatable {
    case search
    case newExpense
    case insights
    case budget(name: String?)

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == AppIdentifiers.urlScheme,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty else {
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
            guard items.allSatisfy({ $0.name == "budget" }), items.count <= 1 else {
                return nil
            }
            if let value = items.first?.value {
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                self = .budget(name: value)
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
        }
        return components.url!
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
