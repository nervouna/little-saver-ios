//
//  SettingsCloudView.swift
//  LittleSaver
//

import SwiftUI

#if !targetEnvironment(simulator)
import CloudKitSyncMonitor
import Combine

@MainActor
private final class CloudSyncStatusModel: ObservableObject {
  @Published private(set) var status = "Checking…"
  private var monitor: SyncMonitor?
  private var monitorChange: AnyCancellable?

  func start() {
    guard monitor == nil,
          !ProcessInfo.processInfo.isRunningUnitTests,
          Bundle.main.bundleIdentifier == AppIdentifiers.appBundle else {
      status = "Unavailable"
      return
    }

    let monitor = SyncMonitor.shared
    self.monitor = monitor
    update(from: monitor)
    monitorChange = monitor.objectWillChange.sink { [weak self, weak monitor] _ in
      DispatchQueue.main.async {
        guard let self, let monitor else { return }
        self.update(from: monitor)
      }
    }
  }

  private func update(from monitor: SyncMonitor) {
    switch monitor.syncStateSummary {
    case .noNetwork: status = "Waiting for network"
    case .accountNotAvailable: status = "iCloud unavailable"
    case .error: status = "Sync error"
    case .notSyncing: status = "Not syncing"
    case .notStarted: status = "Ready"
    case .inProgress: status = "Syncing…"
    case .succeeded: status = "Up to date"
    case .unknown: status = "Status unavailable"
    }
  }
}
#endif

struct SettingsCloudView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  #if !targetEnvironment(simulator)
  @StateObject private var statusModel = CloudSyncStatusModel()
  #endif

  var body: some View {
    VStack(spacing: 10) {
      Text("iCloud Sync")
        .font(.system(.title3, design: .rounded).weight(.semibold))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundColor(Color.PrimaryText)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
          Button {
            presentationMode.wrappedValue.dismiss()
          } label: {
            SettingsBackButton()
          }
        }
        .padding(.bottom, 20)

      HStack {
        Text("Status")
          .font(.system(.body, design: .rounded))
          .foregroundColor(Color.PrimaryText)
        Spacer()
        Text(statusText)
          .font(.system(.body, design: .rounded))
          .foregroundColor(Color.SubtitleText)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 15)
      .padding(.vertical, 12)
      .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))

      Text("Sync is automatic. When iCloud or the network is unavailable, changes remain on this device and retry later.")
        .font(.system(.caption, design: .rounded).weight(.medium))
        .multilineTextAlignment(.leading)
        .foregroundColor(Color.SubtitleText)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #if !targetEnvironment(simulator)
    .onAppear { statusModel.start() }
    #endif
    .modifier(SettingsSubviewModifier())
  }

  private var statusText: String {
    #if targetEnvironment(simulator)
    return "Unavailable in Simulator"
    #else
    return statusModel.status
    #endif
  }
}
