//
//  GetInsightsIntent.swift
//  LittleSaver
//
//  Created by Rafael Soh on 5/8/23.
//

import LittleSaverCore
import AppIntents
import Foundation
import SwiftUI

@available(iOS 16.4, *)
struct GetInsightsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Insights"

    static var description =
        IntentDescription("Extracts your total expenditure or income for a particular time period")

    @Parameter(title: "Type", description: "Type of Data", requestValueDialog: IntentDialog("Which of the following would you like to extract?"))
    var type: ShortcutsInsightsType

    @Parameter(title: "Time Frame", description: "Time Frame of Data", requestValueDialog: IntentDialog("Over what time frame would you like to consider?"))
    var timeframe: ShortcutsInsightsTimeFrame

    @Parameter(title: "Category Filters", description: "Additional Category Filters", requestValueDialog: IntentDialog("Which additional category filters do you want to impose?"))
    var incomeCategories: [IncomeCategoryEntity]?

    @Parameter(title: "Category Filters", description: "Additional Category Filters", requestValueDialog: IntentDialog("Which additional category filters do you want to impose?"))
    var expenseCategories: [ExpenseCategoryEntity]?

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ShowsSnippetView & ProvidesDialog {
        let dataController = DataController.platformShared
//        let dataController = DataController()

        let optionalIncome: Bool?
        let categoryIDs: [UUID]
        switch type {
        case .net:
            optionalIncome = nil
            categoryIDs = []
        case .income:
            optionalIncome = true
            categoryIDs = incomeCategories?.map(\.id) ?? []
        case .spent:
            optionalIncome = false
            categoryIDs = expenseCategories?.map(\.id) ?? []
        }
        let values = try await dataController.transactionSnapshots(type: timeframe.rawValue, income: optionalIncome, categoryIDs: categoryIDs)
        let result = NumericSafety.finiteOrZero(values.reduce(0) {
            $0 + (optionalIncome == nil && !$1.income ? -$1.amount : $1.amount)
        })

        return .result(value: result, dialog: "Here you go!") {
            ShortcutInsightsView(amount: result, type: type, timeframe: timeframe)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\GetInsightsIntent.$type) {
            Case(ShortcutsInsightsType.net) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)")
            }
            Case(ShortcutsInsightsType.income) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)") {
                    \.$incomeCategories
                }
            }
            Case(ShortcutsInsightsType.spent) {
                Summary("Calculate \(\.$type) for \(\.$timeframe)") {
                    \.$expenseCategories
                }
            }
            DefaultCase {
                Summary("Calculate \(\.$type) for \(\.$timeframe)")
            }
        }
    }
}

enum ShortcutsInsightsTimeFrame: Int {
    case day = 1
    case week = 2
    case month = 3
    case year = 4
    case all = 5
}

@available(iOS 16, *)
extension ShortcutsInsightsTimeFrame: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Time Frame")
    }

    static var caseDisplayRepresentations: [ShortcutsInsightsTimeFrame: DisplayRepresentation] = [
        .day: DisplayRepresentation(title: "today"),
        .week: DisplayRepresentation(title: "this week"),
        .month: DisplayRepresentation(title: "this month"),
        .year: DisplayRepresentation(title: "this year"),
        .all: DisplayRepresentation(title: "all time")
    ]
}

enum ShortcutsInsightsType: String {
    case net, income, spent
}

@available(iOS 16, *)
extension ShortcutsInsightsType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Insights Type")
    }

    static var caseDisplayRepresentations: [ShortcutsInsightsType: DisplayRepresentation] = [
        .net: DisplayRepresentation(title: "net total"),
        .income: DisplayRepresentation(title: "total income"),
        .spent: DisplayRepresentation(title: "total expenditure")
    ]
}

struct ShortcutInsightsView: View {
    let amount: Double
    let type: ShortcutsInsightsType
    let timeframe: ShortcutsInsightsTimeFrame

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = Locale.current.currencyCode!

    var insightTypeText: String {
        switch type {
        case .net:
            return String(localized: "Net total")
        case .income:
            return String(localized: "Earned")
        case .spent:
            return String(localized: "Spent")
        }
    }

    var timeframeText: String {
        switch timeframe {
        case .day:
            return String(localized: "today")
        case .week:
            return String(localized: "this week")
        case .month:
            return String(localized: "this month")
        case .year:
            return String(localized: "this year")
        case .all:
            return String(localized: "all time")
        }
    }

    var amountString: String {
        localizedCurrencyAmount(amount, currencyCode: currency, showCents: showCents)
    }

    var summaryText: String {
        localizedFormat(
            "shortcut.insights.summary",
            arguments: [insightTypeText, timeframeText]
        )
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(summaryText)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(Color.SubtitleText)

            Text(amountString)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .padding(20)
    }
}
