import Foundation
import LocalAuthentication
import SwiftUI

protocol OwnerAuthenticationContext: AnyObject {
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void)
    func invalidate()
}
extension LAContext: OwnerAuthenticationContext {}

/// A system prompt may make the scene inactive; only genuine backgrounding
/// invalidates its token and any held success. This adapter belongs to the App.
@MainActor
final class AppLockViewModel: ObservableObject {
    @Published private(set) var isAppLockEnabled: Bool
    @Published private(set) var isAppUnLocked = false
    @Published private(set) var isPending = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var offersSettings = false
    @Published private(set) var phase: ScenePhase = .active

    private enum Action { case unlock, setEnabled(Bool) }
    private let preferences: UserDefaults
    private let contextFactory: () -> OwnerAuthenticationContext
    private var context: OwnerAuthenticationContext?
    private var token: UUID?
    private var heldSuccess: Action?

    init(preferences: UserDefaults = .standard, contextFactory: @escaping () -> OwnerAuthenticationContext = { LAContext() }) {
        self.preferences = preferences
        self.contextFactory = contextFactory
        isAppLockEnabled = preferences.bool(forKey: "appLockEnabled")
    }

    var protectsContent: Bool { isAppLockEnabled && (!isAppUnLocked || phase != .active) }
    var canHandleDeepLinks: Bool { !protectsContent }

    func appLockValidation() {
        guard isAppLockEnabled, !isAppUnLocked else { return }
        request(.unlock, reason: String(localized: "Authenticate to unlock LittleSaver"))
    }

    func appLockStateChange(appLockState: Bool) {
        guard appLockState != isAppLockEnabled else { return }
        request(.setEnabled(appLockState), reason: appLockState ? String(localized: "Authenticate to enable App Lock") : String(localized: "Authenticate to disable App Lock"))
    }

    func sceneChanged(_ phase: ScenePhase) {
        self.phase = phase
        switch phase {
        case .inactive:
            if isAppLockEnabled { isAppUnLocked = false }
        case .background:
            isAppUnLocked = false
            let oldContext = context
            token = nil; heldSuccess = nil; context = nil; isPending = false
            // Clear identity first: invalidate may synchronously invoke the reply.
            oldContext?.invalidate()
        case .active:
            if let action = heldSuccess { applySuccess(action) }
        @unknown default: break
        }
    }

    private func request(_ action: Action, reason: String) {
        guard token == nil, phase == .active else { return }
        let requestToken = UUID()
        let fresh = contextFactory()
        token = requestToken; context = fresh; isPending = true
        heldSuccess = nil; errorMessage = nil; offersSettings = false
        fresh.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
            Task { @MainActor in self?.complete(requestToken, action: action, success: success, error: error) }
        }
    }

    private func complete(_ requestToken: UUID, action: Action, success: Bool, error: Error?) {
        guard token == requestToken else { return }
        context = nil
        if success {
            if phase == .active { applySuccess(action) }
            else if phase == .inactive { heldSuccess = action }
        } else {
            token = nil; heldSuccess = nil; isPending = false
            offersSettings = (error as? LAError)?.code == .passcodeNotSet
            errorMessage = error?.localizedDescription ?? String(localized: "Authentication failed. Please try again.")
        }
    }

    private func applySuccess(_ action: Action) {
        token = nil; heldSuccess = nil; context = nil; isPending = false
        if case let .setEnabled(enabled) = action {
            preferences.set(enabled, forKey: "appLockEnabled")
            isAppLockEnabled = enabled
        }
        errorMessage = nil; offersSettings = false; isAppUnLocked = true
    }
}

/// Only presentation entry requests focus. Query/analytics changes have no focus event.
struct SearchFocusLifecycle {
    private(set) var appeared = false
    mutating func appear() -> Bool? {
        guard !appeared else { return nil }
        appeared = true
        return true
    }
    mutating func end() -> Bool { appeared = false; return false }
    func contentChanged() -> Bool? { nil }
}
