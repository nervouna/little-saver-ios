//
//  BudgetGraphs.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

struct AnimatedHorizontalBarGraphBudget: View {
    let category: Category

    @State var showBar: Bool = false
    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                .foregroundColor(Color(hex: category.wrappedColour))
                .frame(width: showBar ? nil : 0, alignment: .leading)

            Spacer(minLength: 0)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if !animated {
                    showBar = true
                } else {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        showBar = true
                    }
                }
            }
        }
    }
}

struct AnimatedHorizontalBarGraphMainBudget: View {
    @State var showBar: Bool = false
    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                .fill(Color.DarkBackground)
                .frame(width: showBar ? nil : 0, alignment: .leading)

            Spacer(minLength: 0)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if !animated {
                    showBar = true
                } else {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        showBar = true
                    }
                }
            }
        }
    }
}

struct AnimatedCurvedBarGraphBudget: View {
    var spent: Double
    var budgetTotal: Double
    let cornerRadius: Double
    let width: Double
    let color: String
    var percent: Double { 1 - BudgetMath.gaugeRatio(spent: spent, budgetAmount: budgetTotal) }

    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true

    var body: some View {
        DonutSemicircle(percent: percent, cornerRadius: cornerRadius, width: width)
            .fill(Color(color))
            .animation(animated ? .easeInOut(duration: 0.7) : nil, value: percent)
    }
}

struct AnimatedCurvedBarGraphMainBudget: View {
    var spent: Double
    var budgetTotal: Double
    let cornerRadius: Double
    let width: Double

    var percent: Double { 1 - BudgetMath.gaugeRatio(spent: spent, budgetAmount: budgetTotal) }

    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true

    var body: some View {
        DonutSemicircle(percent: percent, cornerRadius: cornerRadius, width: width)
            .fill(Color.DarkBackground)
            .animation(animated ? .easeInOut(duration: 0.7) : nil, value: percent)
    }
}

struct BudgetStepperView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    @StateObject private var boundary = SnapshotModel<TransactionBoundaryRequest, Date?>()
    let categoryReference: URL?
    private var request: TransactionBoundaryRequest { TransactionBoundaryRequest(category: categoryReference, environment: environment) }
    @Binding var date: Date
    let startDate: Date?
    let type: Int

    private var period: BudgetPeriod? { Int16(exactly: type).flatMap(BudgetPeriod.init(rawValue:)) }
    private var selected: BudgetWindow? {
        guard let anchor = startDate else { return nil }
        return period?.window(anchor: anchor, containing: date, calendar: environment.calendar)
    }
    private var latest: BudgetWindow? { period?.currentWindow(anchor: startDate, amount: 1, now: environment.now, calendar: environment.calendar) }
    private var earliestIndex: Int {
        guard let anchor = startDate, let earliest = boundary.value(for: request) ?? nil else { return latest?.index ?? 0 }
        return min(latest?.index ?? 0, period?.window(anchor: anchor, containing: earliest, calendar: environment.calendar)?.index ?? 0)
    }
    private func move(_ delta: Int) {
        guard let anchor = startDate, let selected, let latest else { return }
        let index = min(latest.index, max(earliestIndex, selected.index + delta))
        if let window = period?.window(anchor: anchor, index: index, calendar: environment.calendar) { date = window.start }
    }
    var body: some View {
        VStack(spacing: 8) {
            navigation
            if let error = boundary.error {
                Text(error).font(.caption).multilineTextAlignment(.center)
                Button("Retry") { Task { await boundary.load(key: request, using: controller.earliestTransactionDate) } }
            }
        }
        .task(id: request) { await boundary.load(key: request, using: controller.earliestTransactionDate) }
    }

    private var navigation: some View {
        HStack {
            StepperButtonView(left: true, disabled: (selected?.index ?? 0) <= earliestIndex) { move(-1) }
            Spacer()
            Text(selected.map { localizedDateInterval(from: $0.start, to: $0.end.addingTimeInterval(-1)) } ?? String(localized: "Date unavailable"))
                .font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            StepperButtonView(left: false, disabled: (selected?.index ?? 0) >= (latest?.index ?? 0)) { move(1) }
        }
        .frame(maxWidth: .infinity)
    }
    init(category: Category?, date: Binding<Date>, startDate: Date?, budgetType: Int) {
        categoryReference = category?.objectID.uriRepresentation()
        _date = date
        self.startDate = startDate
        type = budgetType
    }
}
