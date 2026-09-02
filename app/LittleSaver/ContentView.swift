//
//  ContentView.swift
//
//  Created by Rafael Soh on 3/6/22.
//

import LittleSaverCore
import SwiftUI
import WidgetKit

struct ContentView: View {
    @EnvironmentObject var appLockVM: AppLockViewModel
    @EnvironmentObject var dataController: DataController

    @AppStorage("colourScheme", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var colourScheme: Int = 0
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("showNotifications", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showNotifications: Bool = false
    @AppStorage("notificationsEnabled", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var notificationsEnabled: Bool = true

    @AppStorage("firstLaunch", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var firstLaunch: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = Locale.current.currencyCode!

    @State var showIntro: Bool = false

    var center = UNUserNotificationCenter.current()

    @AppStorage("topEdge", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var savedTopEdge: Double = 30
    @AppStorage("bottomEdge", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var savedBottomEdge: Double = 15

    var body: some View {
        GeometryReader { proxy in
            let topEdge = proxy.safeAreaInsets.top
            let bottomEdge = proxy.safeAreaInsets.bottom

            HomeView(topEdge: topEdge, bottomEdge: bottomEdge == 0 ? 15 : bottomEdge)
                .ignoresSafeArea(.all, edges: .bottom)
                .preferredColorScheme(colourScheme == 1 ? .light : colourScheme == 2 ? .dark : nil)
                .fullScreenCover(isPresented: $showIntro) {
                    WelcomeSheetView()
                }
                .onAppear {
                    savedTopEdge = topEdge
                    savedBottomEdge = bottomEdge
                }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
//            UserDefaults(suiteName: AppIdentifiers.appGroup)!.set(false, forKey: "newTransactionAdded")
//            WidgetCenter.shared.reloadTimelines(ofKind: "TemplateTransactions")

            if appLockVM.isAppLockEnabled {
                appLockVM.appLockValidation()
            }

            let defaults =
                UserDefaults(suiteName: AppIdentifiers.appGroup) ?? UserDefaults.standard

            if defaults.object(forKey: "firstDayOfMonth") == nil {
                defaults.set(1, forKey: "firstDayOfMonth")
            }

            if firstLaunch {
                showIntro = true
                firstLaunch = false

                defaults.set(1, forKey: "firstWeekday")
                defaults.set(1, forKey: "haptics")
                defaults.set(1, forKey: "firstDayOfMonth")
                defaults.set(1, forKey: "notificationOption")
                defaults.set(false, forKey: "confetti")
                defaults.set(false, forKey: "chromatic")
                defaults.set(true, forKey: "showCents")
                defaults.set(true, forKey: "animated")

                if NSUbiquitousKeyValueStore.default.string(forKey: "currency") == nil {
                    NSUbiquitousKeyValueStore.default.set(Locale.current.currencyCode!, forKey: "currency")
                } else {
                    currency = NSUbiquitousKeyValueStore.default.string(forKey: "currency")!
                }

                defaults.set(2, forKey: "numberEntryType")
            } else {
                if let holdingCurrency = NSUbiquitousKeyValueStore.default.string(forKey: "currency") {
                    currency = holdingCurrency
                } else {
                    currency = Locale.current.currencyCode!
                    NSUbiquitousKeyValueStore.default.set(Locale.current.currencyCode!, forKey: "currency")
                }
            }

            center.getNotificationSettings { settings in
                if settings.authorizationStatus == .authorized {
                    if !showNotifications && notificationsEnabled == false {
                        showNotifications = true
                        notificationsEnabled = true
                        newNotification()
                    }
                } else if settings.authorizationStatus == .denied {
                    notificationsEnabled = false

                    if showNotifications {
                        showNotifications = false
                        center.removeAllPendingNotificationRequests()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            appLockVM.sceneChanged(newPhase)
            if newPhase == .active {
                Task { try? await dataController.refreshPersistentHistory() }
                center.getNotificationSettings { settings in
                    if settings.authorizationStatus == .authorized {
                        if !showNotifications && notificationsEnabled == false {
                            showNotifications = true
                            notificationsEnabled = true
                            newNotification()
                        }
                    } else if settings.authorizationStatus == .denied {
                        notificationsEnabled = false

                        if showNotifications {
                            showNotifications = false
                            center.removeAllPendingNotificationRequests()
                        }
                    }
                }
            }
        }
    }
}
