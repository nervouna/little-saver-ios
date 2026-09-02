//
//  BudgetWidget.swift
//  LittleSaver
//
//  Created by Rafael Soh on 17/8/22.
//

import SwiftUI
import WidgetKit

struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: BudgetWidgetConfigurationIntent.self, provider: BudgetWidgetProvider()) { entry in
            BudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget")
        .description("Monitor how you are sticking to your budgets.")
        .supportedFamilies([.systemSmall])
    }
}

struct BudgetWidgetProvider: IntentTimelineProvider {
    typealias Intent = BudgetWidgetConfigurationIntent

    public typealias Entry = BudgetWidgetEntry

    func placeholder(in _: Context) -> BudgetWidgetEntry {
        let loaded = loadData(budgetId: "")

        return BudgetWidgetEntry(date: Date(), totalSpent: loaded.total, percentageOfDays: loaded.percentage, budget: loaded.budget, configuration: BudgetWidgetConfigurationIntent())
    }

    func getSnapshot(for configuration: BudgetWidgetConfigurationIntent, in _: Context, completion: @escaping (BudgetWidgetEntry) -> Void) {
        let loaded = loadData(budgetId: configuration.budget?.identifier ?? "")

        let entry = BudgetWidgetEntry(date: Date(), totalSpent: loaded.total, percentageOfDays: loaded.percentage, budget: loaded.budget, configuration: configuration)
        completion(entry)
    }

    func getTimeline(for configuration: BudgetWidgetConfigurationIntent, in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let loaded = loadData(budgetId: configuration.budget?.identifier ?? "")

        let entry = BudgetWidgetEntry(date: Date(), totalSpent: loaded.total, percentageOfDays: loaded.percentage, budget: loaded.budget, configuration: configuration)

        let timeline = Timeline(entries: [entry], policy: .atEnd)

        completion(timeline)
    }

    func loadData(budgetId: String) -> (total: Double, percentage: Double, budget: HoldingBudget) {
        let dataController = DataController.shared
        do {
            return try dataController.performViewContextRead { context in
                guard let objectIDURL = URL(string: budgetId),
                      let managedObjectID = dataController.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: objectIDURL),
                      let budget = try context.existingObject(with: managedObjectID) as? Budget,
                      BudgetValidation.isUsable(startDate: budget.startDate, hasCategory: budget.category != nil),
                      let startDate = budget.startDate else {
                    return (0, 0, HoldingBudget(type: 1, emoji: "failed", name: "", colour: "", budgetAmount: 0))
                }

                let transactions = try context.fetch(dataController.fetchRequestForBudgetTransactions(budget: budget))
                let total = transactions.reduce(0) { $0 + $1.wrappedAmount }
                guard total.isFinite, budget.amount.isFinite else {
                    return (0, 0, HoldingBudget(type: 1, emoji: "failed", name: "", colour: "", budgetAmount: 0))
                }
                let holdingBudget = HoldingBudget(
                    type: Int(budget.type),
                    emoji: budget.wrappedEmoji,
                    name: budget.wrappedName,
                    colour: budget.wrappedColour,
                    budgetAmount: budget.amount
                )
                let percentage = BudgetWindow.progress(
                    startDate: startDate,
                    endDate: budget.endDate,
                    now: .now,
                    calendar: .current
                )
                return (total, percentage, holdingBudget)
            }
        } catch {
            return (0, 0, HoldingBudget(type: 1, emoji: "failed", name: "", colour: "", budgetAmount: 0))
        }
    }
}

struct BudgetWidgetEntry: TimelineEntry {
    let date: Date
    let totalSpent: Double
    let percentageOfDays: Double
    let budget: HoldingBudget
    let configuration: BudgetWidgetConfigurationIntent
}

struct HoldingBudget {
    let type: Int
    let emoji: String
    let name: String
    let colour: String
    let budgetAmount: Double
}

struct BudgetWidgetEntryView: View {
    let entry: BudgetWidgetProvider.Entry

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = Locale.current.currencyCode!
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
        return abs(entry.budget.budgetAmount - entry.totalSpent)
    }

    var percentString1: String {
        return "\(BudgetMath.roundedPercentage(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount))%"
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
                .widgetURL(DeepLink.budget(name: entry.budget.name).url)
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
                .widgetURL(DeepLink.budget(name: entry.budget.name).url)
            }
        }
    }
}

struct WidgetBudgetDollarView: View {
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var amount: Double
    var red: Bool

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = Locale.current.currencyCode!

    var body: some View {
        Text(localizedCurrencyAmount(amount, currencyCode: currency, showCents: showCents))
            .font(.system(.title3, design: .rounded).weight(.medium))
            .foregroundColor(red ? Color("BudgetRed") : Color.PrimaryText)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}
