//
//  LogInsightsView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import LittleSaverCore
import CoreData
import Foundation
import Popovers
import SwiftUI

struct NumberView: AnimatableModifier {
    var number: Double
    var dynamicTypeSize: DynamicTypeSize
    let netTotal: Bool
    let positive: Bool

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 46
        case .small:
            return 47
        case .medium:
            return 48
        case .large:
            return 50
        case .xLarge:
            return 56
        case .xxLarge:
            return 58
        case .xxxLarge:
            return 62
        default:
            return 50
        }
    }
    var animatableData: Double {
        get { number }
        set { number = newValue }
    }

    func body(content _: Content) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Group {
                Text(netTotal ? (positive ? "+\(currencySymbol)" : "-\(currencySymbol)") : currencySymbol)
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundColor(Color.SubtitleText) +

                Text("\(number, specifier: showCents  ? "%.2f" : "%.0f")")
                    .font(.system(size: fontSize, weight: .regular, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)

    }
}

struct LogInsightsView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    @AppStorage("logInsightsTimeFrame", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) private var timeframe = 2
    @Binding var navBarText: String
    let showCents: Bool
    let currencySymbol: String
    var body: some View {
        AnalyticsReadView(key: LogRequest(timeframe: timeframe, environment: environment), load: controller.logSnapshot) { snapshot in
            if snapshot.totals.net.isFinite && snapshot.netPoints.allSatisfy({ $0.amount.isFinite }) {
                LogInsightsContent(snapshot: snapshot, readDate: environment.now, navBarText: $navBarText, showCents: showCents, currencySymbol: currencySymbol)
            } else { Text("Amount unavailable").padding() }
        }
    }
}

struct LogInsightsContent: View {
    let snapshot: LogSnapshot
    let readDate: Date
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @Binding var navBarText: String

    let showCents: Bool
    let currencySymbol: String

    @State var showMenu1 = false
    let subtitleText = ["today", "this week", "this month", "this year", "all time"]

    @AppStorage("logInsightsTimeFrame", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var timeframe = 2
    @AppStorage("logInsightsType", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var insightsType = 1

    @AppStorage("logViewLineGraph", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var lineGraph: Bool = false

    var netTotal: (value: Double, positive: Bool) {
        (abs(snapshot.totals.net), snapshot.totals.net >= 0)
    }

    var range: Int {
        var calendar = Calendar(identifier: .gregorian)

        calendar.firstWeekday = UserDefaults(suiteName: AppIdentifiers.appGroup)?.integer(forKey: "firstWeekday") ?? 0
        calendar.minimumDaysInFirstWeek = 4

        if timeframe == 3 {
            let dateComponents = calendar.dateComponents([.month, .year], from: readDate)

            let thisMonth = calendar.date(from: dateComponents) ?? readDate
            let numberOfDays = calendar.dateComponents([.day], from: thisMonth, to: readDate)

            return (numberOfDays.day ?? 0) + 1
        } else if timeframe == 4 {
            let dateComponents = calendar.dateComponents([.year], from: readDate)

            let thisYear = calendar.date(from: dateComponents) ?? readDate

            let numberOfMonths = calendar.dateComponents([.month], from: thisYear, to: readDate)

            return (numberOfMonths.month ?? 0) + 1
        } else {
            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: readDate)
            let thisWeek = calendar.date(from: dateComponents) ?? readDate
            let numberOfDays = calendar.dateComponents([.day], from: thisWeek, to: readDate)

            return (numberOfDays.day ?? 0) + 1
        }
    }

    var totalSpent: Double {
        return snapshot.totals.spent
    }

    var totalIncome: Double {
        return snapshot.totals.income
    }

    var lineGraphData: [LineGraphDataPoint] {
        if insightsType == 1 {
            return snapshot.netPoints
        } else if insightsType == 2 {
            return snapshot.incomePoints
        } else {
            return snapshot.expensePoints
        }
    }

    var lineGraphGreen: Bool {
        if insightsType == 1 {
            return (lineGraphData.first?.amount ?? 0.0) < (lineGraphData.last?.amount ?? 0.0)
        } else if insightsType == 2 {
            return true
        } else {
            return false
        }
    }

    var amount: Double {
        if insightsType == 1 {
            return netTotal.value
        } else if insightsType == 2 {
            return totalIncome
        } else {
            return totalSpent
        }
    }

    var headingText: String {
        if insightsType == 1 {
            return "Net total"
        } else if insightsType == 2 {
            return "Earned"
        } else {
            return "Spent"
        }
    }

    var body: some View {
        VStack(spacing: -3) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(headingText))
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundColor(Color.PrimaryText.opacity(0.9))
                    Button {
                        showMenu1 = true
                    } label: {
                        Text(LocalizedStringKey(subtitleText[timeframe - 1]))
                            .padding(2)
                            .padding(.horizontal, 6)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundColor(Color.PrimaryText.opacity(9))
                            .overlay(Capsule().stroke(Color.Outline, lineWidth: 1.3))
                    }
                    .popover(present: $showMenu1, attributes: {
                        $0.position = .absolute(
                            originAnchor: .bottom,
                            popoverAnchor: .top
                        )
                        $0.rubberBandingMode = .none
                        $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
                        $0.presentation.animation = .easeInOut(duration: 0.2)
                        $0.dismissal.animation = .easeInOut(duration: 0.3)
                    }) {
                        TimePickerView(showMenu: $showMenu1, timeframe: $timeframe)
                    }
                }

                EmptyView()
                    .modifier(NumberView(number: amount, dynamicTypeSize: _dynamicTypeSize.wrappedValue, netTotal: insightsType == 1, positive: netTotal.positive))
            }
            .padding(7)
            .contentShape(Rectangle())
            .contextMenu {
                if insightsType != 3 {
                    Button {
                        insightsType = 3
                    } label: {
                        Label("Total Spent", systemImage: "minus")
                    }
                }

                if insightsType != 2 {
                    Button {
                        insightsType = 2
                    } label: {
                        Label("Total Income", systemImage: "plus")
                    }
                }

                if insightsType != 1 {
                    Button {
                        insightsType = 1
                    } label: {
                        Label("Net Total", systemImage: "alternatingcurrent")
                    }
                }
            }

            if totalSpent != 0 && totalIncome != 0 && insightsType == 1 {
                HStack {
//                    if showCents {
//                        Text("+\(totalIncome, specifier: "%.2f")")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.IncomeGreen)
//                            .lineLimit(1)
//                    } else {
//                        Text("+\(NumericSafety.roundedInt(floor(totalIncome)))")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.IncomeGreen)
//                            .lineLimit(1)
//                    }

                    Text("+\(formatNumber(showCents: showCents, number: totalIncome))")
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.IncomeGreen)
                        .lineLimit(1)

                    DottedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .frame(width: 1.7, height: 15)
                        .foregroundColor(Color.Outline)

                    Text("-\(formatNumber(showCents: showCents, number: totalSpent))")
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .minimumScaleFactor(0.5)
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.AlertRed)
                        .lineLimit(1)

//                    if showCents {
//                        Text("-\(totalSpent, specifier: "%.2f")")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.AlertRed)
//                            .lineLimit(1)
//                    } else {
//                        Text("-\(NumericSafety.roundedInt(floor(totalSpent)))")
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
//                            .foregroundColor(Color.AlertRed)
//                            .lineLimit(1)
//                    }
                }
                .padding(.bottom, 13)
            }

            if lineGraph {
                LineGraph(data: lineGraphData, green: lineGraphGreen, type: timeframe, range: range)
                    .frame(height: 25)
                    .padding(.horizontal, 60)
                    .padding(.top, 16)
            }
        }
        .padding([.bottom, .horizontal], 20)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: lineGraph ? 240 : 170)
    }

    func formatNumber(showCents: Bool, number: Double) -> String {
        guard number.isFinite else { return String(localized: "Amount unavailable") }
        if showCents {
            return String(format: "%.2f", number)
        } else {
            return String(format: "%.0f", floor(number))
        }
    }
}

struct TimePickerView: View {
    @Namespace var animation

    let timeframes = ["today", "this week", "this month", "this year", "all time"]

    @Binding var showMenu: Bool
    @Binding var timeframe: Int
    @State var holdingTimeframe = 0

    @AppStorage("colourScheme", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(timeframes.indices, id: \.self) { index in
                HStack {
                    Text(LocalizedStringKey(timeframes[index]))
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)

                    Spacer()

                    if holdingTimeframe == index + 1 {
                        Image(systemName: "checkmark")
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
//                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
//                .font(.system(size: 18, weight: .medium, design: .rounded))
                .padding(5)
                .background {
                    if holdingTimeframe == index + 1 {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(darkMode ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground"))
                            .matchedGeometryEffect(id: "TAB", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if holdingTimeframe == index + 1 {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            holdingTimeframe = index + 1
                        }

                        timeframe = index + 1

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showMenu = false
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
            }
        }
        .foregroundColor(darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground"))
        .padding(4)
        .frame(width: dynamicTypeSize > .xxLarge ? 185 : 160)
        .background(RoundedRectangle(cornerRadius: 9).fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground")).shadow(color: darkMode ? Color.clear : Color.gray.opacity(0.25), radius: 6))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(darkMode ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
        .onAppear {
            holdingTimeframe = timeframe
        }
    }
}
