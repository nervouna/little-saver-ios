//
//  LockBudgetWidget.swift
//  LittleSaverWidget
//
//  Created by Rafael Soh on 9/9/22.
//

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
            LockBudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget")
        .description("Monitor how you are sticking to your budgets.")
        .supportedFamilies(supportedFamilies)
    }
}

struct LockBudgetWidgetProvider: IntentTimelineProvider {
    typealias Intent = BudgetWidgetConfigurationIntent

    public typealias Entry = LockBudgetWidgetEntry

    func placeholder(in _: Context) -> LockBudgetWidgetEntry {
        let loaded = loadData(budgetId: "")

        return LockBudgetWidgetEntry(date: Date(), totalSpent: loaded.total, timeLeft: loaded.timeLeft, budget: loaded.budget, configuration: BudgetWidgetConfigurationIntent())
    }

    func getSnapshot(for configuration: BudgetWidgetConfigurationIntent, in _: Context, completion: @escaping (LockBudgetWidgetEntry) -> Void) {
        let loaded = loadData(budgetId: configuration.budget?.identifier ?? "")

        let entry = LockBudgetWidgetEntry(date: Date(), totalSpent: loaded.total, timeLeft: loaded.timeLeft, budget: loaded.budget, configuration: configuration)
        completion(entry)
    }

    func getTimeline(for configuration: BudgetWidgetConfigurationIntent, in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let loaded = loadData(budgetId: configuration.budget?.identifier ?? "")

        let entry = LockBudgetWidgetEntry(date: Date(), totalSpent: loaded.total, timeLeft: loaded.timeLeft, budget: loaded.budget, configuration: configuration)

        let timeline = Timeline(entries: [entry], policy: .atEnd)

        completion(timeline)
    }

    func loadData(budgetId: String) -> (total: Double, timeLeft: String, budget: HoldingBudget) {
        let dataController = DataController.shared
        do {
            return try dataController.performViewContextRead { context in
                guard let objectIDURL = URL(string: budgetId),
                      let managedObjectID = dataController.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: objectIDURL),
                      let budget = try context.existingObject(with: managedObjectID) as? Budget,
                      BudgetValidation.isUsable(startDate: budget.startDate, hasCategory: budget.category != nil),
                      let startDate = budget.startDate else {
                    return (0, "", HoldingBudget(type: 1, emoji: "failed", name: "", colour: "", budgetAmount: 0))
                }

                let transactions = try context.fetch(dataController.fetchRequestForBudgetTransactions(budget: budget))
                let total = transactions.reduce(0) { $0 + $1.wrappedAmount }
                guard total.isFinite, budget.amount.isFinite else {
                    return (0, "", HoldingBudget(type: 1, emoji: "failed", name: "", colour: "", budgetAmount: 0))
                }
                let holdingBudget = HoldingBudget(
                    type: Int(budget.type),
                    emoji: budget.wrappedEmoji,
                    name: budget.wrappedName,
                    colour: budget.wrappedColour,
                    budgetAmount: budget.amount
                )
                let calendar = Calendar.current
                let timeLeft: String
                if budget.type == 1 {
                    let elapsedHours = calendar.dateComponents([.hour], from: startDate, to: .now).hour ?? 0
                    timeLeft = String(localized: "\(24 - elapsedHours) hours left")
                } else if budget.type == 2 {
                    let elapsedDays = calendar.dateComponents([.day], from: startDate, to: .now).day ?? 0
                    timeLeft = String(localized: "\(7 - elapsedDays) days left")
                } else {
                    let totalDays = calendar.dateComponents([.day], from: startDate, to: budget.endDate).day ?? 0
                    let elapsedDays = calendar.dateComponents([.day], from: startDate, to: .now).day ?? 0
                    timeLeft = String(localized: "\(totalDays - elapsedDays) days left")
                }
                return (total, timeLeft, holdingBudget)
            }
        } catch {
            return (0, "", HoldingBudget(type: 1, emoji: "failed", name: "", colour: "", budgetAmount: 0))
        }
    }
}

struct LockBudgetWidgetEntry: TimelineEntry {
    let date: Date
    let totalSpent: Double
    let timeLeft: String
    let budget: HoldingBudget
    let configuration: BudgetWidgetConfigurationIntent
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
            return "this week"
        }
    }

    var subtitle: String {
        if entry.budget.budgetAmount > entry.totalSpent {
            return String(localized: "left")
        } else {
            return String(localized: "over")
        }
    }

    var difference: Double {
        return abs(entry.budget.budgetAmount - entry.totalSpent)
    }

    var percent: Double {
        return BudgetMath.spendingRatio(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount)
    }

    var gaugePercent: Double {
        return BudgetMath.gaugeRatio(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount)
    }

    var percentString: String {
        return String(localized: "\(BudgetMath.roundedPercentage(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount))% spent")
    }

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var body: some View {
        switch widgetFamily {
        case .accessoryInline:
            if entry.configuration.budget == nil || entry.budget.emoji == "failed" {
                Text("Select budget in widget options")
            } else {
                Text("\(entry.budget.emoji) \(currencySymbol)\(difference, specifier: (showCents && difference < 100) ? "%.2f" : "%.0f") \(subtitle)")
                    .widgetURL(URL(string: "\(AppIdentifiers.urlScheme)://budget?budget=\(entry.budget.name)"))
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
                        Text("\(BudgetMath.roundedPercentage(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount))%")
                    }
                    .gaugeStyle(AccessoryCircularGaugeStyle())
                    .widgetURL(URL(string: "\(AppIdentifiers.urlScheme)://budget?budget=\(entry.budget.name)"))
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
                            Text("\(BudgetMath.roundedPercentage(spent: entry.totalSpent, budgetAmount: entry.budget.budgetAmount))%")
                        }
                        .gaugeStyle(AccessoryCircularGaugeStyle())
                        .widgetURL(URL(string: "\(AppIdentifiers.urlScheme)://budget?budget=\(entry.budget.name)"))
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

                            Text("\(currencySymbol)\(difference, specifier: (showCents && difference < 100) ? "%.2f" : "%.0f") \(subtitle) \(budgetType)")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(Color.SubtitleText)

                            Gauge(value: gaugePercent, in: 0 ... 1) {
                                Text("Percent Spent")
                            } currentValueLabel: {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("\(entry.totalSpent, specifier: (showCents && entry.totalSpent < 100) ? "%.2f" : "%.0f")")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                            } maximumValueLabel: {
                                Text("\(entry.budget.budgetAmount, specifier: (showCents && entry.budget.budgetAmount < 100) ? "%.2f" : "%.0f")")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                            }
                            .frame(height: 5)
                            .gaugeStyle(.accessoryLinear)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .widgetURL(URL(string: "\(AppIdentifiers.urlScheme)://budget?budget=\(entry.budget.name)"))
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

                            Text("\(currencySymbol)\(difference, specifier: (showCents && difference < 100) ? "%.2f" : "%.0f") \(subtitle) \(budgetType)")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundColor(Color.SubtitleText)

                            if #available(iOS 16.0, *) {
                                Gauge(value: gaugePercent, in: 0 ... 1) {
                                    Text("Percent Spent")
                                } currentValueLabel: {
                                    EmptyView()
                                } minimumValueLabel: {
                                    Text("\(entry.totalSpent, specifier: (showCents && entry.totalSpent < 100) ? "%.2f" : "%.0f")")
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                } maximumValueLabel: {
                                    Text("\(entry.budget.budgetAmount, specifier: (showCents && entry.budget.budgetAmount < 100) ? "%.2f" : "%.0f")")
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                }
                                .frame(height: 5)
                                .gaugeStyle(.accessoryLinear)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .widgetURL(URL(string: "\(AppIdentifiers.urlScheme)://budget?budget=\(entry.budget.name)"))
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
