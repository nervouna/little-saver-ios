//
//  LittleSaverWidget.swift
//  LittleSaverWidget
//
//  Created by Rafael Soh on 25/7/22.
//

import SwiftUI
import WidgetKit

@main
struct LittleSaverWidgets: WidgetBundle {
    var body: some Widget {
        RecentLittleSaverWidget()
        InsightsWidget()
        BudgetWidget()
        LockBudgetWidget()
        MainBudgetWidget()
        NewExpenseWidget()
//        TemplateTransactionWidget()
    }
}
