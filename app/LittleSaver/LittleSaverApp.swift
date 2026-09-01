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
    @StateObject var unlockManager: UnlockManager
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
                    ProgressView("正在准备数据…")
                case .loaded:
                    ContentView()
                        .environment(\.managedObjectContext, dataController.container.viewContext)
                        .environmentObject(appLockVM)
                        .environmentObject(dataController)
                        .environmentObject(unlockManager)
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
        let unlockManager = UnlockManager(dataController: dataController)

        _dataController = StateObject(wrappedValue: dataController)
        _unlockManager = StateObject(wrappedValue: unlockManager)

        UITableView.appearance().backgroundColor = .clear
    }
}

private struct StorageUnavailableView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.largeTitle)
            Text("无法打开数据")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
