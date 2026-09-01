//
//  AppIdentifiers.swift
//  LittleSaver
//

import Foundation

enum AppIdentifiers {
    static let appBundle = "io.damao.littlesaver"
    static let widgetBundle = "io.damao.littlesaver.widget"
    static let intentBundle = "io.damao.littlesaver.intent"
    static let intentUIBundle = "io.damao.littlesaver.intentui"

    static let appGroup = "group.io.damao.littlesaver"
    static let cloudKitContainer = "iCloud.io.damao.littlesaver"
    static let urlScheme = "io.damao.littlesaver"
    static let persistentModel = "LittleSaverModel"
    static let persistentStore = "LittleSaver.sqlite"
}

enum AppRuntimeRole: Equatable {
    case mainApplication
    case widget
    case intentService
    case intentUI

    init(bundleIdentifier: String?) throws {
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

    var persistentStoreMode: PersistentStoreMode? {
        switch self {
        case .mainApplication: return .cloudSync
        case .widget, .intentService: return .sharedLocal
        case .intentUI: return nil
        }
    }
}

enum PersistentStoreMode: Equatable {
    case cloudSync
    case sharedLocal
    case inMemory
}

enum AppConfigurationError: LocalizedError, Equatable {
    case unknownBundleIdentifier(String?)
    case unavailableAppGroup(String)
    case unavailableManagedObjectModel(String)

    var errorDescription: String? {
        switch self {
        case let .unknownBundleIdentifier(identifier):
            return "Unsupported bundle identifier: \(identifier ?? "nil")"
        case let .unavailableAppGroup(identifier):
            return "The App Group container is unavailable: \(identifier)"
        case let .unavailableManagedObjectModel(name):
            return "The managed object model is unavailable: \(name)"
        }
    }
}
