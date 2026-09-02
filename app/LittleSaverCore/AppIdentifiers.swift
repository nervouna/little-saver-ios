//
//  AppIdentifiers.swift
//  LittleSaver
//

import Foundation

public enum AppIdentifiers {
    public static let appBundle = "io.damao.littlesaver"
    public static let widgetBundle = "io.damao.littlesaver.widget"
    public static let intentBundle = "io.damao.littlesaver.intent"
    public static let intentUIBundle = "io.damao.littlesaver.intentui"

    public static let appGroup = "group.io.damao.littlesaver"
    public static let cloudKitContainer = "iCloud.io.damao.littlesaver"
    public static let urlScheme = "io.damao.littlesaver"
    public static let persistentModel = "LittleSaverModel"
    public static let persistentStore = "LittleSaver.sqlite"
}

public enum AppRuntimeRole: Equatable {
    case mainApplication
    case widget
    case intentService
    case intentUI

    public init(bundleIdentifier: String?) throws {
        switch bundleIdentifier {
        case AppIdentifiers.appBundle:
            self = .mainApplication
        case AppIdentifiers.widgetBundle:
            self = .widget
        case AppIdentifiers.intentBundle:
            self = .intentService
        case AppIdentifiers.intentUIBundle:
            self = .intentUI
        default:
            throw AppConfigurationError.unknownBundleIdentifier(bundleIdentifier)
        }
    }

    public var persistentStoreMode: PersistentStoreMode? {
        switch self {
        case .mainApplication: return .cloudSync
        case .widget, .intentService: return .sharedLocal
        case .intentUI: return nil
        }
    }
}

public enum PersistentStoreMode: Equatable {
    case cloudSync
    case sharedLocal
    case inMemory
}

public enum AppConfigurationError: LocalizedError, Equatable {
    case unknownBundleIdentifier(String?)
    case unavailableAppGroup(String)
    case unavailableManagedObjectModel(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownBundleIdentifier(identifier):
            return String.localizedStringWithFormat(
                NSLocalizedString("Unsupported bundle identifier: %@", comment: "Unknown process configuration"),
                identifier ?? "nil"
            )
        case let .unavailableAppGroup(identifier):
            return String.localizedStringWithFormat(
                NSLocalizedString("The App Group container is unavailable: %@", comment: "Missing App Group container"),
                identifier
            )
        case let .unavailableManagedObjectModel(name):
            return String.localizedStringWithFormat(
                NSLocalizedString("The managed object model is unavailable: %@", comment: "Missing Core Data model"),
                name
            )
        }
    }
}
