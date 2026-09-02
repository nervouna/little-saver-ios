//
//  BudgetInsightsIntent.swift
//  LittleSaver
//
//  Created by Rafael Soh on 6/8/23.
//

import LittleSaverCore
import AppIntents
import Foundation
import SwiftUI

@available(iOS 16.4, *)
struct BudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Budget Insights"

    static var description =
        IntentDescription("Extract leftover amount for a particular budget")

    @Parameter(title: "Budget Type", requestValueDialog: IntentDialog("What budget type would you like to extract insights from?"))
    var type: ShortcutsBudgetsType

    @Parameter(title: "Category Budget", requestValueDialog: IntentDialog("Select a categorical budget."))
    var budget: BudgetEntity?

    @MainActor
    func perform() async throws -> some ReturnsValue<Double> & ShowsSnippetView & ProvidesDialog {
        if type == .category && budget == nil {
            throw $budget.needsValueError()
        }

//        let dataController = DataController()

        let dataController = DataController.platformShared

        let snapshot: BudgetReadSnapshot?
        switch type {
        case .overall: snapshot = try await dataController.mainBudgetSnapshot()
        case .category: snapshot = try await dataController.budgetSnapshot(identifier: budget?.id.uuidString ?? "")
        }
        guard let snapshot else { throw CustomError.notFound }
        let amount = NumericSafety.finiteOrZero(snapshot.amount - snapshot.spent)
        let budgetType = snapshot.type

        return .result(value: amount, dialog: "Here you go!") {
            ShortcutBudgetView(amount: amount, type: Int(budgetType))
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\BudgetIntent.$type) {
            Case(ShortcutsBudgetsType.category) {
                Summary("Calculate leftover amount for the \(\.$budget) \(\.$type)")
            }
            Case(ShortcutsBudgetsType.overall) {
                Summary("Calculate leftover amount for the \(\.$type)")
            }
            DefaultCase {
                Summary("Calculate leftover amount for the \(\.$type)")
            }
        }
    }
}

enum ShortcutsBudgetsType: String {
    case overall, category
}

@available(iOS 16, *)
extension ShortcutsBudgetsType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(name: "Budget Type")
    }

    static var caseDisplayRepresentations: [ShortcutsBudgetsType: DisplayRepresentation] = [
        .overall: DisplayRepresentation(title: "overall budget"),
        .category: DisplayRepresentation(title: "categorical budget")
    ]
}

struct ShortcutBudgetView: View {
    let amount: Double
    let type: Int

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = Locale.current.currencyCode!

    var budgetType: String {
        switch type {
        case 1:
            return String(localized: "today")
        case 2:
            return String(localized: "this week")
        case 3:
            return String(localized: "this month")
        case 4:
            return String(localized: "this year")
        default:
            return String(localized: "this week")
        }
    }

    var amountString: String {
        localizedCurrencyAmount(abs(amount), currencyCode: currency, showCents: showCents)
    }

    var statusText: String {
        localizedFormat(
            amount > 0 ? "shortcut.budget.left" : "shortcut.budget.over",
            arguments: [budgetType]
        )
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(amountString)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .lineLimit(1)

            Text(statusText)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Color.SubtitleText)
        }
        .padding(20)
    }
}
