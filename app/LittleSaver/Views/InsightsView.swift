//
//  InsightsView.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import SwiftUIIntrospect
import Popovers
import SwiftUI

struct InsightsView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @Environment(\.ledgerMetadata) private var metadata

    @State private var showTimeMenu = false
    @AppStorage("chartTimeFrame", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var chartType = 1


    var chartTypeString: String {
        if chartType == 1 {
            return String(localized: "week")
        } else if chartType == 2 {
            return String(localized: "month")
        } else if chartType == 3 {
            return String(localized: "year")
        } else {
            return ""
        }
    }

//    @State private var holdingIncome = false
//    @Namespace var animation

    var body: some View {
        let _ = calendarRevision
        if metadata == nil { ProgressView() }
        else if metadata?.hasTransactions != true {
            VStack(spacing: 5) {
                Image("chart")
                    .resizable()
                    .frame(width: 75, height: 75)
                    .padding(.bottom, 20)

                Text("Analyse Your Expenditure")
                    .font(.system(.title2, design: .rounded).weight(.medium))
//                    .font(.system(size: 23.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText.opacity(0.8))
                    .multilineTextAlignment(.center)

                Text("As transactions start piling up")
                    .font(.system(.body, design: .rounded).weight(.medium))
//                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
            .frame(height: 250, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .background(Color.PrimaryBackground)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

        } else {
            VStack(spacing: 5) {
                HStack {
                    Text("Insights")
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .accessibility(addTraits: .isHeader)
                    Spacer()

                    Button {
                        showTimeMenu = true
                    } label: {
                        HStack(spacing: 4.5) {
                            Text(chartTypeString)
                                .font(.system(.body, design: .rounded).weight(.medium))

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                        }
                        .padding(3)
                        .padding(.horizontal, 6)
                        .foregroundColor(Color.PrimaryText.opacity(0.9))
                        .background(Color.Outline, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .popover(present: $showTimeMenu, attributes: {
                        $0.position = .absolute(
                            originAnchor: .bottomRight,
                            popoverAnchor: .topRight
                        )
                        $0.rubberBandingMode = .none
                        $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
                        $0.presentation.animation = .easeInOut(duration: 0.2)
                        $0.dismissal.animation = .easeInOut(duration: 0.3)
                    }) {
                        ChartTimePickerView(showMenu: $showTimeMenu)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)
                .padding(.bottom, 20)

                if chartType == 1 {
                    WeekGraphView()
                } else if chartType == 2 {
                    MonthGraphView()
                } else if chartType == 3 {
                    YearGraphView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.PrimaryBackground)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

struct HorizontalPieChartView: View {
    @Environment(\.managedObjectContext) private var context
    let snapshot: BucketSnapshot

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var income: Bool
    var date: Date
    var total: Double { snapshot.amount }

    @Binding var chosenAmount: Double
    @Binding var chosenName: String

    @Binding var categoryFilterMode: Bool
    @Binding var categoryFilter: Category?
    @Binding var selectedDate: Date?

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 12
        case .small:
            return 13
        case .medium:
            return 14
        case .large:
            return 15
        case .xLarge:
            return 17
        case .xxLarge:
            return 19
        case .xxxLarge:
            return 21
        default:
            return 15
        }
    }

    var percentWidth: CGFloat {
        return "100%".widthOfRoundedString(size: fontSize, weight: .medium) + 4
    }

    var categories: [PowerCategory] {
        snapshot.categories.compactMap { row in
            guard let category: Category = presentationObject(row.id, in: context) else { return nil }
            return PowerCategory(id: row.id, category: category, percent: row.percent, amount: row.amount)
        }
    }

    var body: some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !categoryFilterMode {
                    Text("Categories")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.SubtitleText)

                    GeometryReader { proxy in
                        HStack(spacing: proxy.size.width * 0.015) {
                            ForEach(categories) { category in
                                if category.percent < 0.005 {
                                    EmptyView()
                                } else {
                                    AnimatedHorizontalBarGraph(category: category, index: categories.firstIndex(of: category) ?? 0)
                                        .frame(width: (proxy.size.width * (1.0 - (0.015 * Double(categories.count - 1)))) * category.percent)
                                        .onTapGesture {
                                            withAnimation(.easeInOut) {
                                                if categoryFilter == category.category {
                                                    selectedDate = nil
                                                    categoryFilterMode = false
                                                    categoryFilter = nil
                                                } else {
                                                    selectedDate = nil
                                                    categoryFilterMode = true
                                                    categoryFilter = category.category
                                                    chosenAmount = category.amount
                                                    chosenName = category.category.wrappedName
                                                }
                                            }
                                        }
                                        .opacity(categoryFilterMode ? (categoryFilter == category.category ? 1 : 0.5) : 1)
                                        .overlay {
                                            if categoryFilterMode && categoryFilter == category.category {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(Color.DarkBackground, lineWidth: 1.5)
                                            }
                                        }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 17)
                    .padding(.bottom, 10)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(categories, id: \.self) { category in
                            if !categoryFilterMode || categoryFilter == category.category {
                                let boxColor = category.category.income ? Color(hex: Color.colorArray[categories.firstIndex(of: category) ?? 0]) : Color(hex: category.category.wrappedColour)

                                HStack(spacing: 10) {

                                    Text(category.category.fullName)
                                        .font(.system(.title3, design: .rounded).weight(.semibold))
                                        .foregroundColor(Color.PrimaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(currencySymbol)\(category.amount, specifier: (showCents && category.amount < 100) ? "%.2f" : "%.0f")")
                                        .font(.system(categoryFilterMode && categoryFilter == category.category ? .title3 : .body, design: .rounded).weight(.medium))
                                        .foregroundColor(Color.SubtitleText)
                                        .lineLimit(1)
                                        .layoutPriority(1)

                                    if categoryFilterMode && categoryFilter == category.category {
                                        Button {
                                            withAnimation(.easeInOut) {
                                                selectedDate = nil
                                                categoryFilterMode = false
                                                categoryFilter = nil
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                                .foregroundColor(Color.SubtitleText)
                                                .padding(5)
                                                .background(Color.SecondaryBackground, in: Circle())
                                        }

                                    } else {

                                        Text("\(category.percent * 100, specifier: "%.0f")%")
                                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                            .foregroundColor(boxColor)
                                            .padding(.vertical, 3)
                                            .frame(width: percentWidth)
                                            .background(boxColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                .padding(.vertical, categoryFilterMode && categoryFilter == category.category ? 10 : 5)
                                .padding(.horizontal, categoryFilterMode && categoryFilter == category.category ? 10 : 0)
                                .background(RoundedRectangle(cornerRadius: 12).fill(categoryFilterMode && categoryFilter == category.category ? Color.TertiaryBackground : Color.PrimaryBackground))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(categoryFilterMode && categoryFilter == category.category ? Color.Outline : Color.clear, lineWidth: 1.3))
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .drawingGroup()
                                .onTapGesture {
                                    withAnimation(.easeInOut) {
                                        if !categoryFilterMode {
                                            selectedDate = nil
                                            categoryFilterMode = true
                                            categoryFilter = category.category
                                            chosenAmount = category.amount
                                            chosenName = category.category.wrappedName
                                        }
                                    }
                                }

                            }

                        }
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    init(date: Date, categoryFilter: Binding<Category?>?, categoryFilterMode: Binding<Bool>, selectedDate: Binding<Date?>?, chosenAmount: Binding<Double>, chosenName: Binding<String>, type: ChartTimeFrame, income: Bool, snapshot: BucketSnapshot) {
        self.date = date
        self.income = income
        _categoryFilter = categoryFilter ?? Binding.constant(nil)
        _categoryFilterMode = categoryFilterMode
        _selectedDate = selectedDate ?? Binding.constant(nil)
        _chosenName = chosenName
        _chosenAmount = chosenAmount

        self.snapshot = snapshot
    }
}

struct FilteredCategoryInsightsView: View {
    @AnalyticsInput private var environment
    let category: Category?
    let date: Date
    let type: ChartTimeFrame
    var body: some View {
        let kind = type == .week ? 1 : type == .month ? 2 : 3
        let end = LedgerCalendar.insightsEnd(start: date, type: kind, firstDayOfMonth: environment.firstDayOfMonth, calendar: environment.calendar) ?? date
        if let category {
            SnapshotTransactionsView(query: .interval(start: date, end: end, income: category.income, category: category.objectID.uriRepresentation()))
        } else { NoResultsView(fullscreen: false) }
    }
}

struct FilteredDateInsightsView: View {
    @AnalyticsInput private var environment
    let date: Date
    let income: Bool
    var chartType = 1
    var body: some View {
        SnapshotTransactionsView(query: .insightsDrilldown(date: date, chartType: chartType, income: income, environment: environment), dayHeaders: chartType == 3)
    }
}

struct FilteredInsightsView: View {
    @AnalyticsInput private var environment
    let startDate: Date
    var income: Bool? = nil
    let type: Int
    var naturalMonth = false
    var body: some View {
        let end = naturalMonth ? environment.calendar.dateInterval(of: .month, for: startDate)?.end : LedgerCalendar.insightsEnd(start: startDate, type: type, firstDayOfMonth: environment.firstDayOfMonth, calendar: environment.calendar)
        SnapshotTransactionsView(query: .interval(start: startDate, end: end ?? startDate, income: income, category: nil))
    }
}

struct SingleGraphView: View {
    let snapshot: InsightsSnapshot
    var date: Date
    let type: Int

    @Binding var categoryFilterMode: Bool
    @Binding var selectedDate: Date?

    @AppStorage("incomeTracking", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var incomeTracking: Bool = true
    let language = Locale.current.languageCode

    var selectedDateString: String {
        if let unwrappedDate = selectedDate {
            let dateFormatter = DateFormatter()

            if type == 3 {
                dateFormatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
            } else {
                dateFormatter.dateStyle = .medium
            }

            if language == "ru" {
                return dateFormatter.string(from: unwrappedDate)
            } else {
                return dateFormatter.string(from: unwrappedDate)
            }
        } else {
            return ""
        }
    }

    var selectedDateAmount: Double {
        guard let selectedDate else { return 0 }
        return (income ? snapshot.income : snapshot.expenses).totals[selectedDate] ?? 0
    }

    var currencySymbol: String
    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var showCents: Bool

    @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var firstDayOfMonth: Int = 1

    var dateString: String {
        let dateFormatter = DateFormatter()

        if type == 1 {
            let calendar = Calendar.current
            dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
            let endComponents = DateComponents(day: 7, second: -1)
            let endWeekDate = calendar.date(byAdding: endComponents, to: date) ?? Date.now

            let startMonth = calendar.component(.month, from: date)
            let endMonth = calendar.component(.month, from: endWeekDate)

            if startMonth == endMonth {
                let anotherDateFormatter = DateFormatter()
                anotherDateFormatter.setLocalizedDateFormatFromTemplate("d")

                return anotherDateFormatter.string(from: date) + " - " + dateFormatter.string(from: endWeekDate)
            } else {
                return dateFormatter.string(from: date) + " - " + dateFormatter.string(from: endWeekDate)
            }
        } else if type == 2 {
            if firstDayOfMonth == 1 {
                dateFormatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
            } else {
                dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                let endMonthDate = LedgerCalendar.insightsEnd(start: date, type: 2, firstDayOfMonth: firstDayOfMonth)?.addingTimeInterval(-1) ?? date
                if language == "ru" {
                    return dateFormatter.string(from: date) + " - " + dateFormatter.string(from: endMonthDate)
                } else {
                    return dateFormatter.string(from: date)  + " - " + dateFormatter.string(from: endMonthDate)
                }
            }
        } else if type == 3 {
            dateFormatter.setLocalizedDateFormatFromTemplate("yyyy")
        }

        if language == "ru" {
            return dateFormatter.string(from: date)
        } else {
            return dateFormatter.string(from: date)
        }
    }

    var selectedCategoryName: String
    var selectedCategoryAmount: Double

    @Binding var income: Bool
    @Binding var incomeFiltering: Bool

    let totalIncome: Double
    let totalSpent: Double
    let totalNet: Double
    let netPositive: Bool
    let currentNet: Double
    let lastNet: Double
    let average: Double

    var incomeAverage: Double { (income ? snapshot.income : snapshot.expenses).average }

    var percentageDifference: String {
        guard currentNet.isFinite, lastNet.isFinite, lastNet != 0 else { return "—" }
        let percentage = ((currentNet - lastNet) / abs(lastNet)) * 100
        guard percentage.isFinite else { return currentNet > lastNet ? ">999%" : "<−999%" }
        return String(format: currentNet > lastNet ? "+%.0f%%" : "%.0f%%", ceil(percentage))
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 14
        case .small:
            return 15
        case .medium:
            return 16
        case .large:
            return 17
        case .xLarge:
            return 19
        case .xxLarge:
            return 21
        case .xxxLarge:
            return 23
        default:
            return 23
        }
    }

    var showPercentage: Bool {
        let amountText = stringConverter(amount: totalNet)
        let supplementalText: String

        if categoryFilterMode {
            supplementalText = stringConverter(amount: selectedCategoryAmount)
        } else if selectedDate != nil {
            supplementalText = stringConverter(amount: selectedDateAmount)
        } else if incomeFiltering {
            supplementalText = stringConverter(amount: incomeAverage)
        } else {
            supplementalText = stringConverter(amount: average)
        }

        let totalWidth = amountText.widthOfRoundedString(size: UIFont.textStyleSize(.title1), weight: .medium)
        let averageWidth = supplementalText.widthOfRoundedString(size: UIFont.textStyleSize(.title1), weight: .medium)
        let percentageWidth = percentageDifference.widthOfRoundedString(size: UIFont.textStyleSize(.footnote), weight: .medium) + 10

        let screenWidth = UIScreen.main.bounds.width - 60

        return totalWidth + averageWidth + percentageWidth + 40 < screenWidth
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1.3) {
                    Text(dateString)
                        .lineLimit(1)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.SubtitleText)
                        .layoutPriority(1)

                    HStack(spacing: 10) {
                        InsightsDollarView(amount: totalNet, currencySymbol: currencySymbol, showCents: showCents, net: netPositive)
                            .layoutPriority(1)

                        if showPercentage {
                            Text(percentageDifference)
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                                .foregroundColor(currentNet < lastNet ? Color.AlertRed : Color.IncomeGreen)
                                .padding(3)
                                .padding(.horizontal, 3)
                                .background(currentNet < lastNet ? Color.AlertRed.opacity(0.23) : Color.IncomeGreen.opacity(0.23), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .opacity(currentNet == 0 || lastNet == 0 ? 0 : 1)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if categoryFilterMode {
                    VStack(alignment: .trailing, spacing: 1.3) {
                        Text(selectedCategoryName)
                            .lineLimit(1)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
//                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.SubtitleText)

                        InsightsDollarView(amount: selectedCategoryAmount, currencySymbol: currencySymbol, showCents: showCents)
                            .layoutPriority(1)
                    }
                } else if selectedDate != nil {
                    VStack(alignment: .trailing, spacing: 1.3) {
                        Text(selectedDateString)
                            .lineLimit(1)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                        InsightsDollarView(amount: selectedDateAmount, currencySymbol: currencySymbol, showCents: showCents)
                            .layoutPriority(1)
                    }
                } else if incomeFiltering {
                    VStack(alignment: .trailing, spacing: 1.3) {
                        Text(LocalizedStringKey(type == 3 ? (income ? "Income/Mth" : "Spent/Mth") : (income ? "Income/Day" : "Spent/Day")))
                            .lineLimit(1)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                        InsightsDollarView(amount: incomeAverage, currencySymbol: currencySymbol, showCents: showCents)
                            .layoutPriority(1)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 1.3) {
                        Text(LocalizedStringKey(type == 3 ? "AVG/MTH" : "AVG/DAY"))
                            .lineLimit(1)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                        InsightsDollarView(amount: average, currencySymbol: currencySymbol, showCents: showCents, net: netPositive)
                            .layoutPriority(1)
                    }
                }
            }
            .padding(.bottom, 5)
            .onTapGesture {
                withAnimation(.easeIn(duration: 0.2)) {
                    selectedDate = nil
                }
            }

            if incomeTracking {
                HStack(spacing: 11) {
                    InsightsSummaryBlockView(income: true, amountString: stringGenerator(amount: totalIncome), showOverlay: income && incomeFiltering) {
                        withAnimation {
                            if incomeFiltering && income {
                                incomeFiltering = false
                            } else {
                                income = true
                                incomeFiltering = true
                            }
                        }
                    }

                    InsightsSummaryBlockView(income: false, amountString: stringGenerator(amount: totalSpent), showOverlay: !income && incomeFiltering) {
                        withAnimation {
                            if incomeFiltering && !income {
                                incomeFiltering = false
                            } else {
                                income = false
                                incomeFiltering = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 13)
            }

            if incomeFiltering {
                if type == 1 {
                    SingleWeekBarGraphView(week: date, date: $selectedDate, mode: $categoryFilterMode, snapshot: income ? snapshot.income : snapshot.expenses)
                } else if type == 2 {
                    SingleMonthBarGraphView(month: date, date: $selectedDate, mode: $categoryFilterMode, snapshot: income ? snapshot.income : snapshot.expenses)
                } else if type == 3 {
                    SingleYearBarGraphView(year: date, date: $selectedDate, mode: $categoryFilterMode, snapshot: income ? snapshot.income : snapshot.expenses)
                }
            }
        }
    }

    func stringGenerator(amount: Double) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        if showCents && amount < 1000 {
            numberFormatter.maximumFractionDigits = 2
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        return numberFormatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

    func stringConverter(amount: Double) -> String {
        if showCents && amount < 100 {
            return currencySymbol + String(format: "%.2f", amount)
        } else {
            return currencySymbol + String(format: "%.0f", amount)
        }
    }

    init(showingDate: Date, date: Binding<Date?>?, mode: Binding<Bool>, categoryName: String, categoryAmount: Double, currencySymbol: String, showCents: Bool, snapshot: InsightsSnapshot, income: Binding<Bool>, incomeFiltering: Binding<Bool>, type: Int) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode
        _income = income
        _incomeFiltering = incomeFiltering
        self.date = showingDate
        selectedCategoryName = categoryName
        selectedCategoryAmount = categoryAmount
        self.currencySymbol = currencySymbol
        self.showCents = showCents
        self.type = type

        self.snapshot = snapshot
        totalIncome = snapshot.current.income
        totalSpent = snapshot.current.spent
        netPositive = snapshot.current.net >= 0
        totalNet = abs(snapshot.current.net)
        average = snapshot.current.average
        currentNet = snapshot.current.net
        lastNet = snapshot.previous.net
    }
}

struct WeekGraphView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @EnvironmentObject var dataController: DataController
    @AnalyticsInput private var environment
    @Environment(\.ledgerMetadata) private var metadata



    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    @State var categoryFilterMode = false
    @State var categoryFilter: Category?

    @State private var selectedDay: CalendarPeriodSelection?
    var selectedDate: Date? {
        get { selectedDay?.start(period: .day, now: environment.now, calendar: environment.calendar) }
        nonmutating set { selectedDay = newValue.map { CalendarPeriodSelection(start: $0, calendar: environment.calendar) } }
    }

    var startOfCurrentWeek: Date {
        CalendarPeriodSelection().start(period: .week, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth)
    }

    // start of week of final transaction
    var startOfLastWeek: Date {
        CalendarPeriodSelection(start: metadata?.earliestDate ?? environment.now, calendar: environment.calendar).start(period: .week, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth)
    }

    var swipeStrings: (backward: String, forward: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")

        let calendar = environment.calendar

        let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: showingWeek) ?? environment.now
        let startOfNextWeek = calendar.date(byAdding: .day, value: 7, to: showingWeek) ?? environment.now

        return (dateFormatter.string(from: startOfLastWeek), dateFormatter.string(from: startOfNextWeek))
    }

    @State private var offset: CGFloat = 0
    @State private var changeDate: Bool = false
    @GestureState var isDragging = false
    var changeTime: Bool {
        if offset < -(UIScreen.main.bounds.width * 0.25) && showingWeek != startOfCurrentWeek {
            return true
        } else if offset > (UIScreen.main.bounds.width * 0.25) && showingWeek != startOfLastWeek {
            return true
        } else {
            return false
        }
//
//        return abs(offset) > UIScreen.main.bounds.width * 0.3
    }

    @State private var periodSelection = CalendarPeriodSelection()
    var showingWeek: Date {
        get { periodSelection.start(period: .week, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth) }
        nonmutating set { periodSelection.select(newValue, period: .week, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth) }
    }


    @State var chosenCategoryName = ""
    @State var chosenCategoryAmount = 0.0

    @AppStorage("insightsViewIncomeFiltering", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var income: Bool = true
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var incomeTracking: Bool = true

//    @Environment(\.dynamicTypeMultiplier) var multiplier

    @State var incomeFiltering: Bool = true

    var body: some View {
        let request = InsightsRequest(start: showingWeek, type: 1, environment: environment)
        AnalyticsReadView(key: request, load: dataController.analyticsInsightsSnapshot) { snapshot in
            if snapshot.current.spent.isFinite && snapshot.current.income.isFinite {
                graphContent(snapshot)
            } else { Text("Amount unavailable").padding() }
        }
    }

    @ViewBuilder private func graphContent(_ snapshot: InsightsSnapshot) -> some View {
        let selectedCategory = (income ? snapshot.income : snapshot.expenses).categories.first { $0.id == categoryFilter?.objectID.uriRepresentation() }
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                ZStack {
                    SingleGraphView(showingDate: showingWeek, date: Binding(get: { selectedDate }, set: { selectedDate = $0 }), mode: Binding(get: { categoryFilterMode && selectedCategory != nil }, set: { categoryFilterMode = $0 }), categoryName: selectedCategory?.category.name ?? "", categoryAmount: selectedCategory?.amount ?? 0, currencySymbol: currencySymbol, showCents: showCents, snapshot: snapshot, income: $income, incomeFiltering: $incomeFiltering, type: 1)
                        .drawingGroup()
                        .offset(x: offset)

                    if !changeDate {
                        HStack {
                            if showingWeek != startOfLastWeek {
                                SwipeArrowView(left: true, swipeString: swipeStrings.backward.uppercased(), changeTime: changeTime)
                                .offset(x: -100)
                                .offset(x: min(100, offset))
                            } else {
                                SwipeEndView(left: true)
                                .offset(x: -120)
                                .offset(x: min(120, offset))
                            }

                            Spacer()
                        }

                        HStack {
                            Spacer()

                            if showingWeek != startOfCurrentWeek {
                                SwipeArrowView(left: false, swipeString: swipeStrings.forward.uppercased(), changeTime: changeTime)
                                .offset(x: 100)
                                .offset(x: max(-100, offset))
                            } else {
                                SwipeEndView(left: false)
                                .offset(x: 120)
                                .offset(x: max(-120, offset))
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 30)
                .simultaneousGesture(
                    DragGesture()
                        .updating($isDragging, body: { _, state, _ in
                            state = true
                        })
                        .onChanged { value in
                            withAnimation {
                                if value.translation.width < 0, showingWeek != startOfCurrentWeek {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width < 0, showingWeek == startOfCurrentWeek {
                                    offset = value.translation.width * 0.5
                                } else if value.translation.width > 0, showingWeek != startOfLastWeek {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width > 0, showingWeek == startOfLastWeek {
                                    offset = value.translation.width * 0.5
                                }
                            }
                        }.onEnded { _ in
                            if changeTime {
                                if offset < 0, showingWeek != startOfCurrentWeek {
                                    changeDate = true

                                    offset = UIScreen.main.bounds.width

                                    showingWeek = environment.calendar.date(byAdding: .day, value: 7, to: showingWeek) ?? environment.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                } else if offset > 0, showingWeek != startOfLastWeek {
                                    changeDate = true

                                    offset = -UIScreen.main.bounds.width

                                    showingWeek = environment.calendar.date(byAdding: .day, value: -7, to: showingWeek) ?? environment.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                }

                                withAnimation(.easeInOut(duration: 0.3)) {
                                    offset = 0
                                }

                                changeDate = false
                            }
                        }
                )
                .onChange(of: changeTime) { _ in
                    if changeTime {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onChange(of: isDragging) { _ in
                    if !isDragging && !changeDate {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                        }
                    }
                }
                .animation(.easeInOut, value: changeTime)
                .onChange(of: showingWeek) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: income) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: incomeFiltering) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .padding(.bottom, incomeFiltering ? 5 : 10)

                Group {
                    if !incomeFiltering {
                        FilteredInsightsView(startDate: showingWeek, type: 1)
                            .padding(.bottom, 70)
                            .padding(.horizontal, 20)
                    } else {
                        if selectedDate == nil {
                            HorizontalPieChartView(date: showingWeek, categoryFilter: $categoryFilter, categoryFilterMode: $categoryFilterMode, selectedDate: Binding(get: { selectedDate }, set: { selectedDate = $0 }), chosenAmount: $chosenCategoryAmount, chosenName: $chosenCategoryName, type: .week, income: income, snapshot: income ? snapshot.income : snapshot.expenses)
                                .padding(.horizontal, 30)
                                .padding(.bottom, 70)

                            if categoryFilterMode {
                                FilteredCategoryInsightsView(category: categoryFilter, date: showingWeek, type: .week)
                                    .padding(.bottom, 70)
                                    .padding(.horizontal, 20)
                            }
                        } else {
                            FilteredDateInsightsView(date: selectedDate ?? environment.now, income: income)
                                .padding(.bottom, 70)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .onTapGesture {
                    selectedDate = nil
                    categoryFilterMode = false
                }
            }
        }
    }
}

struct AverageLineView: View {
    var getMax: Double
    var average: Double

//    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true
//    @State var showLine: Bool = false
//    @State var offset: CGFloat

//    var calculatedOffset: CGFloat {
//        return getOffset(maxi: getMax, average: average)
//    }

    var body: some View {
        HStack(spacing: 2) {
            PencilView(text: getAverageText(average: average))

            Line()
                .stroke(Color.SubtitleText, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5]))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
//        .opacity(showLine ? 1 : 0)
        .offset(y: getOffset(maxi: getMax, average: average))
        .opacity((NumericSafety.safeRatio(average, getMax)) < 0.1 || (NumericSafety.safeRatio(average, getMax)) > 0.9 ? 0 : 1)
//        .onAppear {
//            DispatchQueue.main.sync {
//                withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
//                    print(calculatedOffset)
//                    offset = calculatedOffset
//                }
//            }
//        }
//        .onChange(of: showLine) { newValue in
//            if newValue {
//                DispatchQueue.main.asyncAfter(deadline: .now()) {
//                    if !animated {
//                        offset = calculatedOffset
//                    } else {
//                        
//                    }
//                }
//            }
//        }
//        .onChange(of: calculatedOffset) { newValue in
//            print(calculatedOffset)
//            if newValue != 0 {
//                if showLine {
//                    if !animated {
//                        offset = calculatedOffset
//                    } else {
//                        withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
//                            offset = calculatedOffset
//                        }
//                    }
//                }
//            }
//        }

    }
}

struct SingleWeekBarGraphView: View {
    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool


    var daysOfWeek = [Date]()

    var dayDictionary = [Date: Double]()

    var max: Double = 0
    var weekTotal: Double = 0
    var weekAverage: Double = 0
    var actualDays: Int = 0

    var getMax: Double {
        return NumericSafety.graphMaximum(max)
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 8) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(spacing: 7) {
                    ForEach(daysOfWeek, id: \.self) { day in
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.SecondaryBackground)
                                    .frame(height: barHeight)

                                AnimatedBarGraph(index: daysOfWeek.firstIndex(of: day) ?? 0)
                                    .frame(height: getBarHeight(point: dayDictionary[day] ?? 0, maxi: getMax))
                                    .opacity(selectedDate == nil ? 1 : (selectedDate == day ? 1 : 0.4))
                            }

                            Text(getWeekday(day: day).prefix(1))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                        }
                        .opacity(day > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(day > Date.now))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == day {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = day
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            // average line
            AverageLineView(getMax: getMax, average: weekAverage)
                .opacity(actualDays <= 1 ? 0 : 1)

        }
    }

    func getWeekday(day: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("EEE")

        return dateFormatter.string(from: day)
    }

    init(week: Date, date: Binding<Date?>?, mode: Binding<Bool>, snapshot: BucketSnapshot) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode

        let loaded = snapshot

        daysOfWeek = loaded.dates
        dayDictionary = loaded.totals
        self.max = loaded.maximum
        weekTotal = loaded.amount
        weekAverage = loaded.average
        actualDays = loaded.nonzeroCount
    }
}

struct MonthGraphView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @EnvironmentObject var dataController: DataController
    @AnalyticsInput private var environment
    @Environment(\.ledgerMetadata) private var metadata


    @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var firstDayOfMonth: Int = 1

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    @State var categoryFilterMode = false
    @State var categoryFilter: Category?

    @State private var selectedDay: CalendarPeriodSelection?
    var selectedDate: Date? {
        get { selectedDay?.start(period: .day, now: environment.now, calendar: environment.calendar) }
        nonmutating set { selectedDay = newValue.map { CalendarPeriodSelection(start: $0, calendar: environment.calendar) } }
    }

    var startOfCurrentMonth: Date {
        CalendarPeriodSelection().start(period: .month, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth)
    }

    // start of month of the earliest transaction
    var startOfLastMonth: Date {
        calculateStartOfMonthPeriod(earliestDate: metadata?.earliestDate ?? environment.now, startOfMonthDay: environment.firstDayOfMonth, calendar: environment.calendar)
    }

    var swipeStrings: (backward: String, forward: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMyy")

        let startOfLastMonth = LedgerCalendar.monthStart(in: showingMonth, day: environment.firstDayOfMonth, offset: -1, calendar: environment.calendar) ?? showingMonth
        let startOfNextMonth = LedgerCalendar.monthStart(in: showingMonth, day: environment.firstDayOfMonth, offset: 1, calendar: environment.calendar) ?? showingMonth

        return (dateFormatter.string(from: startOfLastMonth), dateFormatter.string(from: startOfNextMonth))
    }

    @State private var offset: CGFloat = 0
    @State private var changeDate: Bool = false
    @GestureState var isDragging = false
    var changeTime: Bool {
        if offset < -(UIScreen.main.bounds.width * 0.25) && showingMonth != startOfCurrentMonth {
            return true
        } else if offset > (UIScreen.main.bounds.width * 0.25) && showingMonth != startOfLastMonth {
            return true
        } else {
            return false
        }
//
//        return abs(offset) > UIScreen.main.bounds.width * 0.3
    }

    @State private var periodSelection = CalendarPeriodSelection()
    var showingMonth: Date {
        get { periodSelection.start(period: .month, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth) }
        nonmutating set { periodSelection.select(newValue, period: .month, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth) }
    }


    @State var chosenCategoryName = ""
    @State var chosenCategoryAmount = 0.0

    @AppStorage("insightsViewIncomeFiltering", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var income: Bool = true
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var incomeTracking: Bool = true

//    @Environment(\.dynamicTypeMultiplier) var multiplier

    @State var incomeFiltering: Bool = true

    var body: some View {
        let request = InsightsRequest(start: showingMonth, type: 2, environment: environment)
        AnalyticsReadView(key: request, load: dataController.analyticsInsightsSnapshot) { snapshot in
            if snapshot.current.spent.isFinite && snapshot.current.income.isFinite {
                graphContent(snapshot)
            } else { Text("Amount unavailable").padding() }
        }
    }

    @ViewBuilder private func graphContent(_ snapshot: InsightsSnapshot) -> some View {
        let selectedCategory = (income ? snapshot.income : snapshot.expenses).categories.first { $0.id == categoryFilter?.objectID.uriRepresentation() }
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                ZStack {
                    SingleGraphView(showingDate: showingMonth, date: Binding(get: { selectedDate }, set: { selectedDate = $0 }), mode: Binding(get: { categoryFilterMode && selectedCategory != nil }, set: { categoryFilterMode = $0 }), categoryName: selectedCategory?.category.name ?? "", categoryAmount: selectedCategory?.amount ?? 0, currencySymbol: currencySymbol, showCents: showCents, snapshot: snapshot, income: $income, incomeFiltering: $incomeFiltering, type: 2)
                        .drawingGroup()
                        .offset(x: offset)

                    if !changeDate {
                        HStack {
                            if showingMonth != startOfLastMonth {
                                SwipeArrowView(left: true, swipeString: swipeStrings.backward.uppercased(), changeTime: changeTime)
                                .offset(x: -100)
                                .offset(x: min(100, offset))
                            } else {
                                SwipeEndView(left: true)
                                .offset(x: -120)
                                .offset(x: min(120, offset))
                            }

                            Spacer()
                        }

                        HStack {
                            Spacer()

                            if showingMonth != startOfCurrentMonth {
                                SwipeArrowView(left: false, swipeString: swipeStrings.forward.uppercased(), changeTime: changeTime)
                                .offset(x: 100)
                                .offset(x: max(-100, offset))
                            } else {
                                SwipeEndView(left: false)
                                .offset(x: 120)
                                .offset(x: max(-120, offset))
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 30)
                .simultaneousGesture(
                    DragGesture()
                        .updating($isDragging, body: { _, state, _ in
                            state = true
                        })
                        .onChanged { value in
                            withAnimation {
                                if value.translation.width < 0, showingMonth != startOfCurrentMonth {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width < 0, showingMonth == startOfCurrentMonth {
                                    offset = value.translation.width * 0.5
                                } else if value.translation.width > 0, showingMonth != startOfLastMonth {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width > 0, showingMonth == startOfLastMonth {
                                    offset = value.translation.width * 0.5
                                }
                            }
                        }.onEnded { _ in
                            if changeTime {
                                if offset < 0, showingMonth != startOfCurrentMonth {
                                    changeDate = true

                                    offset = UIScreen.main.bounds.width

                                    showingMonth = LedgerCalendar.monthStart(in: showingMonth, day: environment.firstDayOfMonth, offset: 1, calendar: environment.calendar) ?? showingMonth

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                } else if offset > 0, showingMonth != startOfLastMonth {
                                    changeDate = true

                                    offset = -UIScreen.main.bounds.width

                                    showingMonth = LedgerCalendar.monthStart(in: showingMonth, day: environment.firstDayOfMonth, offset: -1, calendar: environment.calendar) ?? showingMonth

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                }

                                withAnimation(.easeInOut(duration: 0.3)) {
                                    offset = 0
                                }

                                changeDate = false
                            }
                        }
                )
                .onChange(of: changeTime) { _ in
                    if changeTime {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onChange(of: isDragging) { _ in
                    if !isDragging && !changeDate {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                        }
                    }
                }
                .animation(.easeInOut, value: changeTime)
                .onChange(of: showingMonth) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: income) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: incomeFiltering) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .padding(.bottom, incomeFiltering ? 5 : 20)
                
                Group {
                    if !incomeFiltering {
                        FilteredInsightsView(startDate: showingMonth, type: 2)
                            .padding(.bottom, 70)
                            .padding(.horizontal, 20)
                    } else {
                        if selectedDate == nil {
                            HorizontalPieChartView(date: showingMonth, categoryFilter: $categoryFilter, categoryFilterMode: $categoryFilterMode, selectedDate: Binding(get: { selectedDate }, set: { selectedDate = $0 }), chosenAmount: $chosenCategoryAmount, chosenName: $chosenCategoryName, type: .month, income: income, snapshot: income ? snapshot.income : snapshot.expenses)
                                .padding(.horizontal, 30)
                                .padding(.bottom, 70)

                            if categoryFilterMode {
                                FilteredCategoryInsightsView(category: categoryFilter, date: showingMonth, type: .month)
                                    .padding(.bottom, 70)
                                    .padding(.horizontal, 20)
                            }
                        } else {
                            FilteredDateInsightsView(date: selectedDate ?? environment.now, income: income)
                                .padding(.bottom, 70)
                                .padding(.horizontal, 20)
                        }
                    }
                }

//                Group {
//                    if !incomeFiltering {
//                        FilteredInsightsView(startDate: showingMonth, type: 2)
//                            .padding(.bottom, 70)
//                    } else {
//                        if selectedDate != nil {
//                            FilteredDateInsightsView(date: selectedDate ?? environment.now, income: income)
//                                .padding(.bottom, 70)
//
//                        } else if categoryFilterMode {
//                            FilteredCategoryInsightsView(category: categoryFilter, date: showingMonth, type: .month)
//                                .padding(.bottom, 70)
//                        } else {
//                            FilteredInsightsView(startDate: showingMonth, income: income, type: 2)
//                                .padding(.bottom, 70)
//                        }
//                    }
//                }
//                .padding(.horizontal, 20)
//                .onTapGesture {
//                    selectedDate = nil
//                    categoryFilterMode = false
//                }
            }
        }
    }
}

struct SingleMonthBarGraphView: View {
    @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var firstDayOfMonth: Int = 1

    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool

    var daysOfMonth = [Date]()

    var dayDictionary = [Date: Double]()

    var max: Double = 0
    var monthTotal: Double = 0
    var monthAverage: Double = 0
    var actualDays: Int = 0

    var getMax: Double {
        return NumericSafety.graphMaximum(max)
    }

    let numberArray = [1, 8, 15, 22, 29]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 3) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(alignment: .top, spacing: 2) {
                    ForEach(daysOfMonth, id: \.self) { day in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.SecondaryBackground)
                                .frame(height: barHeight)
                                .zIndex(0)

                            AnimatedBarGraph(index: daysOfMonth.firstIndex(of: day) ?? 0)
                                .frame(height: getBarHeight(point: dayDictionary[day] ?? 0, maxi: getMax))
                                .opacity(selectedDate == nil ? 1 : (selectedDate == day ? 1 : 0.4))
                                .zIndex(0)
                                .overlay(alignment: .bottom) {
                                    if numberArray.contains(((daysOfMonth.firstIndex(of: day) ?? -1) + 1)) && firstDayOfMonth == 1 {
                                        Text("\((daysOfMonth.firstIndex(of: day) ?? -1) + 1)")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.SubtitleText)
                                            .frame(width: 20, alignment: .center)
                                            .offset(y: 20)
                                    }
                                }
                        }
                        .padding(.bottom, firstDayOfMonth == 1 ? 22 : 0)
                        .opacity(day > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(day > Date.now))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == day {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = day
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

            }
            .frame(maxWidth: .infinity)

            //                .frame(maxHeight: .infinity)

            // average line

            AverageLineView(getMax: getMax, average: monthAverage)
                .opacity(actualDays <= 1 ? 0 : 1)

        }
    }

    init(month: Date, date: Binding<Date?>?, mode: Binding<Bool>, snapshot: BucketSnapshot) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode

        let loaded = snapshot

        daysOfMonth = loaded.dates
        dayDictionary = loaded.totals
        self.max = loaded.maximum
        monthTotal = loaded.amount
        monthAverage = loaded.average
        actualDays = loaded.nonzeroCount
    }
}

struct YearGraphView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @EnvironmentObject var dataController: DataController
    @AnalyticsInput private var environment
    @Environment(\.ledgerMetadata) private var metadata


    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    @State var categoryFilterMode = false
    @State var categoryFilter: Category?

    @State private var selectedDay: CalendarPeriodSelection?
    var selectedDate: Date? {
        get { selectedDay?.start(period: .day, now: environment.now, calendar: environment.calendar) }
        nonmutating set { selectedDay = newValue.map { CalendarPeriodSelection(start: $0, calendar: environment.calendar) } }
    }

    var startOfCurrentYear: Date {
        CalendarPeriodSelection().start(period: .year, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth)
    }

    var startOfLastYear: Date {
        CalendarPeriodSelection(start: metadata?.earliestDate ?? environment.now, calendar: environment.calendar).start(period: .year, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth)
    }

    var swipeStrings: (backward: String, forward: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("yyyy")

        let calendar = environment.calendar

        let startOfLastYear = calendar.date(byAdding: .year, value: -1, to: showingYear) ?? environment.now
        let startOfNextYear = calendar.date(byAdding: .year, value: 1, to: showingYear) ?? environment.now

        return (dateFormatter.string(from: startOfLastYear), dateFormatter.string(from: startOfNextYear))
    }

    @State private var offset: CGFloat = 0
    @State private var changeDate: Bool = false
    @GestureState var isDragging = false
    var changeTime: Bool {
        if offset < -(UIScreen.main.bounds.width * 0.25) && showingYear != startOfCurrentYear {
            return true
        } else if offset > (UIScreen.main.bounds.width * 0.25) && showingYear != startOfLastYear {
            return true
        } else {
            return false
        }
//
//        return abs(offset) > UIScreen.main.bounds.width * 0.3
    }

    @State private var periodSelection = CalendarPeriodSelection()
    var showingYear: Date {
        get { periodSelection.start(period: .year, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth) }
        nonmutating set { periodSelection.select(newValue, period: .year, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday, firstDayOfMonth: environment.firstDayOfMonth) }
    }


    @State var chosenCategoryName = ""
    @State var chosenCategoryAmount = 0.0

    @AppStorage("insightsViewIncomeFiltering", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var income: Bool = true
    @AppStorage("incomeTracking", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var incomeTracking: Bool = true
//
//    @Environment(\.dynamicTypeMultiplier) var multiplier

    @State var incomeFiltering: Bool = true

    var body: some View {
        let request = InsightsRequest(start: showingYear, type: 3, environment: environment)
        AnalyticsReadView(key: request, load: dataController.analyticsInsightsSnapshot) { snapshot in
            if snapshot.current.spent.isFinite && snapshot.current.income.isFinite {
                graphContent(snapshot)
            } else { Text("Amount unavailable").padding() }
        }
    }

    @ViewBuilder private func graphContent(_ snapshot: InsightsSnapshot) -> some View {
        let selectedCategory = (income ? snapshot.income : snapshot.expenses).categories.first { $0.id == categoryFilter?.objectID.uriRepresentation() }
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                ZStack {
                    SingleGraphView(showingDate: showingYear, date: Binding(get: { selectedDate }, set: { selectedDate = $0 }), mode: Binding(get: { categoryFilterMode && selectedCategory != nil }, set: { categoryFilterMode = $0 }), categoryName: selectedCategory?.category.name ?? "", categoryAmount: selectedCategory?.amount ?? 0, currencySymbol: currencySymbol, showCents: showCents, snapshot: snapshot, income: $income, incomeFiltering: $incomeFiltering, type: 3)
                        .drawingGroup()
                        .offset(x: offset)

                    if !changeDate {
                        HStack {
                            if showingYear != startOfLastYear {
                                SwipeArrowView(left: true, swipeString: swipeStrings.backward.uppercased(), changeTime: changeTime)
                                .offset(x: -100)
                                .offset(x: min(100, offset))
                            } else {
                                SwipeEndView(left: true)
                                .offset(x: -120)
                                .offset(x: min(120, offset))
                            }

                            Spacer()
                        }

                        HStack {
                            Spacer()

                            if showingYear != startOfCurrentYear {
                                SwipeArrowView(left: false, swipeString: swipeStrings.forward.uppercased(), changeTime: changeTime)
                                .offset(x: 100)
                                .offset(x: max(-100, offset))
                            } else {
                                SwipeEndView(left: false)
                                .offset(x: 120)
                                .offset(x: max(-120, offset))
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 30)
                .simultaneousGesture(
                    DragGesture()
                        .updating($isDragging, body: { _, state, _ in
                            state = true
                        })
                        .onChanged { value in
                            withAnimation {
                                if value.translation.width < 0, showingYear != startOfCurrentYear {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width < 0, showingYear == startOfCurrentYear {
                                    offset = value.translation.width * 0.5
                                } else if value.translation.width > 0, showingYear != startOfLastYear {
                                    offset = value.translation.width * 0.9
                                } else if value.translation.width > 0, showingYear == startOfLastYear {
                                    offset = value.translation.width * 0.5
                                }
                            }
                        }.onEnded { _ in
                            if changeTime {
                                if offset < 0, showingYear != startOfCurrentYear {
                                    changeDate = true

                                    offset = UIScreen.main.bounds.width

                                    showingYear = environment.calendar.date(byAdding: .year, value: 1, to: showingYear) ?? environment.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                } else if offset > 0, showingYear != startOfLastYear {
                                    changeDate = true

                                    offset = -UIScreen.main.bounds.width

                                    showingYear = environment.calendar.date(byAdding: .year, value: -1, to: showingYear) ?? environment.now

                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        offset = 0
                                    }
                                }

                                withAnimation(.easeInOut(duration: 0.3)) {
                                    offset = 0
                                }

                                changeDate = false
                            }
                        }
                )
                .onChange(of: changeTime) { _ in
                    if changeTime {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onChange(of: isDragging) { _ in
                    if !isDragging && !changeDate {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                        }
                    }
                }
                .animation(.easeInOut, value: changeTime)
                .onChange(of: showingYear) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: income) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .onChange(of: incomeFiltering) { _ in
                    selectedDate = nil
                    categoryFilterMode = false
                }
                .padding(.bottom, incomeFiltering ? 5 : 20)

                Group {
                    if !incomeFiltering {
                        FilteredInsightsView(startDate: showingYear, type: 3)
                            .padding(.bottom, 70)
                            .padding(.horizontal, 20)
                    } else {
                        if selectedDate == nil {
                            HorizontalPieChartView(date: showingYear, categoryFilter: $categoryFilter, categoryFilterMode: $categoryFilterMode, selectedDate: Binding(get: { selectedDate }, set: { selectedDate = $0 }), chosenAmount: $chosenCategoryAmount, chosenName: $chosenCategoryName, type: .year, income: income, snapshot: income ? snapshot.income : snapshot.expenses)
                                .padding(.horizontal, 30)
                                .padding(.bottom, 70)

                            if categoryFilterMode {
                                FilteredCategoryInsightsView(category: categoryFilter, date: showingYear, type: .year)
                                    .padding(.bottom, 70)
                                    .padding(.horizontal, 20)
                            }
                        } else {
                            FilteredDateInsightsView(date: selectedDate ?? environment.now, income: income, chartType: 3)
                                .padding(.bottom, 70)
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
    }
}

struct SingleYearBarGraphView: View {
    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool

    var monthsOfYear = [Date]()

    var monthDictionary = [Date: Double]()

    var max: Double = 0

    var getMax: Double {
        return NumericSafety.graphMaximum(max)
    }

    var yearTotal: Double = 0
    var yearAverage: Double = 0
    var actualMonths: Int = 0
    var pastYearTotal: Double = 0

    let numberArray = [1, 4, 7, 10]
    let monthNames: [Int: String] = [1: "Jan", 4: "Apr", 7: "Jul", 10: "Oct"]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 3) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(alignment: .top, spacing: 4) {
                    ForEach(monthsOfYear, id: \.self) { month in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.SecondaryBackground)
                                .frame(height: barHeight)
                                .zIndex(0)

                            AnimatedBarGraph(index: monthsOfYear.firstIndex(of: month) ?? 0)
                                .frame(height: getBarHeight(point: monthDictionary[month] ?? 0, maxi: getMax))
                                .opacity(selectedDate == nil ? 1 : (selectedDate == month ? 1 : 0.4))
                                .zIndex(0)
                                .overlay(alignment: .bottom) {
                                    if numberArray.contains(((monthsOfYear.firstIndex(of: month) ?? 0) + 1)) {
                                        Text(LocalizedStringKey(monthNames[((monthsOfYear.firstIndex(of: month) ?? 0) + 1)] ?? ""))
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.SubtitleText)
                                            .frame(width: 30)
                                            .offset(y: 20)
                                    }
                                }
                        }
                        .padding(.bottom, 22)
                        .opacity(month > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(month > Date.now))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == month {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = month
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

            }
            .frame(maxWidth: .infinity)

            // average line

            AverageLineView(getMax: getMax, average: yearAverage)
                .opacity(actualMonths <= 1 ? 0 : 1)

        }
    }

    func getMonth(month: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("M")

        return dateFormatter.string(from: month)
    }

    init(year: Date, date: Binding<Date?>?, mode: Binding<Bool>, snapshot: BucketSnapshot) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode

        let loaded = snapshot

        monthsOfYear = loaded.dates
        monthDictionary = loaded.totals
        self.max = loaded.maximum
        yearTotal = loaded.amount
        yearAverage = loaded.average
        actualMonths = loaded.nonzeroCount
    }
}

func getMaxText(maxi: Double) -> String {
    guard maxi.isFinite else { return "—" }
    return maxi.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
}

struct ChartTimePickerView: View {
    @Namespace var animation
    @State var timeframe = ChartTimeFrame.week
    @Binding var showMenu: Bool

    @AppStorage("colourScheme", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var colourScheme: Int = 0

    @AppStorage("chartTimeFrame", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var chartType = 1

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ChartTimeFrame.allCases, id: \.self) { time in
                HStack {
                    Text(LocalizedStringKey(time.rawValue))
                    Spacer()

                    if time == timeframe {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .padding(5)
                .background {
                    if time == timeframe {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(darkMode ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground"))
                            .matchedGeometryEffect(id: "TAB", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if timeframe == time {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            timeframe = time
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showMenu = false
                        }
                    }
                }
            }
        }
        .foregroundColor(darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground"))
        .padding(4)
        .frame(width: 120)
        .background(RoundedRectangle(cornerRadius: 9).fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground")).shadow(color: darkMode ? Color.clear : Color.gray.opacity(0.25), radius: 6))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(darkMode ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
        .onChange(of: timeframe) { _ in
            if timeframe == .week {
                chartType = 1
            } else if timeframe == .month {
                chartType = 2
            } else if timeframe == .year {
                chartType = 3
            }
        }
        .onAppear {
            if chartType == 1 {
                timeframe = ChartTimeFrame.week
            } else if chartType == 2 {
                timeframe = ChartTimeFrame.month
            } else if chartType == 3 {
                timeframe = ChartTimeFrame.year
            }
        }
    }
}

struct AnimatedBarGraph: View {
    var index: Int

    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true
    @State var showBar: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.DarkBackground)
                .frame(height: showBar ? nil : 0, alignment: .bottom)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if !animated {
                    showBar = true
                } else {
                    withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8).delay(Double(index) * 0.1)) {
                        showBar = true
                    }
                }
            }
        }
    }
}

struct AnimatedHorizontalBarGraph: View {
    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true
    var category: PowerCategory
    var index: Int

    @State var showBar: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(category.category.income ? Color(hex: Color.colorArray[index]) : Color(hex: category.category.wrappedColour))
                .frame(width: showBar ? nil : 0, alignment: .leading)

            Spacer(minLength: 0)
        }
//        .onAppear {
//            DispatchQueue.main.asyncAfter(deadline: .now()) {
//                if !animated {
//                    showBar = true
//                } else {
//                    withAnimation(.easeInOut(duration: 0.7).delay(Double(index) * 0.5)) {
//                        showBar = true
//                    }
//                }
//            }
//        }
    }
}

struct InsightsDollarView: View {
    let amount: Double
    var currencySymbol: String
    var showCents: Bool
    var net: Bool?

    var symbol: String {
        if let netPositive = net {
            if netPositive {
                return "+\(currencySymbol)"
            } else {
                return "-\(currencySymbol)"
            }
        } else {
            return currencySymbol
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1.3) {
            Group {
                Text(symbol)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText) +

                Text(amount.isFinite ? String(format: showCents && amount < 100 ? "%.2f" : "%.0f", amount) : String(localized: "Amount unavailable"))
                    .font(.system(.title, design: .rounded).weight(.medium))
                    .foregroundColor(Color.PrimaryText)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    init(amount: Double, currencySymbol: String, showCents: Bool, net: Bool? = nil) {
        self.amount = amount
        self.currencySymbol = currencySymbol
        self.showCents = showCents
        self.net = net
    }
}

func getAverageText(average: Double) -> String {
    guard average.isFinite else { return "—" }
    return average.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
}

let barHeight = 150.0

func getOffset(maxi: Double, average: Double) -> Double {
    if maxi == 0 {
        return 0
    } else {
        let shiftedAmount = NumericSafety.clamped(NumericSafety.safeRatio(average, maxi), to: 0...1) * (barHeight)
        let height = (barHeight) - (shiftedAmount)
        return height - 10
    }
}

func getBarHeight(point: CGFloat, maxi: Double) -> CGFloat {
    if maxi == 0 {
        return 0
    } else {
        let height = NumericSafety.clamped(NumericSafety.safeRatio(Double(point), maxi), to: 0...1) * barHeight
        return height
    }
}

struct SwipeArrowView: View {
    let left: Bool
    let swipeString: String
    let changeTime: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: left ? "arrow.backward.circle.fill" : "arrow.forward.circle.fill")
                .font(.system(.body, design: .rounded).weight(.medium))
//                                        .font(.system(size: 18, weight: .medium))
                //                                .scaleEffect(changeTime ? 1.3 : 1)
                .foregroundColor(changeTime ? Color.PrimaryText : Color.SecondaryBackground)

            Text(swipeString)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(changeTime ? Color.PrimaryText : Color.SecondaryBackground)
        }
        .drawingGroup()
    }
}

struct SwipeEndView: View {
    let left: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: left ? "eyeglasses" : "sun.haze.fill")
                .font(.system(.title2, design: .rounded).weight(.medium))
//                                        .font(.system(size: 22, weight: .medium))
                .foregroundColor(Color.SubtitleText)

            Text(LocalizedStringKey(left ? "That's all, buddy." : "Into the unknown."))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 90)
                .multilineTextAlignment(.center)
                .foregroundColor(Color.SubtitleText)
        }
        .opacity(0.8)
        .drawingGroup()
    }
}
