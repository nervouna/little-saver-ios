//
//  RecentTransactionsWidget.swift
//  LittleSaverWidget
//
//  Created by Rafael Soh on 12/8/22.
//

import SwiftUI
import WidgetKit

struct RecentLittleSaverWidget: Widget {
    let kind: String = "LittleSaverWidget"

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOSApplicationExtension 17, *) {
            return [
                .accessoryRectangular,
                .accessoryInline,
                .systemSmall,
                .systemLarge
            ]
        } else if #available(iOSApplicationExtension 16, *) {
            return [
                .accessoryRectangular,
                .accessoryInline,
                .systemSmall
            ]
        } else {
            return [.systemSmall]
        }
    }

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: RecentWidgetConfigurationIntent.self, provider: Provider()) { entry in
            LittleSaverWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Recent Transactions")
        .description("View your latest expenses.")
        .supportedFamilies(supportedFamilies)
    }
}

struct Provider: IntentTimelineProvider {
    typealias Intent = RecentWidgetConfigurationIntent

    public typealias Entry = RecentWidgetEntry

    func placeholder(in _: Context) -> RecentWidgetEntry {
        RecentWidgetEntry(date: Date(), amount: loadAmount(type: .week, insightsType: .net), transactions: loadTransactions(type: .week, count: 9), duration: .week, type: .net)
    }

    func getSnapshot(for configuration: RecentWidgetConfigurationIntent, in _: Context, completion: @escaping (RecentWidgetEntry) -> Void) {
        let entry = RecentWidgetEntry(date: Date(), amount: loadAmount(type: configuration.duration, insightsType: configuration.insightsType), transactions: loadTransactions(type: configuration.duration, count: 9), duration: configuration.duration, type: configuration.insightsType)
        completion(entry)
    }

    func getTimeline(for configuration: RecentWidgetConfigurationIntent, in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = RecentWidgetEntry(date: Date(), amount: loadAmount(type: configuration.duration, insightsType: configuration.insightsType), transactions: loadTransactions(type: configuration.duration, count: 9), duration: configuration.duration, type: configuration.insightsType)

        let timeline = Timeline(entries: [entry], policy: .atEnd)

        completion(timeline)
    }

    func loadAmount(type: TimePeriod, insightsType: InsightsType) -> Double {
        let dataController = DataController.shared

        let timeframe: Int

        switch type {
        case .day:
            timeframe = 1
        case .week:
            timeframe = 2
        case .month:
            timeframe = 3
        case .year:
            timeframe = 4
        default:
            timeframe = 0
        }

        do {
            let amount: Double = try dataController.performViewContextRead { context in
                let incomeFilter: Bool?
                switch insightsType {
                case .net:
                    incomeFilter = nil
                case .income:
                    incomeFilter = true
                case .expense:
                    incomeFilter = false
                default:
                    return 0
                }

                let request = dataController.fetchRequestForLogView(
                    type: timeframe,
                    optionalIncome: incomeFilter
                )
                let transactions = try context.fetch(request)
                if insightsType == .net {
                    return TransactionSummary.net(transactions)
                }
                return transactions.reduce(0) { $0 + $1.amount }
            }
            return NumericSafety.finiteOrZero(amount)
        } catch {
            return 0
        }
    }

    func loadTransactions(type: TimePeriod, count: Int) -> [HoldingTransaction] {
        let dataController = DataController.shared
        do {
            return try dataController.performViewContextRead { context in
                let request = dataController.fetchRequestForRecentTransactionsWithCount(type: type, count: count)
                return try context.fetch(request).map { transaction in
                    HoldingTransaction(
                        colour: transaction.category?.wrappedColour ?? "",
                        note: transaction.wrappedNote,
                        amount: NumericSafety.finiteOrZero(transaction.wrappedAmount),
                        income: transaction.income
                    )
                }
            }
        } catch {
            return []
        }
    }
}

struct RecentWidgetEntry: TimelineEntry {
    let date: Date
    let amount: Double
    let transactions: [HoldingTransaction]
    let duration: TimePeriod
    let type: InsightsType
}

struct HoldingTransaction: Hashable {
    let colour: String
    let note: String
    let amount: Double
    let income: Bool
}

struct LittleSaverWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: Provider.Entry

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = Locale.current.currencyCode!
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var summaryText: String {
        localizedFormat("widget.recent.summary", arguments: [typeText, inlineSubtitleText])
    }

    var displayEntryAmount: Double {
        entry.type == .net ? entry.amount : abs(entry.amount)
    }

    var signedInlineAmount: Double {
        switch entry.type {
        case .net: return entry.amount
        case .income: return abs(entry.amount)
        case .expense: return -abs(entry.amount)
        case .unknown: return entry.amount
        }
    }

    func transactionAmount(_ transaction: HoldingTransaction) -> String {
        localizedCurrencyAmount(
            transaction.income ? abs(transaction.amount) : -abs(transaction.amount),
            currencyCode: currency,
            showCents: showCents,
            showPositiveSign: transaction.income
        )
    }

    var inlineSubtitleText: String {
        switch entry.duration {
        case .unknown:
            return "NIL"
        case .day:
            return String(localized: "today")
        case .week:
            return String(localized: "this week")
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return String(localized: "in \(formatter.string(from: Date.now))")
        case .year:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return String(localized: "in \(formatter.string(from: Date.now))")
        }
    }

    var typeText: String {
        switch entry.type {
        case .unknown:
            return ""
        case .net:
            return String(localized: "net")
        case .income:
            return String(localized: "earned")
        case .expense:
            return String(localized: "spent")
        }
    }

    var body: some View {
        switch widgetFamily {
        case .accessoryInline:
            Text(localizedFormat(
                "widget.recent.inline.summary",
                arguments: [localizedCurrencyAmount(signedInlineAmount, currencyCode: currency, showCents: showCents, showPositiveSign: signedInlineAmount > 0), typeText, inlineSubtitleText]
            ))
        case .accessoryRectangular:
            if #available(iOS 17.0, *) {
                if entry.transactions.count == 0 {
                    Text("NO RECENT EXPENSES")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .containerBackground(for: .widget) { Color.clear }
                } else {
                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(entry.transactions.prefix(3), id: \.self) { transaction in
                                HStack(spacing: 3) {
                                    Text(transaction.note)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(transactionAmount(transaction))
                                        .fontWeight(.regular)
                                        .layoutPriority(1)
                                        .lineLimit(1)
                                }
                                .font(.system(size: getRectangularWidgetFont(width: proxy.size.width), design: .rounded))
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .containerBackground(for: .widget) { Color.clear }
                }
            } else {
                if entry.transactions.count == 0 {
                    Text("NO RECENT EXPENSES")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                } else {
                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(entry.transactions.prefix(3), id: \.self) { transaction in
                                HStack(spacing: 3) {
                                    Text(transaction.note)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(transactionAmount(transaction))
                                        .fontWeight(.regular)
                                        .layoutPriority(1)
                                        .lineLimit(1)
                                }
                                .font(.system(size: getRectangularWidgetFont(width: proxy.size.width), design: .rounded))
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case .systemSmall:
            if #available(iOS 17.0, *) {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Text(summaryText.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.SubtitleText)

                            RecentTransactionsDollarView(amount: displayEntryAmount, currencyCode: currency, showCents: showCents, showPositiveSign: entry.type == .net, bigger: true)
                            .frame(maxWidth: .infinity)
                            .frame(height: proxy.size.height * 0.27)
                        }
                        .frame(maxWidth: .infinity)

                        if entry.transactions.isEmpty {
                            VStack(spacing: 5) {
                                Text("NO RECENT EXPENSES")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.SubtitleText)
                                    .frame(maxHeight: .infinity)

                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))

                                    Text("New Expense")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.PrimaryText)
                                }
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.SecondaryBackground))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                            .padding(.top, 12)

                        } else {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("RECENT EXPENSES")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.SubtitleText)

                                ForEach(entry.transactions.prefix(3), id: \.self) { transaction in
                                    HStack(spacing: 5) {
                                        Capsule()
                                            .fill(Color(hex: transaction.colour))
                                            .frame(width: 4, height: 12)

                                        Text(transaction.note)
                                            .lineLimit(1)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .foregroundColor(Color.PrimaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if transaction.income {
                                            Text(transactionAmount(transaction))
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .foregroundColor(Color.IncomeGreen)
                                                .lineLimit(1)
                                                .layoutPriority(1)
                                        } else {
                                            Text(transactionAmount(transaction))
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                                .lineLimit(1)
                                                .layoutPriority(1)
                                        }
                                    }
                                }

                                if entry.transactions.count < 2 {
                                    HStack(spacing: 5) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))

                                        Text("New Expense")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(Color.PrimaryText)
                                    }
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.SecondaryBackground))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                }
                            }
                            .padding(.top, entry.transactions.count >= 3 ? 5 : 10)
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(for: .widget) {
                    Color.PrimaryBackground
                }
                .widgetURL(entry.transactions.count < 2 ? DeepLink.newExpense.url : nil)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } else {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Text(summaryText.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.SubtitleText)

                            RecentTransactionsDollarView(amount: displayEntryAmount, currencyCode: currency, showCents: showCents, showPositiveSign: entry.type == .net)
                            .frame(maxWidth: .infinity)
                            .frame(height: proxy.size.height * 0.2)
                        }
                        .frame(maxWidth: .infinity)

                        if entry.transactions.isEmpty {
                            VStack(spacing: 5) {
                                Text("NO RECENT EXPENSES")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.SubtitleText)
                                    .frame(maxHeight: .infinity)

                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))

                                    Text("New Expense")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.PrimaryText)
                                }
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.SecondaryBackground))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                            .padding(.top, 12)

                        } else {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("RECENT EXPENSES")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.SubtitleText)

                                ForEach(entry.transactions.prefix(3), id: \.self) { transaction in
                                    HStack(spacing: 5) {
                                        Capsule()
                                            .fill(Color(transaction.colour))
                                            .frame(width: 4, height: 12)

                                        Text(transaction.note)
                                            .lineLimit(1)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .foregroundColor(Color.PrimaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if transaction.income {
                                            Text(transactionAmount(transaction))
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .foregroundColor(Color.IncomeGreen)
                                                .lineLimit(1)
                                                .layoutPriority(1)
                                        } else {
                                            Text(transactionAmount(transaction))
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                                .lineLimit(1)
                                                .layoutPriority(1)
                                        }
                                    }
                                }

                                if entry.transactions.count < 2 {
                                    HStack(spacing: 5) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))

                                        Text("New Expense")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(Color.PrimaryText)
                                    }
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.SecondaryBackground))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                }
                            }
                            .padding(.top, entry.transactions.count == 3 ? 5 : 10)
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .padding(15)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.PrimaryBackground)
                .widgetURL(entry.transactions.count < 2 ? DeepLink.newExpense.url : nil)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }

        case .systemLarge:
            if #available(iOS 17.0, *) {
                GeometryReader { _ in
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Text(summaryText.uppercased())
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.SubtitleText)

                            RecentTransactionsDollarView(amount: displayEntryAmount, currencyCode: currency, showCents: showCents, showPositiveSign: entry.type == .net)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()
                            .frame(minHeight: 5, idealHeight: 15, maxHeight: 20)
                            .fixedSize()

                        if entry.transactions.isEmpty {
                            VStack(spacing: 20) {
                                Text("NO RECENT EXPENSES")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.SubtitleText)

                                Link(destination: DeepLink.newExpense.url) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))

                                        Text("New Expense")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundColor(Color.PrimaryText)
                                    }
                                    .padding(.vertical, 6)
                                    .frame(width: 200)
                                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.SecondaryBackground))
                                }
                            }
                            .frame(maxHeight: .infinity)

                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("RECENT EXPENSES")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.SubtitleText)

                                ForEach(entry.transactions, id: \.self) { transaction in
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(hex: transaction.colour))
                                            .frame(width: 15, height: 15)

                                        Text(transaction.note)
                                            .lineLimit(1)
                                            .font(.system(size: 16, weight: .medium, design: .rounded))
                                            .foregroundColor(Color.PrimaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if transaction.income {
                                            Text(transactionAmount(transaction))
                                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                                .foregroundColor(Color.IncomeGreen)
                                                .lineLimit(1)
                                                .layoutPriority(1)
                                        } else {
                                            Text(transactionAmount(transaction))
                                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                                .foregroundColor(Color.SubtitleText)
                                                .lineLimit(1)
                                                .layoutPriority(1)
                                        }
                                    }
                                }

                                if entry.transactions.count < 5 {
                                    Link(destination: DeepLink.newExpense.url) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))

                                            Text("New Expense")
                                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                .foregroundColor(Color.PrimaryText)
                                        }
                                        .padding(.vertical, 6)
                                        .frame(width: 200)
                                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.SecondaryBackground))
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                }
                            }
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(for: .widget) {
                    Color.PrimaryBackground
                }
            }

        default:
            EmptyView()
        }
    }

    func getRectangularWidgetFont(width: CGFloat) -> CGFloat {
        var fontSize = 15.0

        while fontSize > 12 {
            var max = 0.0
            entry.transactions.forEach { transaction in
                let amountText = transactionAmount(transaction)

                let holding = transaction.note.widthOfRoundedString(size: fontSize, weight: .semibold) + amountText.widthOfRoundedString(size: fontSize, weight: .regular) + 8

                if holding > max {
                    max = holding
                }
            }

            if width > max {
                return fontSize
            }

            fontSize -= 1
        }

        return 12
    }
}

struct RecentTransactionsDollarView: View {
    var amount: Double
    var currencyCode: String
    var showCents: Bool
    var showPositiveSign: Bool
    var bigger: Bool = false

    var body: some View {
        Text(localizedCurrencyAmount(amount, currencyCode: currencyCode, showCents: showCents, showPositiveSign: showPositiveSign))
            .font(.system(bigger ? .title : .title3, design: .rounded).weight(.medium))
            .foregroundColor(Color.PrimaryText)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}
