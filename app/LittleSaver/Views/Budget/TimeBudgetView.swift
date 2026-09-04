//
//  TimeBudgetView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

struct TimeBudgetView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    @StateObject private var reads = SnapshotModel<LedgerListRequest, LedgerListSnapshot>()
    let budget: Budget

    var budgetAmount: Double {
        return budget.amount
    }

    var budgetType: Int {
        return Int(budget.type)
    }

    @State private var selectedPeriodIndex: Int?

    var selectedWindow: BudgetWindow? {
        guard let current = budget.currentWindow(now: environment.now, calendar: environment.calendar), let anchor = budget.startDate else { return nil }
        guard let selectedPeriodIndex else { return current }
        return BudgetPeriod(rawValue: budget.type)?.window(anchor: anchor, index: min(selectedPeriodIndex, current.index), calendar: environment.calendar)
    }

    private var startDate: Date {
        get { selectedWindow?.start ?? .distantPast }
        nonmutating set {
            guard let anchor = budget.startDate,
                  let selected = BudgetPeriod(rawValue: budget.type)?.window(anchor: anchor, containing: newValue, calendar: environment.calendar),
                  let current = budget.currentWindow(now: environment.now, calendar: environment.calendar) else { return }
            selectedPeriodIndex = selected.index >= current.index ? nil : selected.index
        }
    }

    var dateString: String {
        guard let window = selectedWindow else { return String(localized: "Date unavailable") }
        return localizedDateInterval(from: window.start, to: window.end.addingTimeInterval(-1))
    }

    private var request: LedgerListRequest {
        LedgerListRequest(query: .interval(start: startDate, end: selectedWindow?.end ?? startDate, income: false, category: budget.category?.objectID.uriRepresentation()), environment: environment)
    }
    private var totalSpent: Double { reads.value(for: request)?.spent ?? .nan }

    var timeLeft: String {
        if budgetType == 1 {
            let hours = NumericSafety.roundedInt(ceil(max(0, (selectedWindow?.end.timeIntervalSince(environment.now) ?? 0)) / 3600))
            return String(localized: "\(hours) hours left")
        }
        return String(localized: "\(daysLeftNumber) days left")
    }

    var subtitleText: String {
        if (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) == startDate {
            return timeLeft
        } else {
            return dateString
        }
    }

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var difference: Double {
        abs(NumericSafety.difference(budgetAmount, totalSpent))
    }

    var differenceSubtitle: String {
        if budgetAmount >= totalSpent {
            if startDate == (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) {
                if budgetType == 1 {
                    return String(localized: "left today")
                } else if budgetType == 2 {
                    return String(localized: "left this week")
                } else if budgetType == 3 {
                    return String(localized: "left this month")
                } else if budgetType == 4 {
                    return String(localized: "left this year")
                } else {
                    return ""
                }
            } else {
                if budgetType == 1 {
                    let dateFormatter = DateFormatter()
                    dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                    return String(localized: "left on \(dateFormatter.string(from: startDate))")
                } else if budgetType == 2 {
                    let components = Calendar.current.dateComponents([.day], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let weekString = String(localized: "\((components.day ?? 0) / 7) weeks ago")
                    return String(localized: "left \(weekString)")
                } else if budgetType == 3 {
                    let components = Calendar.current.dateComponents([.month], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let monthString = String(localized: "\((components.month ?? 0)) months ago")
                    return String(localized: "left \(monthString)")
                } else if budgetType == 4 {
                    let components = Calendar.current.dateComponents([.year], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let yearString = String(localized: "\((components.year ?? 0)) years ago")
                    return String(localized: "left \(yearString)")
                } else {
                    return ""
                }
            }
        } else {
            if startDate == (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) {
                if budgetType == 1 {
                    return String(localized: "over today")
                } else if budgetType == 2 {
                    return String(localized: "over this week")
                } else if budgetType == 3 {
                    return String(localized: "over this month")
                } else if budgetType == 4 {
                    return String(localized: "over this year")
                } else {
                    return ""
                }
            } else {
                if budgetType == 1 {
                    let dateFormatter = DateFormatter()
                    dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                    return String(localized: "over on \(dateFormatter.string(from: startDate))")
                } else if budgetType == 2 {
                    let components = Calendar.current.dateComponents([.day], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let weekString = String(localized: "\((components.day ?? 0) / 7) weeks ago")
                    return String(localized: "over \(weekString)")
                } else if budgetType == 3 {
                    let components = Calendar.current.dateComponents([.month], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let monthString = String(localized: "\((components.month ?? 0)) months ago")
                    return String(localized: "over \(monthString)")
                } else if budgetType == 4 {
                    let components = Calendar.current.dateComponents([.year], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let yearString = String(localized: "\((components.year ?? 0)) years ago")
                    return String(localized: "over \(yearString)")
                } else {
                    return ""
                }
            }
        }
    }

    // for week, month, year only

    var daysLeftNumber: Int { budget.currentWindow(now: environment.now, calendar: environment.calendar)?.daysRemaining(at: environment.now, calendar: environment.calendar) ?? 0 }

    var leftPerDay: Double {
        if budgetType >= 2 {
            return NumericSafety.safeRatio(NumericSafety.difference(budgetAmount, totalSpent), Double(daysLeftNumber))
        } else {
            return 0
        }
    }

    var showExtraDetails: Bool {
        if budgetType >= 2 {
            return (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) == startDate && totalSpent < budgetAmount && daysLeftNumber != 1
        } else {
            return false
        }
    }

    var body: some View {
        AnalyticsResultView(model: reads, key: request, load: controller.ledgerListSnapshot) { snapshot in
            if snapshot.spent.isFinite { content(snapshot) }
            else { Text("Amount unavailable") }
        }
    }

    private func content(_ snapshot: LedgerListSnapshot) -> some View {
        VStack(spacing: 20) {
            // budget name and emoji and time left
            VStack(spacing: 10) {
                HStack(spacing: 7.5) {
                    Text(budget.wrappedEmoji)
                        .font(.system(.subheadline, design: .rounded))
                    Text(budget.wrappedName)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .lineLimit(1)
                }
                .foregroundColor(Color.PrimaryText)

                Text(subtitleText)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.SubtitleText)
                    .padding(4)
                    .padding(.horizontal, 7)
                    .background(Color.SecondaryBackground, in: Capsule())
            }
            .padding(.bottom, 15)

            // amount left and averages

            if budgetType >= 2 {
                HStack(alignment: .top, spacing: 15) {
                    VStack(alignment: showExtraDetails ? .leading : .center, spacing: -4) {
                        DetailedBudgetDifferenceDollarView(amount: difference, red: totalSpent >= budgetAmount)

                        Text(differenceSubtitle)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .frame(maxWidth: .infinity, alignment: showExtraDetails ? .leading : .center)

                    if showExtraDetails {
                        VStack(alignment: .trailing, spacing: -4) {
                            DetailedBudgetDollarView(amount: leftPerDay)

                            Text("left each day")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
//                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 25)
            } else {
                VStack(spacing: -4) {
                    DetailedBudgetDifferenceDollarView(amount: difference, red: totalSpent >= budgetAmount)

                    Text(differenceSubtitle)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
//                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                }
                .padding(.horizontal, 25)
            }

            // bar graph

            VStack(spacing: 5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                            .fill(Color.SecondaryBackground)
                            .frame(width: proxy.size.width)

                        if BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount) < 0.98 {
                            if let category = budget.category {
                                AnimatedHorizontalBarGraphBudget(category: category)
                                    .frame(width: proxy.size.width * (1 - BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 28)

                HStack {
                    Text("\(currencySymbol)\(totalSpent, specifier: "%.2f")")
                    Spacer()
                    Text("\(currencySymbol)\(budgetAmount, specifier: "%.2f")")
                }
                .frame(maxWidth: .infinity)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Color.SubtitleText)
            }
            .padding(.bottom, budgetType >= 2 ? 20 : 0)
            .padding(.horizontal, 25)

            if budgetType == 1 {
                Divider()
                    .overlay(Color.Outline)
                    .padding(.horizontal, 25)
            }

            if let category = budget.category {
                ScrollView(showsIndicators: false) {
                    ListView(snapshot: snapshot, dayHeaders: budgetType != 1)
                        .padding(.horizontal, 15)
                }
                .frame(maxHeight: .infinity)

                BudgetStepperView(category: category, date: Binding(get: { startDate }, set: { startDate = $0 }), startDate: budget.startDate, budgetType: budgetType)
                    .padding(.horizontal, 25)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct TimeMainBudgetView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    @StateObject private var reads = SnapshotModel<LedgerListRequest, LedgerListSnapshot>()
    let budget: MainBudget

    var budgetAmount: Double {
        return budget.amount
    }

    var budgetType: Int {
        return Int(budget.type)
    }

    @State private var selectedPeriodIndex: Int?

    var selectedWindow: BudgetWindow? {
        guard let current = budget.currentWindow(now: environment.now, calendar: environment.calendar), let anchor = budget.startDate else { return nil }
        guard let selectedPeriodIndex else { return current }
        return BudgetPeriod(rawValue: budget.type)?.window(anchor: anchor, index: min(selectedPeriodIndex, current.index), calendar: environment.calendar)
    }

    private var startDate: Date {
        get { selectedWindow?.start ?? .distantPast }
        nonmutating set {
            guard let anchor = budget.startDate,
                  let selected = BudgetPeriod(rawValue: budget.type)?.window(anchor: anchor, containing: newValue, calendar: environment.calendar),
                  let current = budget.currentWindow(now: environment.now, calendar: environment.calendar) else { return }
            selectedPeriodIndex = selected.index >= current.index ? nil : selected.index
        }
    }

    var dateString: String {
        guard let window = selectedWindow else { return String(localized: "Date unavailable") }
        return localizedDateInterval(from: window.start, to: window.end.addingTimeInterval(-1))
    }

    private var request: LedgerListRequest {
        LedgerListRequest(query: .interval(start: startDate, end: selectedWindow?.end ?? startDate, income: false, category: nil), environment: environment)
    }
    private var totalSpent: Double { reads.value(for: request)?.spent ?? .nan }

    var timeLeft: String {
        if budgetType == 1 {
            let hours = NumericSafety.roundedInt(ceil(max(0, (selectedWindow?.end.timeIntervalSince(environment.now) ?? 0)) / 3600))
            return String(localized: "\(hours) hours left")
        }
        return String(localized: "\(daysLeftNumber) days left")
    }

    var subtitleText: String {
        if (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) == startDate {
            return timeLeft
        } else {
            return dateString
        }
    }

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var difference: Double {
        abs(NumericSafety.difference(budgetAmount, totalSpent))
    }

    var differenceSubtitle: String {
        if budgetAmount >= totalSpent {
            if startDate == (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) {
                if budgetType == 1 {
                    return String(localized: "left today")
                } else if budgetType == 2 {
                    return String(localized: "left this week")
                } else if budgetType == 3 {
                    return String(localized: "left this month")
                } else if budgetType == 4 {
                    return String(localized: "left this year")
                } else {
                    return ""
                }
            } else {
                if budgetType == 1 {
                    let dateFormatter = DateFormatter()
                    dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                    return String(localized: "left on \(dateFormatter.string(from: startDate))")
                } else if budgetType == 2 {
                    let components = Calendar.current.dateComponents([.day], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let weekString = String(localized: "\((components.day ?? 0) / 7) weeks ago")
                    return String(localized: "left \(weekString)")
                } else if budgetType == 3 {
                    let components = Calendar.current.dateComponents([.month], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let monthString = String(localized: "\((components.month ?? 0)) months ago")
                    return String(localized: "left \(monthString)")
                } else if budgetType == 4 {
                    let components = Calendar.current.dateComponents([.year], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let yearString = String(localized: "\((components.year ?? 0)) years ago")
                    return String(localized: "left \(yearString)")
                } else {
                    return ""
                }
            }
        } else {
            if startDate == (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) {
                if budgetType == 1 {
                    return String(localized: "over today")
                } else if budgetType == 2 {
                    return String(localized: "over this week")
                } else if budgetType == 3 {
                    return String(localized: "over this month")
                } else if budgetType == 4 {
                    return String(localized: "over this year")
                } else {
                    return ""
                }
            } else {
                if budgetType == 1 {
                    let dateFormatter = DateFormatter()
                    dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                    return String(localized: "over on \(dateFormatter.string(from: startDate))")
                } else if budgetType == 2 {
                    let components = Calendar.current.dateComponents([.day], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let weekString = String(localized: "\((components.day ?? 0) / 7) weeks ago")
                    return String(localized: "over \(weekString)")
                } else if budgetType == 3 {
                    let components = Calendar.current.dateComponents([.month], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let monthString = String(localized: "\((components.month ?? 0)) months ago")
                    return String(localized: "over \(monthString)")
                } else if budgetType == 4 {
                    let components = Calendar.current.dateComponents([.year], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let yearString = String(localized: "\((components.year ?? 0)) years ago")
                    return String(localized: "over \(yearString)")
                } else {
                    return ""
                }
            }
        }
    }

    // for week, month, year only

    var daysLeftNumber: Int { budget.currentWindow(now: environment.now, calendar: environment.calendar)?.daysRemaining(at: environment.now, calendar: environment.calendar) ?? 0 }

    var leftPerDay: Double {
        if budgetType >= 2 {
            return NumericSafety.safeRatio(NumericSafety.difference(budgetAmount, totalSpent), Double(daysLeftNumber))
        } else {
            return 0
        }
    }

    var showExtraDetails: Bool {
        if budgetType >= 2 {
            return (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) == startDate && totalSpent < budgetAmount && daysLeftNumber != 1
        } else {
            return false
        }
    }

    var body: some View {
        AnalyticsResultView(model: reads, key: request, load: controller.ledgerListSnapshot) { snapshot in
            if snapshot.spent.isFinite { content(snapshot) }
            else { Text("Amount unavailable") }
        }
    }

    private func content(_ snapshot: LedgerListSnapshot) -> some View {
        VStack(spacing: 20) {
            // budget name and emoji and time left
            VStack(spacing: 10) {
                Text("Overall Budget")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .lineLimit(1)
                    .foregroundColor(Color.PrimaryText)

                Text(subtitleText)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.SubtitleText)
                    .padding(4)
                    .padding(.horizontal, 7)
                    .background(Color.SecondaryBackground, in: Capsule())
            }
            .padding(.bottom, 15)

            // amount left and averages

            if budgetType >= 2 {
                HStack(alignment: .top, spacing: 15) {
                    VStack(alignment: showExtraDetails ? .leading : .center, spacing: -4) {
                        DetailedBudgetDifferenceDollarView(amount: difference, red: totalSpent >= budgetAmount)

                        Text(differenceSubtitle)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .frame(maxWidth: .infinity, alignment: showExtraDetails ? .leading : .center)

                    if showExtraDetails {
                        VStack(alignment: .trailing, spacing: -4) {
                            DetailedBudgetDollarView(amount: leftPerDay)

                            Text("left each day")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundColor(Color.SubtitleText)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 25)
            } else {
                VStack(spacing: -4) {
                    DetailedBudgetDifferenceDollarView(amount: difference, red: totalSpent >= budgetAmount)

                    Text(differenceSubtitle)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                }
                .padding(.horizontal, 25)
            }

            // bar graph

            VStack(spacing: 5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                            .fill(Color.SecondaryBackground)
                            .frame(width: proxy.size.width)

                        if BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount) < 0.98 {
                            AnimatedHorizontalBarGraphMainBudget()
                                .frame(width: proxy.size.width * (1 - BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 28)

                HStack {
                    Text("\(currencySymbol)\(totalSpent, specifier: "%.2f")")
                    Spacer()
                    Text("\(currencySymbol)\(budgetAmount, specifier: "%.2f")")
                }
                .frame(maxWidth: .infinity)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Color.SubtitleText)
            }
            .padding(.bottom, budgetType >= 2 ? 20 : 0)
            .padding(.horizontal, 25)

            if budgetType == 1 {
                Divider()
                    .overlay(Color.Outline)
                    .padding(.horizontal, 25)
            }

            ScrollView(showsIndicators: false) {
                ListView(snapshot: snapshot, dayHeaders: budgetType != 1)
                    .padding(.horizontal, 15)
            }
            .frame(maxHeight: .infinity)

            BudgetStepperView(category: nil, date: Binding(get: { startDate }, set: { startDate = $0 }), startDate: budget.startDate, budgetType: budgetType)
                .padding(.horizontal, 25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
