//
//  HomeView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import ConfettiSwiftUI
import Foundation
import SwiftUI

class OverallToastPresenter: ObservableObject {
    @Published var showToast: Bool = false
}

enum DeletionType {
    case instant
    case prompt
}

class OverallTransactionManager: ObservableObject {
    @Published var toEdit: Transaction?
    @Published var toDelete: Transaction?
    @Published var deletionSnapshot: TransactionDeletionSnapshot?
    @Published var showToast: Bool = false
    @Published var showPopup: Bool = false
    @Published var future: Bool = false
}

private struct LedgerCalendarRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var ledgerCalendarRevision: Int {
        get { self[LedgerCalendarRevisionKey.self] }
        set { self[LedgerCalendarRevisionKey.self] = newValue }
    }
}

struct HomeView: View {
    @AnalyticsInput private var analytics
    @StateObject private var metadata = SnapshotModel<AnalyticsEnvironment, LedgerMetadataSnapshot>()
    @State private var calendarRevision = 0
    @EnvironmentObject var appLockVM: AppLockViewModel

    @StateObject var toastPresenter = OverallToastPresenter()
    @StateObject var transactionManager = OverallTransactionManager()
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    @State var currentTab = "Log"

    var topEdge: CGFloat
    var bottomEdge: CGFloat

    @State private var deepLinkRouter = DeepLinkRouter()
    @State private var budgetRequest: BudgetNavigationRequest?

    @State var launchAdd: Bool = false
    @State var launchSearch: Bool = false

    @State var counter = 0

    @EnvironmentObject var tabBarManager: TabBarManager

    @State var showPopup = false

    // Hiding Native TabBar...
    init(topEdge: CGFloat, bottomEdge: CGFloat) {
        UITabBar.appearance().isHidden = true
        self.topEdge = topEdge
        self.bottomEdge = bottomEdge
    }

    var body: some View {
        content.modifier(MutationPendingModifier())
            .environment(\.ledgerCalendarRevision, calendarRevision)
            .environment(\.ledgerMetadata, metadata.value)
            .task(id: analytics) { await metadata.load(key: analytics, using: dataController.ledgerMetadataSnapshot) }
            .overlay(alignment: .top) {
                if let error = metadata.error {
                    VStack {
                        Text(error).font(.callout)
                        Button("Retry") { dataController.refreshAnalytics() }
                    }.padding().background(Color.PrimaryBackground)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshCalendar() }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in refreshCalendar() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshCalendar() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refreshCalendar() }
    }

    private func refreshCalendar() {
        calendarRevision += 1
        dataController.refreshAnalytics()
    }

    @ViewBuilder private var content: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentTab) {
                LogView(topEdge: topEdge, bottomEdge: bottomEdge, launchSearch: launchSearch)
                    .ignoresSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag("Log")

                InsightsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag("Insights")

                BudgetView(request: budgetRequest)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag("Budget")

                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag("Settings")
            }
            .allowsHitTesting(showPopup ? false : true)
            .environmentObject(toastPresenter)
            .environmentObject(transactionManager)

            CustomTabBar(currentTab: $currentTab, topEdge: topEdge, bottomEdge: bottomEdge, counter: $counter, launchAdd: launchAdd)
                .offset(y: tabBarManager.hideTab ? (70 + bottomEdge) : 0)

            if showPopup {
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        transactionManager.showPopup = false
                    }
            }

            DeleteTransactionAlert()
                .offset(y: showPopup ? 0 : 300)
                .environmentObject(transactionManager)

            if appLockVM.protectsContent {
                AppLockView()
                    .ignoresSafeArea(.all)
            }
        }
        .toast(isPresenting: $toastPresenter.showToast, duration: 4, tapToDismiss: true, offsetY: 12, alert: {
            AlertToast(displayMode: .hud, type: .systemImage("checkmark.circle.fill", Color.IncomeGreen), title: "Image Saved", subTitle: "Check it out in Photos")
        })
        .toast(isPresenting: $transactionManager.showToast, duration: 4, tapToDismiss: true, offsetY: 12, alert: {
            AlertToast(displayMode: .hud, type: .systemImage("arrow.uturn.backward.circle.fill", Color.AlertRed), title: "Log Deleted", subTitle: "Tap to Undo")
        }, onTap: {
            guard let snapshot = transactionManager.deletionSnapshot else { return }
            dataController.submitMutation({
                try await dataController.restoreTransaction(snapshot)
            }, success: {
                transactionManager.deletionSnapshot = nil
            }, failure: { error in
                MutationPresentation.show(error)
                transactionManager.showToast = true
            })
        })
        .onChange(of: transactionManager.showPopup) { newValue in
            withAnimation {
                showPopup = newValue
            }
        }
        .fullScreenCover(item: $transactionManager.toEdit, onDismiss: {
            transactionManager.toEdit = nil
        }) { transaction in
            TransactionView(toEdit: transaction)
        }
        .confettiCannon(counter: $counter, num: 50, openingAngle: Angle(degrees: 0), closingAngle: Angle(degrees: 360), radius: 200)
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            let isLocked = !appLockVM.canHandleDeepLinks
            if let route = deepLinkRouter.receive(link, isLocked: isLocked) {
                handle(route)
            }
        }
        .onChange(of: appLockVM.canHandleDeepLinks) { canHandle in
            guard canHandle, let route = deepLinkRouter.unlock() else { return }
            handle(route)
        }
    }

    private func handle(_ link: DeepLink) {
        switch link {
        case .search:
            currentTab = "Log"
            launchSearch.toggle()
        case .newExpense:
            launchAdd.toggle()
        case .insights:
            currentTab = "Insights"
        case let .budget(name):
            budgetRequest = name.map { BudgetNavigationRequest(target: .legacyName($0)) }
            currentTab = "Budget"
        case let .budgetUUID(id):
            budgetRequest = BudgetNavigationRequest(target: .uuid(id))
            currentTab = "Budget"
        }
    }
}

struct AppLockView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "lock.fill")
                .font(.system(size: 65))
                .foregroundColor(Color.DarkIcon.opacity(0.7))

            Text("App Locked")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .padding(.bottom, 30)

            Button {
                appLockVM.appLockValidation()
            } label: {
                HStack {
                    Image(systemName: "lock.open")

                    Text("Unlock App")
                }
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.Outline)
                }
            }

            if appLockVM.isPending { ProgressView() }
            if let message = appLockVM.errorMessage {
                Text(message)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)
                    .multilineTextAlignment(.center)
            }
            if appLockVM.offersSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
    }
}
