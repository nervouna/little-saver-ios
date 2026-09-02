//
//  LockBudgetWidget.swift
//  LittleSaverWidget
//
//  Created by Rafael Soh on 9/9/22.
//

import LittleSaverCore
import SwiftUI
import WidgetKit

struct LockBudgetWidget: Widget {
    let kind: String = "LockBudgetWidget"

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOSApplicationExtension 16, *) {
            return [
                .accessoryCircular,
                .accessoryRectangular,
                .accessoryInline
            ]
        } else {
            return [WidgetFamily]()
        }
    }

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: BudgetWidgetConfigurationIntent.self, provider: LockBudgetWidgetProvider()) { entry in
            if entry.readStatus.isUnavailable {
                WidgetReadStatusView(status: entry.readStatus)
            } else {
                LockBudgetWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Budget")
        .description("Monitor how you are sticking to your budgets.")
        .supportedFamilies(supportedFamilies)
    }
}

struct LockBudgetWidgetProvider: IntentTimelineProvider {
    typealias Intent = BudgetWidgetConfigurationIntent
    typealias Entry = LockBudgetWidgetEntry

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
        Entry(date: Date(), totalSpent: 0, timeLeft: "", budget: HoldingBudget(type: 1, emoji: "failed", name: "", colour: "", budgetAmount: 0), configuration: configuration, readStatus: status)
    }

    private func loadEntry(configuration: Intent) async -> Entry {
        do {
            guard let snapshot = try await DataController.platformShared.budgetSnapshot(identifier: configuration.budget?.identifier ?? "") else {
                return empty(configuration: configuration, status: .empty)
            }
            let component: Calendar.Component = snapshot.type == 1 ? .hour : .day
            let left = Calendar.current.dateComponents([component], from: .now, to: snapshot.endDate).value(for: component) ?? 0
            let timeLeft = snapshot.type == 1 ? String(localized: "\(left) hours left") : String(localized: "\(left) days left")
            let budget = HoldingBudget(type: snapshot.type, emoji: snapshot.emoji, name: snapshot.name, colour: snapshot.colour, budgetAmount: snapshot.amount)
            return Entry(date: Date(), totalSpent: snapshot.spent, timeLeft: timeLeft, budget: budget, configuration: configuration)
        } catch {
            return empty(configuration: configuration, status: ExtensionReadStatus(error: error))
        }
    }
}

struct LockBudgetWidgetEntry: TimelineEntry {
    let date: Date
    let totalSpent: Double
    let timeLeft: String
    let budget: HoldingBudget
    let configuration: BudgetWidgetConfigurationIntent
    var readStatus: ExtensionReadStatus = .loaded
}

struct LockBudgetWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: LockBudgetWidgetProvider.Entry

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

    var statusText: String {
        if entry.budget.budgetAmount > entry.totalSpent {
            return String(localized: "left")
        } else {
            return String(localized: "over")
        }
    }

    var difference: Double {
        return abs(NumericSafety.difference(entry.budget.budgetAmount, entry.totalSpent))
    }

    var percent: Double {
        return BudgetMath.spendingRatio(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount)
    }

    var gaugePercent: Double {
        return BudgetMath.gaugeRatio(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount)
    }

    var percentString: String {
        return localizedFormat("widget.budget.percentage.spent", arguments: [BudgetMath.percentageText(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount)])
    }

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    func currencyAmount(_ amount: Double) -> String {
        localizedCurrencyAmount(amount, currencyCode: currency, showCents: showCents)
    }

    var budgetStatusText: String {
        localizedFormat("widget.budget.amount.status.period", arguments: [currencyAmount(difference), statusText, budgetType])
    }

    var body: some View {
        switch widgetFamily {
        case .accessoryInline:
            if entry.configuration.budget == nil || entry.budget.emoji == "failed" {
                Text("Select budget in widget options")
            } else {
                Text(localizedFormat("widget.budget.inline.status", arguments: [entry.budget.emoji, currencyAmount(difference), statusText]))
                    .widgetURL(DeepLink.budget(name: entry.budget.name).url)
            }

        case .accessoryCircular:
            if #available(iOS 17.0, *) {
                if entry.configuration.budget == nil || entry.budget.emoji == "failed" {
                    ZStack {
                        AccessoryWidgetBackground()

                        Text("SELECT BUDGET")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                } else {
                    Gauge(value: gaugePercent) {
                        Text(entry.budget.emoji)
                    } currentValueLabel: {
                        Text(BudgetMath.percentageText(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount))
                    }
                    .gaugeStyle(AccessoryCircularGaugeStyle())
                    .widgetURL(DeepLink.budget(name: entry.budget.name).url)
                    .containerBackground(for: .widget) { Color.clear }
                }
            } else {
                if entry.configuration.budget == nil || entry.budget.emoji == "failed" {
                    ZStack {
                        if #available(iOS 16.0, *) {
                            AccessoryWidgetBackground()
                        }

                        VStack {
                            Text("SELECT BUDGET")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                } else {
                    if #available(iOS 16.0, *) {
                        Gauge(value: gaugePercent) {
                            Text(entry.budget.emoji)
                        } currentValueLabel: {
                            Text(BudgetMath.percentageText(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount))
                        }
                        .gaugeStyle(AccessoryCircularGaugeStyle())
                        .widgetURL(DeepLink.budget(name: entry.budget.name).url)
                    } else {
                        EmptyView()
                    }
                }
            }

        case .accessoryRectangular:
            if #available(iOS 17.0, *) {
                if entry.configuration.budget == nil || entry.budget.emoji == "failed" {
                    Text("SELECT BUDGET IN WIDGET OPTIONS")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .containerBackground(for: .widget) { Color.clear }
                } else {
                    GeometryReader { proxy in
                        VStack(alignment: .leading) {
                            HStack(spacing: 3) {
                                Text(entry.budget.name)

                                if showPercent(size: proxy.size.width) {
                                    Text("•")
                                    Text(percentString)
                                }
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))

                            Text(budgetStatusText)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(Color.SubtitleText)

                            Gauge(value: gaugePercent, in: 0 ... 1) {
                                Text("Percent Spent")
                            } currentValueLabel: {
                                EmptyView()
                            } minimumValueLabel: {
                                Text(currencyAmount(entry.totalSpent))
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                            } maximumValueLabel: {
                                Text(currencyAmount(entry.budget.budgetAmount))
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                            }
                            .frame(height: 5)
                            .gaugeStyle(.accessoryLinear)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .widgetURL(DeepLink.budget(name: entry.budget.name).url)
                    .containerBackground(for: .widget) { Color.clear }
                }
            } else {
                if entry.configuration.budget == nil || entry.budget.emoji == "failed" {
                    Text("SELECT BUDGET IN WIDGET OPTIONS")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                } else {
                    GeometryReader { proxy in
                        VStack(alignment: .leading) {
                            HStack(spacing: 3) {
                                Text(entry.budget.name)

                                if showPercent(size: proxy.size.width) {
                                    Text("•")
                                    Text(percentString)
                                }
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))

                            Text(budgetStatusText)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(Color.SubtitleText)

                            if #available(iOS 16.0, *) {
                                Gauge(value: gaugePercent, in: 0 ... 1) {
                                    Text("Percent Spent")
                                } currentValueLabel: {
                                    EmptyView()
                                } minimumValueLabel: {
                                    Text(currencyAmount(entry.totalSpent))
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                } maximumValueLabel: {
                                    Text(currencyAmount(entry.budget.budgetAmount))
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                }
                                .frame(height: 5)
                                .gaugeStyle(.accessoryLinear)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .widgetURL(DeepLink.budget(name: entry.budget.name).url)
                }
            }

        default:
            EmptyView()
        }
    }

    func showPercent(size: CGFloat) -> Bool {
        return size > entry.budget.name.widthOfRoundedString(size: 15, weight: .semibold) + 15 + percentString.widthOfRoundedString(size: 15, weight: .semibold)
    }
}
