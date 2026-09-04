//
//  InsightsYearGraphView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

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
