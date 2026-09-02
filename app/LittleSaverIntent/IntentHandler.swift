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
        Task {
            do {
                let budgets = try await dataController.budgetSnapshots().map {
                    WidgetBudget(identifier: $0.identifier, display: $0.name)
                }
                completion(INObjectCollection(items: budgets), nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    override func handler(for _: INIntent) -> Any {
        // This is the default implementation.  If you want different objects to handle different intents,
        // you can override this and return the handler you want for that particular intent.

        return self
    }
}
