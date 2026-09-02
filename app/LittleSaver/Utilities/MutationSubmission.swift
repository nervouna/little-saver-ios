import LittleSaverCore
import SwiftUI
import UIKit

/// A single UI submission gate prevents duplicate taps while retaining all form state
/// until a throwing command has actually committed and merged.
@MainActor
final class MutationSubmissionState: ObservableObject {
    @Published private(set) var pending = false
    @Published private(set) var error: Error?

    @discardableResult
    func submit<T>(operation: @escaping () async throws -> T, success: @escaping (T) -> Void, failure: @escaping (Error) -> Void) -> Task<Void, Never>? {
        guard !pending else {
            failure(LedgerCommandError.submissionPending)
            return nil
        }
        pending = true
        error = nil
        return Task { @MainActor in
            defer { pending = false }
            do { success(try await operation()) }
            catch { self.error = error; failure(error) }
        }
    }
}

struct MutationPendingModifier: ViewModifier {
    @ObservedObject private var state = MutationPresentation.state
    func body(content: Content) -> some View {
        content
            .disabled(state.pending)
            .allowsHitTesting(!state.pending)
            .interactiveDismissDisabled(state.pending)
    }
}

@MainActor
enum MutationPresentation {
    static let state = MutationSubmissionState()
    static func show(_ error: Error) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var presenter = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let alert = UIAlertController(title: String(localized: "Unable to Save"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        presenter.present(alert, animated: true)
    }
}


extension DataController {
    @MainActor
    func submitMutation<T>(_ operation: @escaping () async throws -> T, success: @escaping (T) -> Void = { _ in }, failure: ((Error) -> Void)? = nil) {
        MutationPresentation.state.submit(operation: operation, success: success, failure: failure ?? MutationPresentation.show)
    }
}
