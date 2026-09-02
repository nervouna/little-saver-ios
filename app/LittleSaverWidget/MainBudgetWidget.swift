//
//  MainBudgetWidget.swift
//  LittleSaver
//
//  Created by Rafael Soh on 12/1/23.
//

import LittleSaverCore
import SwiftUI
import WidgetKit

struct MainBudgetWidget: Widget {
    let kind: String = "MainBudgetWidget"

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOS 16.0, *) {
            return [
                .accessoryCircular,
                .accessoryRectangular,
                .systemSmall
            ]
        } else {
            return [.systemSmall]
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MainBudgetWidgetProvider()) { entry in
            if entry.readStatus.isUnavailable {
                WidgetReadStatusView(status: entry.readStatus)
            } else {
                MainBudgetWidgetEntryView(entry: entry)
            }
        }
        .supportedFamilies(supportedFamilies)
        .configurationDisplayName("Overall Budget")
        .description("Monitor how you are sticking to your overall budgets.")
    }
}

struct MainBudgetWidgetProvider: TimelineProvider {
    typealias Entry = MainBudgetWidgetEntry

    func placeholder(in _: Context) -> Entry { empty(status: .loading) }

    func getSnapshot(in _: Context, completion: @escaping (Entry) -> Void) {
        Task { completion(await loadEntry()) }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let entry = await loadEntry()
            completion(Timeline(entries: [entry], policy: .after(entry.readStatus.nextRefresh(after: entry.date))))
        }
    }

    private func empty(status: ExtensionReadStatus) -> Entry {
        Entry(date: Date(), totalSpent: 0, percentageOfDays: 0, type: 1, budgetAmount: 0, startDate: Date(), found: false, readStatus: status)
    }

    private func loadEntry() async -> Entry {
        do {
            guard let snapshot = try await DataController.platformShared.mainBudgetSnapshot() else { return empty(status: .empty) }
            return Entry(date: Date(), totalSpent: snapshot.spent, percentageOfDays: snapshot.progress, type: snapshot.type, budgetAmount: snapshot.amount, startDate: snapshot.startDate, found: true)
        } catch {
            return empty(status: ExtensionReadStatus(error: error))
        }
    }
}

struct MainBudgetWidgetEntry: TimelineEntry {
    let date: Date
    let totalSpent: Double
    let percentageOfDays: Double
    let type: Int
    let budgetAmount: Double
    let startDate: Date
    let found: Bool
    var readStatus: ExtensionReadStatus = .loaded
}

struct MainBudgetWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: MainBudgetWidgetProvider.Entry

    var budgetType: String {
        switch entry.type {
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

    var headingText: String {
        switch entry.type {
        case 1:
            return localizedDate(entry.startDate, template: "dMMMyyyy")
        case 2:
            let endComponents = DateComponents(day: 7, second: -1)
            let endWeekDate = Calendar.current.date(byAdding: endComponents, to: entry.startDate)!
            return localizedDateInterval(from: entry.startDate, to: endWeekDate)
        case 3:
            let endComponents = DateComponents(month: 1, second: -1)
            let endWeekDate = Calendar.current.date(byAdding: endComponents, to: entry.startDate)!
            return localizedDateInterval(from: entry.startDate, to: endWeekDate)
        case 4:
            return localizedDate(entry.startDate, template: "dMMMyy")
        default:
            return ""
        }
    }

    var difference: Double {
        return abs(entry.budgetAmount - entry.totalSpent)
    }

    var percentString: String {
        return String(localized: "\(BudgetMath.roundedPercentage(spent: entry.totalSpent, budgetAmount: entry.budgetAmount))% spent")
    }

    var percentString1: String {
        return "\(BudgetMath.roundedPercentage(spent: entry.totalSpent, budgetAmount: entry.budgetAmount))%"
    }

    var percent: Double {
        return BudgetMath.spendingRatio(spent: entry.totalSpent, budgetAmount: entry.budgetAmount)
    }

    var gaugePercent: Double {
        return BudgetMath.gaugeRatio(spent: entry.totalSpent, budgetAmount: entry.budgetAmount)
    }

    var systemSmallWidgetText: String {
        localizedFormat(
            entry.budgetAmount >= entry.totalSpent ? "widget.budget.left.period" : "widget.budget.over.period",
            arguments: [budgetType]
        )
    }

    func showPercent(size: CGFloat) -> Bool {
        return size > headingText.widthOfRoundedString(size: 15, weight: .semibold) + 15 + percentString.widthOfRoundedString(size: 15, weight: .semibold)
    }

    func showTimeFrame(size: CGFloat) -> Bool {
        return size > systemSmallWidgetText.widthOfRoundedString(size: 10, weight: .semibold)
    }

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = Locale.current.currencyCode!
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    func currencyAmount(_ amount: Double) -> String {
        localizedCurrencyAmount(amount, currencyCode: currency, showCents: showCents)
    }

    var budgetStatusText: String {
        localizedFormat(
            "widget.budget.amount.status.period",
            arguments: [
                currencyAmount(difference),
                entry.totalSpent > entry.budgetAmount ? String(localized: "over") : String(localized: "left"),
                budgetType,
            ]
        )
    }

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            if #available(iOS 17.0, *) {
                if !entry.found {
                    ZStack {
                        AccessoryWidgetBackground()

                        VStack {
                            Text("ADD\nBUDGET")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                } else {
                    Gauge(value: gaugePercent) {
                        Image(systemName: "dollarsign.circle.fill")
                    } currentValueLabel: {
                        Text("\(BudgetMath.roundedPercentage(spent: entry.totalSpent, budgetAmount: entry.budgetAmount))%")
                    }
                    .gaugeStyle(AccessoryCircularGaugeStyle())
                    .containerBackground(for: .widget) { Color.clear }
                }
            } else {
                if !entry.found {
                    ZStack {
                        if #available(iOS 16.0, *) {
                            AccessoryWidgetBackground()
                        }

                        VStack {
                            Text("ADD BUDGET")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                } else {
                    if #available(iOS 16.0, *) {
                        Gauge(value: gaugePercent) {
                            Image(systemName: "dollarsign.circle.fill")
                        } currentValueLabel: {
                            Text("\(BudgetMath.roundedPercentage(spent: entry.totalSpent, budgetAmount: entry.budgetAmount))%")
                        }
                        .gaugeStyle(AccessoryCircularGaugeStyle())

                    } else {
                        EmptyView()
                    }
                }
            }

        case .accessoryRectangular:
            if #available(iOS 17.0, *) {
                if !entry.found {
                    Text("ADD OVERALL BUDGET")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .containerBackground(for: .widget) { Color.clear }
                } else {
                    GeometryReader { proxy in
                        VStack(alignment: .leading) {
                            HStack(spacing: 3) {
                                Text(headingText)

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
                                Text(currencyAmount(entry.budgetAmount))
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                            }
                            .frame(height: 5)
                            .gaugeStyle(.accessoryLinear)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .containerBackground(for: .widget) { Color.clear }
                }
            } else {
                if !entry.found {
                    Text("ADD OVERALL BUDGET")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                } else {
                    GeometryReader { proxy in
                        VStack(alignment: .leading) {
                            HStack(spacing: 3) {
                                Text(headingText)

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
                                    Text(currencyAmount(entry.budgetAmount))
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                }
                                .frame(height: 5)
                                .gaugeStyle(.accessoryLinear)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

        case .systemSmall:
            if #available(iOS 17.0, *) {
                if !entry.found {
                    Text("Create your overall budget in the app")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.SubtitleText)
                        .padding(15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .containerBackground(for: .widget) { Color.PrimaryBackground }
                } else {
                    VStack(spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2.4) {
                                Text(headingText.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
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

                                        if percent < 0.97 {
                                            DonutSemicircle(percent: 1 - percent, cornerRadius: 4, width: 15)
                                                .fill(Color.DarkBackground)
                                                .frame(width: proxy.size.width, height: proxy.size.width / 2)
                                        }
                                    }
                                    .frame(width: proxy.size.width)

                                    VStack(spacing: -4) {
                                        WidgetBudgetDollarView(amount: difference, red: entry.totalSpent >= entry.budgetAmount)
                                            .frame(width: proxy.size.width - 50)

                                        if showTimeFrame(size: proxy.size.width - 50) {
                                            Text(systemSmallWidgetText)
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                        } else {
                                            if entry.budgetAmount >= entry.totalSpent {
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
                                    if entry.totalSpent > 999.99 || entry.budgetAmount > 999.99 {
                                        Text(currencyAmount(entry.totalSpent))
                                            .frame(width: 50, alignment: .leading)
                                        Spacer()
                                        Text(currencyAmount(entry.budgetAmount))
                                            .frame(width: 50, alignment: .trailing)
                                    } else {
                                        Text(currencyAmount(entry.totalSpent))
                                            .frame(width: 50, alignment: .leading)
                                        Spacer()
                                        Text(currencyAmount(entry.budgetAmount))
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
                    .containerBackground(for: .widget) { Color.PrimaryBackground }
                }
            } else {
                if !entry.found {
                    Text("Create your overall budget in the app")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.SubtitleText)
                        .padding(15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.PrimaryBackground)
                } else {
                    VStack(spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2.4) {
                                Text(headingText.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
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

                                        if percent < 0.97 {
                                            DonutSemicircle(percent: 1 - percent, cornerRadius: 4, width: 15)
                                                .fill(Color.DarkBackground)
                                                .frame(width: proxy.size.width, height: proxy.size.width / 2)
                                        }
                                    }
                                    .frame(width: proxy.size.width)

                                    VStack(spacing: -4) {
                                        WidgetBudgetDollarView(amount: difference, red: entry.totalSpent >= entry.budgetAmount)
                                            .frame(width: proxy.size.width - 50)

                                        if showTimeFrame(size: proxy.size.width - 50) {
                                            Text(systemSmallWidgetText)
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                        } else {
                                            if entry.budgetAmount >= entry.totalSpent {
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
                                    if entry.totalSpent > 999.99 || entry.budgetAmount > 999.99 {
                                        Text(currencyAmount(entry.totalSpent))
                                            .frame(width: 50, alignment: .leading)
                                        Spacer()
                                        Text(currencyAmount(entry.budgetAmount))
                                            .frame(width: 50, alignment: .trailing)
                                    } else {
                                        Text(currencyAmount(entry.totalSpent))
                                            .frame(width: 50, alignment: .leading)
                                        Spacer()
                                        Text(currencyAmount(entry.budgetAmount))
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
                }
            }

        default:
            EmptyView()
        }
    }
}
