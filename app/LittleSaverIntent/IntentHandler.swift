//
//  IntentHandler.swift
//  LittleSaverIntent
//
//  Created by Rafael Soh on 17/8/22.
//

import LittleSaverCore
import Intents

class IntentHandler: INExtension, BudgetWidgetConfigurationIntentHandling {
//    let dataController = DataController()
    let dataController = DataController.platformShared

    func provideBudgetOptionsCollection(for _: BudgetWidgetConfigurationIntent, with completion: @escaping (INObjectCollection<WidgetBudget>?, Error?) -> Void) {
        do {
            let budgets: [WidgetBudget] = try dataController.performViewContextRead { context in
                try context.fetch(dataController.fetchRequestForBudgets()).compactMap { budget -> WidgetBudget? in
                    guard BudgetValidation.isUsable(
                        startDate: budget.startDate,
                        hasCategory: budget.category != nil
                    ) else { return nil }
                    return WidgetBudget(
                        identifier: budget.objectID.uriRepresentation().absoluteString,
                        display: budget.wrappedName
                    )
                }
            }
            completion(INObjectCollection(items: budgets), nil)
        } catch {
            let error = NSError(
                domain: AppIdentifiers.intentBundle,
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            )
            completion(nil, error)
        }
    }

    override func handler(for _: INIntent) -> Any {
        // This is the default implementation.  If you want different objects to handle different intents,
        // you can override this and return the handler you want for that particular intent.

        return self
    }
}
