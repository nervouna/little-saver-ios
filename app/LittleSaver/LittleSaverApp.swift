//
//  LittleSaverApp.swift
//  LittleSaver
//
//  Created by Rafael Soh on 11/7/22.
//

import SwiftUI

@main
struct LittleSaverApp: App {
    @StateObject var dataController: DataController
    @StateObject var appLockVM = AppLockViewModel()
    @StateObject var tabBarManager = TabBarManager()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.isRunningUnitTests {
                EmptyView()
            } else {
                switch dataController.persistentStoreState {
                case .loading:
                    ProgressView("Preparing data…")
                case .loaded:
                    ContentView()
                        .environment(\.managedObjectContext, dataController.container.viewContext)
                        .environmentObject(appLockVM)
                        .environmentObject(dataController)
                        .environmentObject(tabBarManager)
                case let .failed(message):
                    StorageUnavailableView(message: message)
                }
            }
        }
    }

    init() {
        let dataController = DataController.shared
//        let dataController = DataController()

        _dataController = StateObject(wrappedValue: dataController)

        UITableView.appearance().backgroundColor = .clear
    }
}

private struct StorageUnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.largeTitle)
            Text("Unable to Open Data")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
