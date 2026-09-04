//
//  LogView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import LittleSaverCore
import CoreData
import Foundation
import SwiftUI

struct LogView: View {
    @AnalyticsInput private var environment
    @Environment(\.ledgerCalendarRevision) private var calendarRevision

    @Environment(\.ledgerMetadata) private var metadata

    @EnvironmentObject var dataController: DataController
    @Environment(\.managedObjectContext) var moc

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var topEdge: CGFloat

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    @State var addTransaction = false

    // searching
    @State var searchMode = false

    // top bar
    @State var navBarText = ""
    @State var showMenu = false
    @AppStorage("logTimeFrame", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var logTimeFrame = 2
    let subtitleText = ["today", "this week", "this month", "this year"]

    // show filter menu
    @State var showFilter = false
    @State var filter = FilterType.all

    // filters
    @State var categoryFilter: Category?
    @State private var dateSelection = CalendarPeriodSelection()
    var dateFilter: Date {
        get { dateSelection.start(period: .day, now: environment.now, calendar: environment.calendar) }
        nonmutating set { dateSelection.select(newValue, period: .day, now: environment.now, calendar: environment.calendar) }
    }
    @State private var weekSelection = CalendarPeriodSelection()
    var weekFilter: Date {
        get { weekSelection.start(period: .week, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday) }
        nonmutating set { weekSelection.select(newValue, period: .week, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday) }
    }
    @State private var monthSelection = CalendarPeriodSelection()
    var monthFilter: Date {
        get { monthSelection.start(period: .month, now: environment.now, calendar: environment.calendar) }
        nonmutating set { monthSelection.select(newValue, period: .month, now: environment.now, calendar: environment.calendar) }
    }
    @State var income = false

    // to show/hide tab bar
    var bottomEdge: CGFloat
    var launchSearch: Bool

    @State var progress = 0.0

    var body: some View {
        let _ = calendarRevision
        if metadata == nil { ProgressView() }
        else if metadata?.hasTransactions != true {
            LogEmptyState()
        } else {
            VStack(spacing: 0) {
                LogHeaderView(
                    searchMode: $searchMode,
                    showFilter: $showFilter,
                    filter: $filter,
                    categoryFilter: $categoryFilter,
                    dateFilter: Binding(get: { dateFilter }, set: { dateFilter = $0 }),
                    weekFilter: Binding(get: { weekFilter }, set: { weekFilter = $0 }),
                    monthFilter: Binding(get: { monthFilter }, set: { monthFilter = $0 }),
                    income: $income,
                    progress: progress,
                    topEdge: topEdge
                )

                ScrollView(showsIndicators: false) {
                    if filter == .all {
                        LogInsightsView(navBarText: $navBarText, showCents: showCents, currencySymbol: currencySymbol)
                    }

                    TransactionsList(filter: filter, category: categoryFilter, date: dateFilter, week: weekFilter, month: monthFilter, income: income)
                        .zIndex(0)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 70 + bottomEdge)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.PrimaryBackground)
            .fullScreenCover(isPresented: $searchMode) {
                SearchView()
            }
            .onChange(of: launchSearch) { _ in
                searchMode = true
            }
        }
    }
}
