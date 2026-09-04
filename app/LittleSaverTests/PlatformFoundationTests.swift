import Foundation
import CoreData
import LocalAuthentication
import LittleSaverCore
import XCTest
@testable import LittleSaver

final class PlatformFoundationTests: XCTestCase {
    @MainActor
    private func settleCallbacks() async { for _ in 0..<8 { await Task.yield() } }

    @MainActor
    func testAuthenticationInactiveSuccessOrdersAndBackgroundStaleCallbacks() async {
        for successFirst in [true, false] {
            let prefs = UserDefaults(suiteName: "T8-\(UUID().uuidString)")!
            prefs.set(true, forKey: "appLockEnabled")
            let first = FakeOwnerContext(); let second = FakeOwnerContext()
            var contexts = [first, second]
            let model = AppLockViewModel(preferences: prefs, contextFactory: { contexts.removeFirst() })
            model.appLockValidation(); model.sceneChanged(.inactive)
            XCTAssertFalse(first.invalidated); XCTAssertTrue(model.protectsContent)
            if successFirst {
                first.callbacks[0](true, nil); await settleCallbacks()
                XCTAssertFalse(model.canHandleDeepLinks); XCTAssertTrue(model.isPending)
                model.sceneChanged(.active)
            } else {
                model.sceneChanged(.active)
                XCTAssertFalse(model.canHandleDeepLinks)
                first.callbacks[0](true, nil); await settleCallbacks()
            }
            XCTAssertTrue(model.isAppUnLocked); XCTAssertTrue(model.canHandleDeepLinks)
            model.sceneChanged(.background); model.sceneChanged(.active); model.appLockValidation()
            first.callbacks[0](true, nil); await settleCallbacks()
            XCTAssertFalse(model.isAppUnLocked); XCTAssertTrue(model.isPending)
            second.callbacks[0](true, nil); await settleCallbacks()
            XCTAssertTrue(model.isAppUnLocked)
        }
    }

    @MainActor
    func testBackgroundClearsHeldSuccessAndTokenBeforeSynchronousInvalidation() async {
        for held in [false, true] {
            let prefs = UserDefaults(suiteName: "T8-\(UUID().uuidString)")!
            prefs.set(true, forKey: "appLockEnabled")
            let context = FakeOwnerContext()
            let model = AppLockViewModel(preferences: prefs, contextFactory: { context })
            model.appLockStateChange(appLockState: false); model.sceneChanged(.inactive)
            if held { context.callbacks[0](true, nil); await settleCallbacks() }
            context.onInvalidate = { context.callbacks[0](true, nil) }
            model.sceneChanged(.background); await settleCallbacks(); model.sceneChanged(.active)
            XCTAssertFalse(model.isAppUnLocked); XCTAssertFalse(model.isPending)
            XCTAssertTrue(model.isAppLockEnabled); XCTAssertTrue(prefs.bool(forKey: "appLockEnabled"))
        }
    }

    @MainActor
    func testAuthenticationFailureRetryAndSuccessOnlyPreferenceChanges() async {
        let prefs = UserDefaults(suiteName: "T8-\(UUID().uuidString)")!
        var contexts: [FakeOwnerContext] = []
        let model = AppLockViewModel(preferences: prefs, contextFactory: { let context = FakeOwnerContext(); contexts.append(context); return context })
        model.appLockStateChange(appLockState: true)
        XCTAssertFalse(prefs.bool(forKey: "appLockEnabled"))
        contexts[0].callbacks[0](false, LAError(.passcodeNotSet)); await settleCallbacks()
        XCTAssertTrue(model.offersSettings); XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isAppLockEnabled); XCTAssertFalse(model.isPending)
        model.appLockStateChange(appLockState: true)
        contexts[1].callbacks[0](true, nil); await settleCallbacks()
        XCTAssertTrue(prefs.bool(forKey: "appLockEnabled")); XCTAssertTrue(model.isAppUnLocked)
        for code in [LAError.Code.userCancel, .authenticationFailed] {
            model.appLockStateChange(appLockState: false)
            contexts.last?.callbacks[0](false, LAError(code)); await settleCallbacks()
            XCTAssertTrue(model.isAppLockEnabled); XCTAssertTrue(prefs.bool(forKey: "appLockEnabled"))
            XCTAssertFalse(model.isPending)
        }
        model.appLockStateChange(appLockState: false)
        contexts.last?.callbacks[0](true, nil); await settleCallbacks()
        XCTAssertFalse(model.isAppLockEnabled); XCTAssertFalse(prefs.bool(forKey: "appLockEnabled"))
        XCTAssertEqual(contexts.count, 5)
    }

    func testNativeSearchFocusLifecycleDoesNotRefocusOnContentChanges() throws {
        var focus = SearchFocusLifecycle()
        XCTAssertEqual(focus.appear(), true)
        XCTAssertNil(focus.appear())
        XCTAssertNil(focus.contentChanged())
        XCTAssertNil(focus.contentChanged())
        XCTAssertEqual(focus.end(), false)
        XCTAssertEqual(focus.appear(), true)
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: app.appendingPathComponent("LittleSaver/Views/Log/LogSearchView.swift"))
        XCTAssertFalse(source.contains(".introspect("))
        XCTAssertTrue(source.contains(".focused($searchFocused)"))
        XCTAssertTrue(source.contains("focusLifecycle.appear()"))
        XCTAssertTrue(source.contains("focusLifecycle.end()"))
        let home = try String(contentsOf: app.appendingPathComponent("LittleSaver/Views/HomeView.swift"))
        XCTAssertTrue(home.contains("appLockVM.canHandleDeepLinks"))
        let budgets = try String(contentsOf: app.appendingPathComponent("LittleSaver/Views/BudgetView.swift"))
        XCTAssertEqual(budgets.components(separatedBy: "NavigationLink(isActive:").count - 1, 1)
        XCTAssertFalse(budgets.contains("NavigationLink(destination: DetailedBudgetView"))
        XCTAssertFalse(budgets.contains("NavigationLink(destination: DetailedMainBudgetView"))
        XCTAssertTrue(budgets.contains("model.value(for: environment)"))
        for file in ["BudgetWidget.swift", "LockBudgetWidget.swift"] {
            let widget = try String(contentsOf: app.appendingPathComponent("LittleSaverWidget/" + file))
            XCTAssertTrue(widget.contains("HoldingBudget(id: snapshot.id"))
            XCTAssertFalse(widget.contains("DeepLink.budget(name: entry.budget.name)"))
        }
    }

    @MainActor
    func testBudgetNavigationUsesReadySnapshotIdentityAndConsumesEachRequestOnce() async throws {
        let controller = try DataController(configuration: .inMemory)
        try await controller.waitUntilReady()
        let context = controller.container.viewContext
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func budget(_ name: String, valid: Bool = true) -> Budget {
            let category = Category(context: context); category.id = UUID(); category.name = name; category.income = false
            let budget = Budget(context: context); budget.id = UUID(); budget.category = category
            budget.type = valid ? 3 : 0; budget.amount = 100; budget.startDate = now
            return budget
        }
        let first = budget("Food"); let other = budget("Other")
        try context.save()
        let id = try XCTUnwrap(first.id)
        let environment = AnalyticsEnvironment(stamp: AnalyticsStamp(now: now))
        var snapshot = try await controller.budgetDashboardSnapshot(environment: environment)
        var navigation = BudgetNavigationState()
        let request = BudgetNavigationRequest(target: .uuid(id))
        navigation.resolve(request, snapshot: nil)
        XCTAssertNil(navigation.consumedRequest)
        navigation.resolve(request, snapshot: snapshot)
        XCTAssertEqual(navigation.reference, first.objectID.uriRepresentation())
        navigation.dismiss(); navigation.resolve(request, snapshot: snapshot)
        XCTAssertNil(navigation.reference, "A refresh must not push the consumed link again")
        navigation.select(other.objectID.uriRepresentation())
        navigation.resolve(BudgetNavigationRequest(target: .uuid(id)), snapshot: snapshot)
        XCTAssertEqual(navigation.reference, first.objectID.uriRepresentation(), "Warm link replaces manual selection through the same state")
        first.category?.name = "Renamed"; try context.save()
        snapshot = try await controller.budgetDashboardSnapshot(environment: environment)
        navigation.resolve(BudgetNavigationRequest(target: .uuid(id)), snapshot: snapshot)
        XCTAssertEqual(navigation.reference, first.objectID.uriRepresentation())
        navigation.resolve(BudgetNavigationRequest(target: .legacyName("Food")), snapshot: snapshot)
        XCTAssertTrue(navigation.unavailable); XCTAssertNil(navigation.reference)
        let invalid = budget("Renamed", valid: false); try context.save()
        snapshot = try await controller.budgetDashboardSnapshot(environment: environment)
        XCTAssertNil(snapshot.budgets.first { $0.businessID == invalid.id }?.read)
        navigation.resolve(BudgetNavigationRequest(target: .legacyName("Renamed")), snapshot: snapshot)
        XCTAssertTrue(navigation.unavailable, "Invalid same-name rows still make a legacy target ambiguous")
        invalid.id = id; try context.save()
        snapshot = try await controller.budgetDashboardSnapshot(environment: environment)
        navigation.resolve(BudgetNavigationRequest(target: .uuid(id)), snapshot: snapshot)
        XCTAssertTrue(navigation.unavailable)
        context.delete(first); context.delete(invalid); try context.save()
        _ = budget("Renamed"); try context.save()
        snapshot = try await controller.budgetDashboardSnapshot(environment: environment)
        navigation.resolve(BudgetNavigationRequest(target: .uuid(id)), snapshot: snapshot)
        XCTAssertTrue(navigation.unavailable); XCTAssertNil(navigation.reference, "Missing UUID never falls back to another same-name budget")
        navigation.resolve(BudgetNavigationRequest(target: .legacyName("Renamed")), snapshot: snapshot)
        XCTAssertFalse(navigation.unavailable); XCTAssertNotNil(navigation.reference)
    }

    @MainActor
    func testBudgetRouteRemainsPendingUntilActiveSuccessfulUnlock() async {
        let prefs = UserDefaults(suiteName: "T8-\(UUID().uuidString)")!
        prefs.set(true, forKey: "appLockEnabled")
        let context = FakeOwnerContext()
        let model = AppLockViewModel(preferences: prefs, contextFactory: { context })
        var router = DeepLinkRouter()
        let route = DeepLink.budgetUUID(UUID())
        XCTAssertNil(router.receive(route, isLocked: !model.canHandleDeepLinks))
        model.appLockValidation(); model.sceneChanged(.inactive)
        context.callbacks[0](true, nil); await settleCallbacks()
        XCTAssertFalse(model.canHandleDeepLinks); XCTAssertEqual(router.pendingLink, route)
        model.sceneChanged(.active)
        XCTAssertTrue(model.canHandleDeepLinks); XCTAssertEqual(router.unlock(), route); XCTAssertNil(router.unlock())
    }

    @MainActor
    func testOwnerAuthenticationDoesNotPreflightBiometricsAndCoalescesRequests() {
        let preferences = UserDefaults(suiteName: "T8-\(UUID().uuidString)")!
        preferences.set(true, forKey: "appLockEnabled")
        let context = FakeOwnerContext()
        let model = AppLockViewModel(preferences: preferences, contextFactory: { context })
        model.appLockValidation(); model.appLockValidation()
        XCTAssertEqual(context.policies, [.deviceOwnerAuthentication])
        XCTAssertTrue(context.preflightPolicies.isEmpty)
        XCTAssertFalse(model.isAppUnLocked)
    }

    func testBudgetUUIDDeepLinkRejectsMalformedMixedAndDuplicateTargets() {
        let id = UUID()
        XCTAssertEqual(DeepLink(url: DeepLink.budgetUUID(id).url), .budgetUUID(id))
        XCTAssertEqual(DeepLink(url: DeepLink.budget(name: nil).url), .budget(name: nil))
        XCTAssertNotNil(DeepLink(url: URL(string: "\(AppIdentifiers.urlScheme)://budget?budgetUUID=\(id.uuidString)")!))
        for query in ["budgetUUID=bad", "budgetUUID=\(id)&budget=Food", "budgetUUID=\(id)&budgetUUID=\(id)", "budget", "unknown=1", "budgetUUID=\(id)#fragment"] {
            XCTAssertNil(DeepLink(url: URL(string: "\(AppIdentifiers.urlScheme)://budget?\(query)")!))
        }
    }
}

private final class FakeOwnerContext: OwnerAuthenticationContext {
    var preflightPolicies: [LAPolicy] = []
    var policies: [LAPolicy] = []
    var callbacks: [@Sendable (Bool, Error?) -> Void] = []
    var invalidated = false
    var onInvalidate: (() -> Void)?
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { preflightPolicies.append(policy); return true }
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) { policies.append(policy); callbacks.append(reply) }
    func invalidate() { invalidated = true; onInvalidate?() }
}
