//
//  BudgetWidget.swift
//  LittleSaver
//
//  Created by Rafael Soh on 17/8/22.
//

import LittleSaverCore
import SwiftUI
import WidgetKit

struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: BudgetWidgetConfigurationIntent.self, provider: BudgetWidgetProvider()) { entry in
            if entry.readStatus.isUnavailable {
                WidgetReadStatusView(status: entry.readStatus)
            } else {
                BudgetWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Budget")
        .description("Monitor how you are sticking to your budgets.")
        .supportedFamilies([.systemSmall])
    }
}

struct BudgetWidgetProvider: IntentTimelineProvider {
    typealias Intent = BudgetWidgetConfigurationIntent
    typealias Entry = BudgetWidgetEntry

    func placeholder(in _: Context) -> Entry {
        empty(configuration: Intent(), status: .loading)
    }

    func getSnapshot(for configuration: Intent, in _: Context, completion: @escaping (Entry) -> Void) {
        Task { completion(await loadEntry(configuration: configuration)) }
    }

    func getTimeline(for configuration: Intent, in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let entry = await loadEntry(configuration: configuration)
            completion(Timeline(entries: [entry], policy: .after(entry.readStatus.nextRefresh(after: entry.date))))
        }
    }

    private func empty(configuration: Intent, status: ExtensionReadStatus) -> Entry {
        Entry(date: Date(), totalSpent: 0, percentageOfDays: 0, budget: HoldingBudget(type: 1, emoji: "failed", name: "", colour: "", budgetAmount: 0), configuration: configuration, readStatus: status)
    }

    private func loadEntry(configuration: Intent) async -> Entry {
        do {
            guard let snapshot = try await DataController.platformShared.budgetSnapshot(identifier: configuration.budget?.identifier ?? "") else {
                return empty(configuration: configuration, status: .empty)
            }

            let budget = HoldingBudget(id: snapshot.id, type: snapshot.type, emoji: snapshot.emoji, name: snapshot.name, colour: snapshot.colour, budgetAmount: snapshot.amount)
            return Entry(date: Date(), totalSpent: snapshot.spent, percentageOfDays: snapshot.progress, budget: budget, configuration: configuration)
        } catch {
            return empty(configuration: configuration, status: ExtensionReadStatus(error: error))
        }
    }
}

struct BudgetWidgetEntry: TimelineEntry {
    let date: Date
    let totalSpent: Double
    let percentageOfDays: Double
    let budget: HoldingBudget
    let configuration: BudgetWidgetConfigurationIntent
    var readStatus: ExtensionReadStatus = .loaded
}

struct HoldingBudget: Sendable {
    var id: UUID? = nil
    var deepLink: DeepLink { id.map(DeepLink.budgetUUID) ?? .budget(name: name) }
    let type: Int
    let emoji: String
    let name: String
    let colour: String
    let budgetAmount: Double
}

/// Unavailable storage must not look like an empty ledger or a zero balance.
struct WidgetReadStatusView: View {
    let status: ExtensionReadStatus

    private var message: String {
        status == .loading ? String(localized: "Preparing data…") : String(localized: "Unable to Open Data")
    }

    var body: some View {
        if #available(iOSApplicationExtension 17, *) {
            Text(message)
                .containerBackground(for: .widget) { Color.PrimaryBackground }
        } else {
            Text(message)
        }
    }
}

struct BudgetWidgetEntryView: View {
    let entry: BudgetWidgetProvider.Entry

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var budgetType: String {
        switch entry.budget.type {
        case 1:
            return String(localized: "today")
        case 2:
            return String(localized: "this week")
        case 3:
            return String(localized: "this month")
        case 4:
            return String(localized: "this year")
        default:
            return String(localized: "this week")
        }
    }

    var difference: Double {
        return abs(NumericSafety.difference(entry.budget.budgetAmount, entry.totalSpent))
    }

    var percentString1: String {
        return BudgetMath.percentageText(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount)
    }

    var spendingRatio: Double {
        BudgetMath.spendingRatio(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount)
    }

    var systemSmallWidgetText: String {
        localizedFormat(
            entry.budget.budgetAmount >= entry.totalSpent ? "widget.budget.left.period" : "widget.budget.over.period",
            arguments: [budgetType]
        )
    }

    func currencyAmount(_ amount: Double) -> String {
        localizedCurrencyAmount(amount, currencyCode: currency, showCents: showCents)
    }

    func showTimeFrame(size: CGFloat) -> Bool {
        return size > systemSmallWidgetText.widthOfRoundedString(size: 10, weight: .semibold)
    }

    var body: some View {
        if entry.configuration.budget == nil {
            if #available(iOS 17.0, *) {
                Text("Select budget in widget options")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.SubtitleText)
                    .padding(15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .containerBackground(for: .widget) {
                        Color.PrimaryBackground
                    }
            } else {
                Text("Select budget in widget options")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.SubtitleText)
                    .padding(15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.PrimaryBackground)
            }

        } else if entry.budget.emoji == "failed" {
            if #available(iOS 17.0, *) {
                Text("Budget no longer exists - please select new budget from widget options.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.SubtitleText)
                    .padding(15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .containerBackground(for: .widget) {
                        Color.PrimaryBackground
                    }
            } else {
                Text("Budget no longer exists - please select new budget from widget options.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.SubtitleText)
                    .padding(15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.PrimaryBackground)
            }

        } else {
            if #available(iOS 17.0, *) {
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2.4) {
                            HStack(spacing: 5) {
                                Text(entry.budget.emoji)
                                    .font(.system(size: 9))
                                Text(entry.budget.name.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundColor(Color.PrimaryText)

                            Text(localizedFormat("widget.budget.spent.percent", arguments: [percentString1]))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                        }

                        Spacer()

                        RingView(percent: entry.percentageOfDays, width: 2.4, topStroke: Color.DarkBackground, bottomStroke: Color.SecondaryBackground)
                            .frame(width: 13, height: 13)
                            .padding(3)
                    }
                    .frame(maxWidth: .infinity)

                    GeometryReader { proxy in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                ZStack {
                                    DonutSemicircle(percent: 1, cornerRadius: 4, width: 15)
                                        .fill(Color.SecondaryBackground)
                                        .frame(width: proxy.size.width, height: proxy.size.width / 2)

                                    if spendingRatio < 0.97 {
                                        DonutSemicircle(percent: 1 - spendingRatio, cornerRadius: 4, width: 15)
                                            .fill(Color(hex: entry.budget.colour))
                                            .frame(width: proxy.size.width, height: proxy.size.width / 2)
                                    }
                                }
                                .frame(width: proxy.size.width)

                                VStack(spacing: -4) {
                                    WidgetBudgetDollarView(amount: difference, red: entry.totalSpent >= entry.budget.budgetAmount)
                                        .frame(width: proxy.size.width - 50)

                                    if showTimeFrame(size: proxy.size.width - 50) {
                                        Text(systemSmallWidgetText)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundColor(Color.SubtitleText)
                                    } else {
                                        if entry.budget.budgetAmount >= entry.totalSpent {
                                            Text("left")
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                        } else {
                                            Text("over")
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                        }
                                    }
                                }
                            }
                            .frame(width: proxy.size.width)

                            HStack {
                                if entry.totalSpent > 999.99 || entry.budget.budgetAmount > 999.99 {
                                    Text(currencyAmount(entry.totalSpent))
                                        .frame(width: 50, alignment: .leading)
                                    Spacer()
                                    Text(currencyAmount(entry.budget.budgetAmount))
                                        .frame(width: 50, alignment: .trailing)
                                } else {
                                    Text(currencyAmount(entry.totalSpent))
                                        .frame(width: 50, alignment: .leading)
                                    Spacer()
                                    Text(currencyAmount(entry.budget.budgetAmount))
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Color.SubtitleText)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(for: .widget) {
                    Color.PrimaryBackground
                }
                .widgetURL(entry.budget.deepLink.url)
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2.4) {
                            HStack(spacing: 5) {
                                Text(entry.budget.emoji)
                                    .font(.system(size: 9))
                                Text(entry.budget.name.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundColor(Color.PrimaryText)

                            Text(localizedFormat("widget.budget.spent.percent", arguments: [percentString1]))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                        }

                        Spacer()

                        RingView(percent: entry.percentageOfDays, width: 2.4, topStroke: Color.DarkBackground, bottomStroke: Color.SecondaryBackground)
                            .frame(width: 13, height: 13)
                            .padding(3)
                    }
                    .frame(maxWidth: .infinity)

                    GeometryReader { proxy in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                ZStack {
                                    DonutSemicircle(percent: 1, cornerRadius: 4, width: 15)
                                        .fill(Color.SecondaryBackground)
                                        .frame(width: proxy.size.width, height: proxy.size.width / 2)

                                    if spendingRatio < 0.97 {
                                        DonutSemicircle(percent: 1 - spendingRatio, cornerRadius: 4, width: 15)
                                            .fill(Color(hex: entry.budget.colour))
                                            .frame(width: proxy.size.width, height: proxy.size.width / 2)
                                    }
                                }
                                .frame(width: proxy.size.width)

                                VStack(spacing: -4) {
                                    WidgetBudgetDollarView(amount: difference, red: entry.totalSpent >= entry.budget.budgetAmount)
                                        .frame(width: proxy.size.width - 50)

                                    if showTimeFrame(size: proxy.size.width - 50) {
                                        Text(systemSmallWidgetText)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundColor(Color.SubtitleText)
                                    } else {
                                        if entry.budget.budgetAmount >= entry.totalSpent {
                                            Text("left")
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                        } else {
                                            Text("over")
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                        }
                                    }
                                }
                            }
                            .frame(width: proxy.size.width)

                            HStack {
                                if entry.totalSpent > 999.99 || entry.budget.budgetAmount > 999.99 {
                                    Text(currencyAmount(entry.totalSpent))
                                        .frame(width: 50, alignment: .leading)
                                    Spacer()
                                    Text(currencyAmount(entry.budget.budgetAmount))
                                        .frame(width: 50, alignment: .trailing)
                                } else {
                                    Text(currencyAmount(entry.totalSpent))
                                        .frame(width: 50, alignment: .leading)
                                    Spacer()
                                    Text(currencyAmount(entry.budget.budgetAmount))
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Color.SubtitleText)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(15)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.PrimaryBackground)
                .widgetURL(entry.budget.deepLink.url)
            }
        }
    }
}

struct WidgetBudgetDollarView: View {
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var amount: Double
    var red: Bool

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")

    var body: some View {
        Text(localizedCurrencyAmount(amount, currencyCode: currency, showCents: showCents))
            .font(.system(.title3, design: .rounded).weight(.medium))
            .foregroundColor(red ? Color("BudgetRed") : Color.PrimaryText)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}
