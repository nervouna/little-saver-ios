//
//  TransactionsList.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import LittleSaverCore
import CoreData
import Foundation
import Popovers
import SwiftUI

struct TransactionsList: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    var filter: FilterType
    var category: Category?
    var date: Date
    var week: Date
    var month: Date
    var income: Bool

    @AppStorage("showUpcomingTransactions", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showUpcoming: Bool = true
    @AppStorage("showUpcomingTransactionsWhenUpcoming", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showSoon: Bool = false

    @EnvironmentObject var dataController: DataController

    var body: some View {
        let _ = calendarRevision
        VStack {
            if (filter == .all && showUpcoming) || filter == .upcoming {
                FutureListView(dataController: dataController, filterMode: filter == .upcoming, limitedMode: showSoon)
                    .padding(.top, 10)
            }

            switch filter {
            case .all:
                SnapshotTransactionsView(query: .all)
            case .category:
                FilteredCategoryView(category: category)
            case .day:
                FilteredDateView(date: date)
            case .week:
                FilteredInsightsView(startDate: week, type: 1)
            case .month:
                FilteredInsightsView(startDate: month, type: 2, naturalMonth: true)
            case .recurring:
                FilteredRecurringView()
            case .type:
                FilteredTypeView(income: income)
            case .upcoming:
                EmptyView()
            }
        }
    }
}

struct ListView: View {
    @Environment(\.managedObjectContext) private var context
    let snapshot: LedgerListSnapshot
    var dayHeaders = true
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents = true
    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency = Locale.current.currencyCode ?? "USD"
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showExpenseOrIncomeSign = true
    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var swapTimeLabel = false
    @EnvironmentObject var toastPresenter: OverallToastPresenter
    var currencySymbol: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(snapshot.days) { day in
                let transactions: [Transaction] = day.rows.compactMap { presentationObject($0.id, in: context) }
                let dateText = day.date.map { dateConverter(date: $0).uppercased() } ?? String(localized: "Date unavailable")
                let amountText = formattedLedgerNet(day.net, currency: currency, showCents: showCents)
                VStack(spacing: 0) {
                    if dayHeaders {
                        VStack(spacing: 4) {
                            HStack { Text(dateText); Spacer(); Text(amountText).layoutPriority(1) }
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .foregroundColor(Color.SubtitleText)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(String(localized: "\(amountText) spent \(day.date.map { dateConverterAccessibilityLabel(date: $0) } ?? String(localized: "Date unavailable"))"))
                            Line().stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                        }.padding(.horizontal, 10).padding(.top, 10)
                    }
                    ForEach(transactions, id: \.objectID) { transaction in
                        SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    if #available(iOS 16.0, *) {
                        Button {
                            guard let image = ImageRenderer(content: SingleDayPhotoView(amountText: amountText, dateText: dateText, transactions: transactions, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: false)).uiImage else { return }
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            toastPresenter.showToast.toggle()
                        } label: { Label("Save as Photo", systemImage: "square.and.arrow.up") }
                    }
                }
                .padding(.bottom, dayHeaders ? 18 : 0)
            }
        }
    }
}

struct FutureListView: View {
    @EnvironmentObject private var controller: DataController
    @Environment(\.managedObjectContext) private var context
    @AnalyticsInput private var environment
    let filterMode: Bool
    let limitedMode: Bool
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents = true
    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency = Locale.current.currencyCode ?? "USD"
    @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showExpenseOrIncomeSign = true
    @AppStorage("swapTimeLabel", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var swapTimeLabel = false
    var currencySymbol: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency }

    var body: some View {
        AnalyticsReadView(key: LedgerListRequest(query: .upcoming(limited: limitedMode), environment: environment), load: controller.ledgerListSnapshot) { snapshot in
            if !snapshot.rows.isEmpty {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        HStack { Text("UPCOMING"); Spacer(); Text(formattedLedgerNet(snapshot.net, currency: currency, showCents: showCents)) }
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.SubtitleText)
                            .accessibilityElement(children: .ignore)
                        Line().stroke(Color.Outline, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    }.padding(.horizontal, 10)
                    ForEach(snapshot.rows) { row in
                        if let transaction: Transaction = presentationObject(row.id, in: context) {
                            SingleTransactionView(transaction: transaction, showCents: showCents, currencySymbol: currencySymbol, currency: currency, swapTimeLabel: swapTimeLabel, future: true, showExpenseOrIncomeSign: showExpenseOrIncomeSign)
                        }
                    }
                }.padding(.bottom, 18)
            } else if filterMode { NoResultsView(fullscreen: true) }
        }
    }
    init(dataController _: DataController, filterMode: Bool, limitedMode: Bool) {
        self.filterMode = filterMode; self.limitedMode = limitedMode
    }
}

struct FilteredRecurringView: View {
    var body: some View { SnapshotTransactionsView(query: .recurring, fullscreen: true) }
}

struct FilteredTypeView: View {
    let income: Bool
    var body: some View { SnapshotTransactionsView(query: .income(income), fullscreen: true) }
}

struct FilteredCategoryView: View {
    let category: Category?
    var body: some View { SnapshotTransactionsView(query: .category(category?.objectID.uriRepresentation()), fullscreen: true) }
}

struct FilteredDateView: View {
    @AnalyticsInput private var environment
    let date: Date
    var body: some View {
        let interval = LedgerCalendar.dayInterval(containing: date, calendar: environment.calendar)
        SnapshotTransactionsView(query: .interval(start: interval?.start ?? date, end: interval?.end ?? date, income: nil, category: nil), fullscreen: true, dayHeaders: false)
    }
}

struct NoResultsView: View {
    let fullscreen: Bool

    var body: some View {
        if fullscreen {
            VStack(spacing: 12) {
                Spacer()

                Image(systemName: "tray.full.fill")
                    .font(.system(.largeTitle, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 38, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Text("No entries found.")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: UIScreen.main.bounds.height * 0.7)
            .opacity(0.7)
        } else {
            VStack(spacing: 12) {
                Spacer()

                //            Text("📭️")
                //                .font(.system(size: 45))
                //                .padding(.bottom, 9)
                //                .accessibility(hidden: true)

                Image(systemName: "tray.full.fill")
                    .font(.system(size: 38, weight: .regular, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Text("No entries found.")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .opacity(0.7)
            .padding(.top, 50)
        }
    }
}

func dateConverter(date: Date) -> String {
    let calendar = Calendar.current

    let dateComponents = calendar.dateComponents([.year], from: Date.now)

    let startOfCurrentYear = calendar.date(from: dateComponents) ?? Date.now

    if calendar.isDateInToday(date) {
        return String(localized: "today")
    } else if calendar.isDateInYesterday(date) {
        return String(localized: "yesterday")
    } else if startOfCurrentYear > date {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("EEEdMMMyy")

        return dateFormatter.string(from: date)
    } else {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("EEEdMMM")

        return dateFormatter.string(from: date)
    }
}

func dateConverterAccessibilityLabel(date: Date) -> String {
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
        return String(localized: "today")
    } else if calendar.isDateInYesterday(date) {
        return String(localized: "yesterday")
    } else {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("EEEdMMMyyyy")

        return String(localized: "on \(dateFormatter.string(from: date))")
    }
}

func dayTotal(dayTransaction: [Transaction]) -> Double {
    var total = 0.0

    dayTransaction.forEach { transaction in
        if transaction.income {
            total += transaction.amount
        } else {
            total -= transaction.amount
        }
    }

    return total
}
