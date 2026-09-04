//
//  InsightsFilteredViews.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

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
