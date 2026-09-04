//
//  SuggestedCategoriesView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 10/5/22.
//

import LittleSaverCore
import Combine
import CoreHaptics
import Popovers
import SwiftUI
import UIKit

struct SuggestedCategoriesView: View {
    let income: Bool
    @FetchRequest private var categories: FetchedResults<Category>

    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    var nameArray: [String] {
        var emptyArray = [String]()

        categories.forEach { category in
            emptyArray.append(category.wrappedName)
        }

        return emptyArray
    }

    var emojiArray: [String] {
        var emptyArray = [String]()

        categories.forEach { category in
            emptyArray.append(category.wrappedEmoji)
        }

        return emptyArray
    }

    var suggestions: [SuggestedCategory] {
        var holding = [SuggestedCategory]()

        if income {
            SuggestedCategory.incomes.forEach { category in
                if !nameArray.contains(category.localizedName) && !emojiArray.contains(category.emoji) {
                    holding.append(category)
                }
            }
        } else {
            SuggestedCategory.expenses.forEach { category in
                if !nameArray.contains(category.localizedName) && !emojiArray.contains(category.emoji) {
                    holding.append(category)
                }
            }
        }

        return holding
    }

    @State private var availableColours: [String] = Color.colorArray
    @State private var selectedColour = "1"

    var body: some View {
        if !suggestions.isEmpty {
            Section(header: Text("SUGGESTED").foregroundColor(Color.SubtitleText)) {
                ForEach(suggestions, id: \.self) { category in
                    HStack(spacing: 8) {
                        Text(category.emoji)
//                            .font(.system(size: 15))
                            .font(.system(.subheadline, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Text(category.localizedName)
                            .font(.system(.body, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 18.5, weight: .regular, design: .rounded))
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "plus")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(4)
                            .background(Color.SecondaryBackground, in: Circle())
                            .contentShape(Circle())
                    }
                    .padding(.vertical, 5)
                    .foregroundColor(Color.PrimaryText)
                    .listRowBackground(Color.SettingsBackground)
                    .listRowSeparatorTint(Color.Outline)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // double check

                        let (outcome, _) = dataController.categoryCheck(name: category.localizedName, emoji: category.emoji, income: income)

                        if outcome != .none {
                            return
                        }

                        let input = CategoryInput(name: category.localizedName, emoji: category.emoji, colour: selectedColour, income: income)
                        dataController.submitMutation({
                            try await dataController.saveCategory(input)
                        }, success: { _ in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            availableColours = Color.colorArray.filter { colour in
                                !categories.contains { $0.wrappedColour == colour }
                            }
                            selectedColour = availableColours.first ?? "#FFFFFF"
                        })
                    }
                }
            }
            .onAppear {
                if !income {
                    categories.forEach { category in
                        if availableColours.contains(category.wrappedColour) {
                            availableColours.remove(at: availableColours.firstIndex(of: category.wrappedColour) ?? 0)
                        }
                    }

                    if availableColours.isEmpty {
                        selectedColour = "#FFFFFF"
                    } else {
                        selectedColour = availableColours[0]
                    }
                }
            }
        }
    }

    init(income: Bool) {
        _categories = FetchRequest<Category>(sortDescriptors: [
            SortDescriptor(\.order)
        ], predicate: NSPredicate(format: "income = %d", income))

        self.income = income
    }
}
