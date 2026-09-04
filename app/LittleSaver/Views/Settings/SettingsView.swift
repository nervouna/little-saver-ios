//
//  SettingsView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Combine
import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

struct SettingsView: View {
  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  @AppStorage("colourScheme", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var colourScheme: Int = 0
  var colourSchemeString: String {
    if colourScheme == 1 {
      return String(localized: "Light")
    } else if colourScheme == 2 {
      return String(localized: "Dark")
    } else {
      return String(localized: "System")
    }
  }

  @AppStorage("firstWeekday", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var firstWeekday: Int = 1
  var firstWeekdayString: String {
    if firstWeekday == 1 {
      return String(localized: "Sunday")
    } else {
      return String(localized: "Monday")
    }
  }

  @AppStorage("showNotifications", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var showNotifications: Bool = false
  @AppStorage("notificationOption", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var option: Int = 1
  var notificationString: String {
    if showNotifications {
      if option == 1 {
        return String(localized: "Mornings")
      } else if option == 2 {
        return String(localized: "Evenings")
      } else {
        return String(localized: "Custom")
      }
    } else {
      return String(localized: "Off")
    }
  }

  @EnvironmentObject var appLockVM: AppLockViewModel
  @Namespace var animation

  @Environment(\.openURL) var openURL

  @AppStorage("numberEntryType", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var numberEntryType: Int = 2

  var numberEntryString: String {
    if numberEntryType == 1 {
      return String(localized: "Type 1")
    } else {
      return String(localized: "Type 2")
    }
  }

  @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var showCents: Bool = true

  @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated:
    Bool = true

  @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency:
    String = Locale.current.currencyCode!

  @AppStorage("incomeTracking", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var incomeTracking: Bool = true
    
  @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var showExpenseOrIncomeSign: Bool = true

  @AppStorage(
    "showUpcomingTransactions", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
  var showUpcoming: Bool = true

  var upcomingString: String {
    if showUpcoming {
      return String(localized: "Shown")
    } else {
      return String(localized: "Hidden")
    }
  }

    @AppStorage("haptics", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
    var hapticType: Int = 1

    var hapticString: String {
      if hapticType == 0 {
        return String(localized: "None")
      } else if hapticType == 1 {
        return String(localized: "Subtle")
      } else {
        return String(localized: "Excessive")
      }
    }

  // popups

  @State var showImportGuide = false
  @StateObject private var exportPreparation = CSVExportPreparation()

  @EnvironmentObject var tabBarManager: TabBarManager

  @EnvironmentObject var dataController: DataController

  var body: some View {
    NavigationView {
      VStack {
        HStack {
          Text("Settings")
            .font(.system(.title, design: .rounded).weight(.semibold))

            //                        .font(.system(size: 25, weight: .semibold, design: .rounded))
            .accessibility(addTraits: .isHeader)
          Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
        .padding(.bottom, 10)

        ScrollView(showsIndicators: false) {
          VStack(spacing: 5) {
            Text("GENERAL")
              .font(.system(.footnote, design: .rounded).weight(.semibold))

              //                            .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundColor(Color.SubtitleText)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 13) {

              NavigationLink(destination: SettingsNotificationsView()) {
                SettingsRowView(
                  systemImage: "bell.fill", title: "Notifications", colour: 102,
                  optionalText: notificationString)
              }

              NavigationLink(destination: SettingsCurrencyView()) {
                SettingsRowView(
                  systemImage: "coloncurrencysign.square.fill", title: "Currency", colour: 103,
                  optionalText: currency)
              }

              NavigationLink(
                destination: SettingsNumberEntryView()
                  .onAppear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationHideTab()
                    }
                  }
                  .onDisappear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationShowTab()
                    }
                  }
              ) {
                SettingsRowView(
                  systemImage: "keyboard.fill", title: "Number Entry", colour: 104,
                  optionalText: numberEntryString)
              }

              ToggleRow(
                icon: "lock.fill", color: "105", text: "Authentication",
                bool: appLockVM.isAppLockEnabled,
                onTap: {
                  appLockVM.appLockStateChange(appLockState: !appLockVM.isAppLockEnabled)
                })
                .disabled(appLockVM.isPending)
              if appLockVM.isPending { ProgressView() }
              if let message = appLockVM.errorMessage { Text(message).font(.callout).foregroundColor(Color.SubtitleText) }
              if appLockVM.offersSettings {
                Button("Open Settings") {
                  if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
              }

              ToggleRow(
                icon: "banknote.fill", color: "106", text: "Income Tracking", bool: incomeTracking,
                onTap: {
                  incomeTracking.toggle()

                  if !incomeTracking {
                    UserDefaults(suiteName: AppIdentifiers.appGroup)!.set(
                      false, forKey: "insightsViewIncomeFiltering")
                    UserDefaults(suiteName: AppIdentifiers.appGroup)!.set(
                      3, forKey: "logInsightsType")
                  }
                })

              NavigationLink(destination: SettingsWeekStartView()) {
                SettingsRowView(systemImage: "calendar", title: "Time Frames", colour: 109)
              }
                
            }
            .padding(10)
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 25)
          .onChange(of: currency) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: firstWeekday) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: showCents) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }

          VStack(spacing: 5) {
            Text("APPEARANCE")
              .font(.system(.footnote, design: .rounded).weight(.semibold))

              //                            .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundColor(Color.SubtitleText)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 13) {
              NavigationLink(destination: SettingsAppearanceView()) {
                SettingsRowView(
                  systemImage: "circle.righthalf.filled", title: "Theme", colour: 100,
                  optionalText: colourSchemeString)
              }

              ToggleRow(
                icon: "centsign.circle.fill", color: "107", text: "Display Cents", bool: showCents,
                onTap: {
                  showCents.toggle()
                })

              NavigationLink(destination: SettingsUpcomingView()) {
                SettingsRowView(
                  systemImage: "sun.min.fill", title: "Upcoming Logs", colour: 108,
                  optionalText: upcomingString)
              }
                
              ToggleRow(
                icon: "plusminus", color: "123", text: "Display +/- Symbol", bool: showExpenseOrIncomeSign,
                onTap: {
                    showExpenseOrIncomeSign.toggle()
                })

              ToggleRow(
                icon: "hare.fill", color: "121", text: "Animated Charts", bool: animated, smaller: true,
                onTap: {
                  animated.toggle()
                })

            }
            .padding(10)
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 25)
          .onChange(of: currency) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: firstWeekday) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: showCents) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }

          VStack(spacing: 5) {
            Text("DATA")
              .font(.system(.footnote, design: .rounded).weight(.semibold))

              //                            .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundColor(Color.SubtitleText)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 13) {
              NavigationLink(
                destination: SettingsCategoryView()
                  .onAppear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationHideTab()
                    }
                  }
                  .onDisappear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationShowTab()
                    }
                  }

              ) {
                SettingsRowView(
                  systemImage: "rectangle.grid.2x2.fill", title: "Categories", colour: 110)
              }

              NavigationLink(destination: SettingsCloudView()) {
                SettingsRowView(
                  systemImage: "icloud.fill", title: "iCloud Sync", colour: 111,
                  optionalText: String(localized: "Status"))
              }

              //
              //                            NavigationLink(destination: SettingsQuickAddWidgetView()) {
              //                                SettingsRowView(systemImage: "bolt.square.fill", title: "Quick-Add Widget", colour: 115)
              //                            }

              Button {
                showImportGuide = true
              } label: {
                SettingsRowView(
                  systemImage: "square.and.arrow.down.fill", title: "Import Data", colour: 112)
              }

              Button {
                Task { await exportPreparation.prepare { try await CSVExportFile.prepare(read: dataController.csvExportText) } }
              } label: {
                SettingsRowView(
                  systemImage: "square.and.arrow.up.fill", title: "Export Data", colour: 113)
              }
              .disabled(exportPreparation.isPreparing)
              .overlay(alignment: .trailing) {
                if exportPreparation.isPreparing { ProgressView().padding(.trailing, 12) }
              }

              NavigationLink(destination: SettingsEraseView()) {
                SettingsRowView(systemImage: "xmark.bin.fill", title: "Erase Data", colour: 114)
              }
            }
            .padding(10)
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 25)

          VStack(spacing: 5) {
            Text("OTHERS")
              .font(.system(.footnote, design: .rounded).weight(.semibold))

              //                            .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundColor(Color.SubtitleText)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 13) {

                NavigationLink(destination: SettingsHapticsView()) {
                  SettingsRowView(
                    systemImage: "hand.tap.fill", title: "Haptics", colour: 100,
                    optionalText: hapticString)
                }

              NavigationLink(destination: SettingsGoofyView()) {
                SettingsRowView(systemImage: "flame.fill", title: "Feature Lab", colour: 122)
              }

              Button {
                if let url = URL(string: "https://github.com/nervouna/little-saver-ios") {
                  openURL(url)
                }
              } label: {
                SettingsRowView(
                  systemImage: "chevron.left.forwardslash.chevron.right", title: "Source Code", colour: 123)
              }

              Button {
                if let url = URL(string: "https://github.com/nervouna/little-saver-ios/issues") {
                  openURL(url)
                }
              } label: {
                SettingsRowView(systemImage: "ladybug.fill", title: "GitHub Issues", colour: 124)
              }

              NavigationLink(destination: PrivacyPolicyView()) {
                SettingsRowView(systemImage: "hand.raised.fill", title: "Privacy", colour: 125)
              }

              NavigationLink(destination: OpenSourceLicensesView()) {
                SettingsRowView(systemImage: "doc.text.fill", title: "Open Source Licenses", colour: 126)
              }
            }
            .padding(10)
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 15)

          VStack(spacing: 5) {
            Text("Version \(UIApplication.appVersion ?? "") (\(UIApplication.buildNumber ?? ""))")
              .font(.system(.footnote, design: .rounded).weight(.medium))
              .foregroundColor(Color.SubtitleText)

            Text("Based on the open-source Dime project")
              .font(.system(.footnote, design: .rounded).weight(.medium))

              .foregroundColor(Color.SubtitleText)
              .multilineTextAlignment(.center)
          }
          .padding(.horizontal, 25)
          .padding(.bottom, 95)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      }
      .navigationBarTitle("")
      .navigationBarHidden(true)
      .background(Color.PrimaryBackground)
      .fullScreenCover(isPresented: $showImportGuide) {
        ImportDataView()
      }
      .sheet(isPresented: Binding(get: { exportPreparation.url != nil }, set: { if !$0 { exportPreparation.clear() } })) {
        if let url = exportPreparation.url { ActivityViewController(activityItems: [url]) }
      }
      .alert("Export Failed", isPresented: Binding(get: { exportPreparation.error != nil }, set: { if !$0 { exportPreparation.clear() } })) {
        Button("OK") { exportPreparation.clear() }
      } message: { Text(exportPreparation.error ?? "") }
    }
  }

  @ViewBuilder
    func ToggleRow(icon: String, color: String, text: String, bool: Bool, smaller: Bool = false, onTap: @escaping () -> Void)
    -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
            .font(.system(smaller ? .subheadline : .body, design: .rounded))
        .foregroundColor(.white)
        .frame(
          width: dynamicTypeSize > .xLarge ? 40 : 30, height: dynamicTypeSize > .xLarge ? 40 : 30,
          alignment: .center
        )
        .background(Color(color), in: RoundedRectangle(cornerRadius: 6))

      Text(LocalizedStringKey(text))
        .font(.system(.body, design: .rounded).weight(.medium))
        .lineLimit(1)
        .foregroundColor(Color.PrimaryText)

      Spacer()

      ZStack(alignment: bool ? .trailing : .leading) {
        Capsule()
          .frame(width: 42, height: 28)
          .foregroundColor(bool ? .green : .gray.opacity(0.8))

        Circle()
          .foregroundColor(Color.white)
          .padding(2)
          .frame(width: 28, height: 28)
          .matchedGeometryEffect(id: "toggle\(color)", in: animation)
      }
      .onTapGesture {
        withAnimation {
          onTap()
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

}

struct SettingsRowView: View {
  var systemImage: String
  var title: String
  var colour: Int
  var optionalText: String?

  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(.body, design: .rounded))

        //                .font(.system(size: 17))
        //                .padding(5)
        .foregroundColor(.white)
        .frame(
          width: dynamicTypeSize > .xLarge ? 40 : 30, height: dynamicTypeSize > .xLarge ? 40 : 30,
          alignment: .center
        )
        .background(Color("\(colour)"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

      Text(LocalizedStringKey(title))
        .font(.system(.body, design: .rounded).weight(.medium))

        //                .font(.system(size: 17, weight: .medium, design: .rounded))
        .lineLimit(1)
        .foregroundColor(Color.PrimaryText)

      Spacer()

      if let optionalText {
        Text(optionalText)
          .font(.system(.body, design: .rounded))

          //                    .font(.system(size: 17, weight: .regular, design: .rounded))
          .foregroundColor(.DarkIcon.opacity(0.6))
          .layoutPriority(1)
          .padding(.trailing, -8)
      }

      Image(systemName: "chevron.forward")
        .font(.system(.subheadline, design: .rounded))
        //                .font(.system(size: 15))
        .foregroundColor(.DarkIcon.opacity(0.6))
    }
    .frame(maxWidth: .infinity)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }
}

struct SettingsCategoryView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  var body: some View {
    CategoryView(mode: .settings, income: false)
      .navigationBarBackButtonHidden(true)
      .navigationBarTitle("")
      .navigationBarHidden(true)
      .background(Color.PrimaryBackground)
  }
}

private struct PrivacyPolicyView: View {
  var body: some View {
    LegalTextView(
      title: String(localized: "Privacy Policy"),
      sections: [
        (String(localized: "Data Storage"), String(localized: "LittleSaver stores transactions, categories, budgets, and app settings on your device. Devices with iCloud enabled sync this data through your private CloudKit database. The developer cannot access the contents of your private database.")),
        (String(localized: "Notifications and Biometrics"), String(localized: "Reminders are scheduled locally by the system. App Lock only uses the authentication result provided by the system and does not read or store your biometric data.")),
        (String(localized: "Data Transfer"), String(localized: "The app contains no advertising, analytics SDKs, or developer-operated servers. When you choose to import or export data, view source code, or report an issue, data is handled by the system feature or external website you select.")),
        (String(localized: "Your Control"), String(localized: "You can export or erase data in Settings, and manage notifications, iCloud, and biometric permissions in the system Settings app."))
      ])
  }
}

struct BundledThirdPartyLicense: Identifiable, Equatable {
  let name: String
  let attribution: String
  let resourceName: String

  var id: String { resourceName }

  static let all = [
    BundledThirdPartyLicense(
      name: "CloudKitSyncMonitor",
      attribution: "Copyright (c) 2020 Grant Grueninger",
      resourceName: "CloudKitSyncMonitor"),
    BundledThirdPartyLicense(
      name: "ConfettiSwiftUI",
      attribution: "Copyright (c) 2020 Simon Bachmann",
      resourceName: "ConfettiSwiftUI"),
    BundledThirdPartyLicense(
      name: "Popovers",
      attribution: "Copyright (c) 2022 A. Zheng",
      resourceName: "Popovers")
  ]

  func text(in bundle: Bundle = .main) throws -> String {
    let resourceURL = bundle.url(
      forResource: resourceName,
      withExtension: "txt",
      subdirectory: "ThirdPartyLicenses")
      ?? bundle.url(forResource: resourceName, withExtension: "txt")

    guard let resourceURL else {
      throw BundledThirdPartyLicenseError.missingResource(resourceName)
    }
    return try String(contentsOf: resourceURL, encoding: .utf8)
  }
}

enum BundledThirdPartyLicenseError: LocalizedError {
  case missingResource(String)

  var errorDescription: String? {
    switch self {
    case .missingResource(let name):
      return String(localized: "Unable to read the license text for \(name).")
    }
  }
}

private struct OpenSourceLicensesView: View {
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text("app_name")
            .font(.headline)
          Text("This project is based on Dime by Rafael Soh and is released under the GNU General Public License v3.0. See the source repository for the complete license and original attribution.")
            .font(.body)
            .foregroundColor(.SubtitleText)
        }
        .padding(.vertical, 4)
      }

      Section("Third-Party Licenses") {
        ForEach(BundledThirdPartyLicense.all) { license in
          NavigationLink(destination: ThirdPartyLicenseDetailView(license: license)) {
            VStack(alignment: .leading, spacing: 4) {
              Text(license.name)
              Text(license.attribution)
                .font(.caption)
                .foregroundColor(.SubtitleText)
            }
          }
        }
      }
    }
    .navigationTitle("Open Source Licenses")
  }
}

private struct ThirdPartyLicenseDetailView: View {
  let license: BundledThirdPartyLicense
  @State private var contents = String(localized: "Loading license text…")

  var body: some View {
    ScrollView {
      Text(contents)
        .font(.body.monospaced())
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
    .navigationTitle(license.name)
    .background(Color.PrimaryBackground)
    .task {
      do {
        contents = try license.text()
      } catch {
        contents = error.localizedDescription
      }
    }
  }
}

private struct LegalTextView: View {
  let title: String
  let sections: [(String, String)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
          VStack(alignment: .leading, spacing: 6) {
            Text(section.0)
              .font(.headline)
              .foregroundColor(.PrimaryText)
            Text(section.1)
              .font(.body)
              .foregroundColor(.SubtitleText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(20)
    }
    .navigationTitle(title)
    .background(Color.PrimaryBackground)
  }
}
