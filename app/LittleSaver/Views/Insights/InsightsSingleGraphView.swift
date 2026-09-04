//
//  InsightsSingleGraphView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

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
