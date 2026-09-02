import CoreData
import LittleSaverCore
import SwiftUI

@propertyWrapper
struct AnalyticsInput: DynamicProperty {
    @EnvironmentObject private var controller: DataController
    @AppStorage("firstWeekday", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) private var firstWeekday = 1
    @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) private var firstDayOfMonth = 1
    var wrappedValue: AnalyticsEnvironment {
        AnalyticsEnvironment(stamp: controller.analyticsStamp, firstWeekday: firstWeekday, firstDayOfMonth: firstDayOfMonth)
    }
}

private struct LedgerMetadataKey: EnvironmentKey {
    static let defaultValue: LedgerMetadataSnapshot? = nil
}

extension EnvironmentValues {
    var ledgerMetadata: LedgerMetadataSnapshot? {
        get { self[LedgerMetadataKey.self] }
        set { self[LedgerMetadataKey.self] = newValue }
    }
}

@MainActor
struct AnalyticsReadView<Key: Hashable, Value: Sendable, Content: View>: View {
    let key: Key
    let load: (Key) async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @StateObject private var model = SnapshotModel<Key, Value>()

    var body: some View {
        AnalyticsResultView(model: model, key: key, load: load, content: content)
    }
}

@MainActor
struct AnalyticsResultView<Key: Hashable, Value: Sendable, Content: View>: View {
    @ObservedObject var model: SnapshotModel<Key, Value>
    let key: Key
    let load: (Key) async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        ZStack {
            // Keep editor/search/period-selection containers mounted during refresh.
            // A previous request's values are hidden, never labeled as the new result.
            if let value = model.value {
                content(value)
                    .opacity(model.value(for: key) == nil ? 0 : 1)
                    .allowsHitTesting(model.value(for: key) != nil)
                    .accessibilityHidden(model.value(for: key) == nil)
            }
            if let error = model.error {
                VStack(spacing: 8) {
                    Text(error).font(.callout).multilineTextAlignment(.center)
                    Button("Retry") { Task { await model.load(key: key, using: load) } }
                }.padding()
            } else if model.value(for: key) == nil { ProgressView().padding() }
        }
        .task(id: key) { await model.load(key: key, using: load) }
    }
}

@MainActor
func presentationObject<T: NSManagedObject>(_ reference: URL, in context: NSManagedObjectContext, as type: T.Type = T.self) -> T? {
    guard let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: reference),
          let object = try? context.existingObject(with: id) as? T, !object.isDeleted else { return nil }
    return object
}

struct SnapshotTransactionsView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    let query: LedgerListQuery
    var fullscreen = false
    var dayHeaders = true

    var body: some View {
        AnalyticsReadView(key: LedgerListRequest(query: query, environment: environment), load: controller.ledgerListSnapshot) { snapshot in
            if snapshot.rows.isEmpty { NoResultsView(fullscreen: fullscreen) }
            else { ListView(snapshot: snapshot, dayHeaders: dayHeaders) }
        }
    }
}

func formattedLedgerNet(_ amount: Double, currency: String, showCents: Bool) -> String {
    guard amount.isFinite else { return String(localized: "Amount unavailable") }
    let formatted = localizedCurrencyAmount(amount, currencyCode: currency, showCents: showCents)
    return amount >= 0 ? "+" + formatted : formatted
}
