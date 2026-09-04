//
//  PowerCategory.swift
//  LittleSaver
//
//  Created by Rafael Soh on 6/6/22.
//

import LittleSaverCore
import Foundation
import SwiftUI

struct PowerCategory: Hashable, Identifiable {
    let id: URL
    let category: Category
    let percent: Double
    let amount: Double
}

struct SuggestedCategory: Hashable {
    let localizationKey: String
    let emoji: String

    var localizedName: String {
        String(localized: String.LocalizationValue(localizationKey))
    }

    static var expenses: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let food = SuggestedCategory(localizationKey: "Food", emoji: "🍔")
        holding.append(food)

        let transport = SuggestedCategory(localizationKey: "Transport", emoji: "🚆")
        holding.append(transport)

        let housing = SuggestedCategory(localizationKey: "Rent", emoji: "🏠")
        holding.append(housing)

        let subscriptions = SuggestedCategory(localizationKey: "Subscriptions", emoji: "🔄")
        holding.append(subscriptions)

        let groceries = SuggestedCategory(localizationKey: "Groceries", emoji: "🛒")
        holding.append(groceries)

        let family = SuggestedCategory(localizationKey: "Family", emoji: "👨‍👩‍👦")
        holding.append(family)

        let utilities = SuggestedCategory(localizationKey: "Utilities", emoji: "💡")
        holding.append(utilities)

        let fashion = SuggestedCategory(localizationKey: "Fashion", emoji: "👔")
        holding.append(fashion)

        let healthcare = SuggestedCategory(localizationKey: "Healthcare", emoji: "🚑")
        holding.append(healthcare)

        let pets = SuggestedCategory(localizationKey: "Pets", emoji: "🐕")
        holding.append(pets)

        let sneakers = SuggestedCategory(localizationKey: "Sneakers", emoji: "👟")
        holding.append(sneakers)

        let gifts = SuggestedCategory(localizationKey: "Gifts", emoji: "🎁")
        holding.append(gifts)

        return holding
    }

    static var incomes: [SuggestedCategory] {
        var holding = [SuggestedCategory]()
        let paycheck = SuggestedCategory(localizationKey: "Paycheck", emoji: "💰")
        holding.append(paycheck)

        let allowance = SuggestedCategory(localizationKey: "Allowance", emoji: "🤑")
        holding.append(allowance)

        let parttime = SuggestedCategory(localizationKey: "Part-Time", emoji: "💼")
        holding.append(parttime)

        let investments = SuggestedCategory(localizationKey: "Investments", emoji: "💹")
        holding.append(investments)

        let gifts = SuggestedCategory(localizationKey: "Gifts", emoji: "🧧")
        holding.append(gifts)

        let tips = SuggestedCategory(localizationKey: "Tips", emoji: "🪙")
        holding.append(tips)

        return holding
    }
}
