//
//  InsightsMonthGraphView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

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
