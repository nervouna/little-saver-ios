//
//  LogFilterSteppers.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import LittleSaverCore
import CoreData
import Foundation
import Popovers
import SwiftUI

struct CategoryStepperView: View {
    @Binding var categoryFilter: Category?
    @Environment(\.ledgerMetadata) private var metadata
    @Environment(\.managedObjectContext) private var context
    @State var income = false
    private var categories: [Category] { categoryObjects(income: income) }
    private func categoryObjects(income: Bool) -> [Category] {
        (metadata?.categories ?? []).filter { $0.income == income }.compactMap { presentationObject($0.id, in: context) }
    }

    var body: some View {
        HStack(spacing: 8) {
            if income {
                Image(systemName: "plus")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.IncomeGreen)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(1.0, contentMode: .fit)
//                    .frame(width: 36, height: 36)
                    .background(Color.IncomeGreen.opacity(0.23), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let holding = categoryObjects(income: false)

                        if holding.isEmpty {
                            return
                        } else {
                            income = false
                            categoryFilter = holding.first
                        }
                    }
            } else {
                Image(systemName: "minus")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.AlertRed)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(1.0, contentMode: .fit)
//                    .frame(width: 36, height: 36)
                    .background(Color.AlertRed.opacity(0.23), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let holding = categoryObjects(income: true)

                        if holding.isEmpty {
                            return
                        } else {
                            income = true
                            categoryFilter = holding.first
                        }
                    }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { value in
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { item in
                            HStack(spacing: 5) {
                                Text(item.wrappedEmoji)
                                    .font(.system(.footnote, design: .rounded).weight(.medium))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                    .font(.system(size: 13))
                                Text(item.wrappedName)
//                                    .font(.system(size: 17.5, weight: .medium, design: .rounded))
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            }
                            .id(item.id)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .fixedSize(horizontal: false, vertical: true)
//                            .frame(height: 36)
                            .foregroundColor(categoryFilter == item ? Color(hex: item.wrappedColour) : Color.PrimaryText)
                            .background(getBackground(category: item), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if categoryFilter != item {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.Outline,
                                                      style: StrokeStyle(lineWidth: 1.5))
                                }
                            }
                            .onTapGesture {
                                categoryFilter = item
                                withAnimation {
                                    value.scrollTo(item.id, anchor: .leading)
                                }
                            }
//                            .accessibilityElement(children: .ignore)
//                            .accessibilityLabel("filter \(item.wrappedName) transactions button")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .onAppear {
            if categories.isEmpty {
                categoryFilter = nil
            } else {
                categoryFilter = categories[0]
            }
        }
        .onChange(of: categories.map(\.objectID)) { _ in
            if categories.isEmpty {
                categoryFilter = nil
            } else {
                categoryFilter = categories[0]
            }
        }
    }

    func getBackground(category: Category) -> Color {
        if category == categoryFilter {
            return Color(hex: category.wrappedColour).opacity(0.3)
        } else {
            return Color.PrimaryBackground
        }
    }

    init(categoryFilter: Binding<Category?>?) {
        _categoryFilter = categoryFilter ?? Binding.constant(nil)
    }
}

struct IncomeFilterToggleView: View {
    @Binding var income: Bool

    @Namespace var animation

    var body: some View {
        HStack(spacing: 0) {
            Text("Expense")
//                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(income == false ? Color.PrimaryText : Color.SubtitleText)
                .padding(5.5)
                .padding(.horizontal, 8)
                .background {
                    if income == false {
                        Capsule()
                            .fill(Color.SecondaryBackground)
                            .matchedGeometryEffect(id: "TAB1", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    DispatchQueue.main.async {
                        withAnimation(.easeIn(duration: 0.15)) {
                            income = false
                        }
                    }
                }

            Text("filter-picker-income")
//                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundColor(income == true ? Color.PrimaryText : Color.SubtitleText)
                .padding(5.5)
                .padding(.horizontal, 8)
                .background {
                    if income == true {
                        Capsule()
                            .fill(Color.SecondaryBackground)
                            .matchedGeometryEffect(id: "TAB1", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    DispatchQueue.main.async {
                        withAnimation(.easeIn(duration: 0.15)) {
                            income = true
                        }
                    }
                }
        }
        .padding(3)
        .overlay(Capsule().stroke(Color.Outline.opacity(0.4), lineWidth: 1.3))
    }
}

struct DateStepperView: View {
    @Environment(\.ledgerMetadata) private var metadata
    @AnalyticsInput private var environment

    @Binding var date: Date
    var endDate: Date { environment.calendar.startOfDay(for: metadata?.earliestDate ?? environment.now) }

    var currentDate: Date { environment.calendar.startOfDay(for: environment.now) }

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.dateStyle = .medium

        return dateFormatter.string(from: date)
    }

    var body: some View {
        HStack {
            StepperButtonView(left: true, disabled: date <= endDate) {
                if date > endDate {
                    date = environment.calendar.date(byAdding: .day, value: -1, to: date) ?? environment.now
                }
            }
            .accessibilityLabel("previous day")

            Spacer()

            Text(dateString)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                .font(.system(size: 20, weight: .bold, design: .rounded))
                .accessibilityLabel("showing transactions on \(dateString)")

            Spacer()

            StepperButtonView(left: false, disabled: date >= currentDate) {
                if date < currentDate {
                    date = environment.calendar.date(byAdding: .day, value: 1, to: date) ?? environment.now
                }
            }
            .accessibilityLabel("next day")
        }
        .frame(maxWidth: .infinity)
    }
}

struct WeekStepperView: View {
    @Environment(\.ledgerMetadata) private var metadata
    @AnalyticsInput private var environment

    @Binding var showingDate: Date
    var endDate: Date {
        let earliest = metadata?.earliestDate ?? environment.now
        return CalendarPeriodSelection(start: earliest, calendar: environment.calendar).start(period: .week, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday)
    }

    var startDate: Date {
        let latest = metadata?.latestDate ?? environment.now
        return CalendarPeriodSelection(start: latest, calendar: environment.calendar).start(period: .week, now: environment.now, calendar: environment.calendar, firstWeekday: environment.calendar.firstWeekday)
    }

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")

        let endComponents = DateComponents(day: 7, second: -1)
        let endWeekDate = environment.calendar.date(byAdding: endComponents, to: showingDate) ?? environment.now

        return dateFormatter.string(from: showingDate) + " - " + dateFormatter.string(from: endWeekDate)
    }

    var accessibilityDateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")

        let endComponents = DateComponents(day: 7, second: -1)
        let endWeekDate = environment.calendar.date(byAdding: endComponents, to: showingDate) ?? environment.now

        return String(localized: "Showing transactions from \(dateFormatter.string(from: showingDate)) to \(dateFormatter.string(from: endWeekDate))")
    }

    var body: some View {
        HStack {
            StepperButtonView(left: true, disabled: showingDate == endDate) {
                if showingDate > endDate {
                    showingDate = environment.calendar.date(byAdding: .day, value: -7, to: showingDate) ?? environment.now
                }
            }
            .accessibilityLabel("previous week")

            Spacer()

            Text(dateString)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .accessibilityLabel(accessibilityDateString)

            Spacer()

            StepperButtonView(left: false, disabled: showingDate == startDate) {
                if showingDate < startDate {
                    showingDate = environment.calendar.date(byAdding: .day, value: 7, to: showingDate) ?? environment.now
                }
            }
            .accessibilityLabel("next week")
        }
        .frame(maxWidth: .infinity)
    }
}

struct MonthStepperView: View {
    @Environment(\.ledgerMetadata) private var metadata
    @AnalyticsInput private var environment

    @Binding var showingDate: Date
    var endDate: Date {
        let earliest = metadata?.earliestDate ?? environment.now
        return CalendarPeriodSelection(start: earliest, calendar: environment.calendar).start(period: .month, now: environment.now, calendar: environment.calendar)
    }

    var startDate: Date {
        let latest = metadata?.latestDate ?? environment.now
        return CalendarPeriodSelection(start: latest, calendar: environment.calendar).start(period: .month, now: environment.now, calendar: environment.calendar)
    }

    var dateString: String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("MMMyyyy")

        return dateFormatter.string(from: showingDate)
    }

    var body: some View {
        HStack {
            StepperButtonView(left: true, disabled: showingDate == endDate) {
                if showingDate > endDate {
                    showingDate = environment.calendar.date(byAdding: .month, value: -1, to: showingDate) ?? environment.now
                }
            }
            .accessibilityLabel("previous month")

            Spacer()

            Text(dateString)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .accessibilityLabel("showing transactions in \(dateString)")

            Spacer()

            StepperButtonView(left: false, disabled: showingDate == startDate) {
                if showingDate < startDate {
                    showingDate = environment.calendar.date(byAdding: .month, value: 1, to: showingDate) ?? environment.now
                }
            }
            .accessibilityLabel("next month")
        }
        .frame(maxWidth: .infinity)
    }
}
