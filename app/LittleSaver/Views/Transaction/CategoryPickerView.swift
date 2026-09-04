//
//  CategoryPickerView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 14/5/22.
//

import LittleSaverCore
import Combine
import Foundation
import Popovers
import SwiftUI

struct CategoryPickerView: View {
    @Binding var category: Category?
    @Binding var showPicker: Bool
    @Binding var showingCategoryView: Bool
    @FetchRequest private var categories: FetchedResults<Category>

    let initialCategory: Category?

    var darkMode: Bool

    var backgroundColor: Color {
        if darkMode {
            return Color("AlwaysDarkBackground")
        } else {
            return Color("AlwaysLightBackground")
        }
    }

    var secondaryBackgroundColor: Color {
        if darkMode {
            return Color("AlwaysDarkSecondaryBackground")
        } else {
            return Color("AlwaysLightSecondaryBackground")
        }
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var heightOfScrollView: Double {
        let fontSize = UIFont.getBodyFontSize(dynamicTypeSize: dynamicTypeSize)

        let font = UIFont.rounded(ofSize: fontSize, weight: .semibold)

        if categories.count == 1 && initialCategory != nil {
            return font.lineHeight + 14.1
        }

        if initialCategory != nil {
            let height = Double(min(6, categories.count)) * (font.lineHeight + 14.1)
            let gap = Double(min(5, categories.count - 1)) * 8.0
            return height + gap
        } else {
            let height = Double(min(6, categories.count + 1)) * (font.lineHeight + 14.1)
            let gap = Double(min(5, categories.count)) * 8.0
            return height + gap
        }
    }

    var body: some View {
        //        VStack(alignment: .trailing, spacing: 8) {

        //            if categories.count > 1 || category == nil {
        HStack {
            Color.clear
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    showPicker = false
                }

            VStack(
                alignment: .trailing, spacing: (categories.count == 1 && initialCategory != nil) ? 0 : 8
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Edit")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundColor(darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground"))
                .background(
                    RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                        .fill(
                            darkMode
                            ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground"))
                )
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .onTapGesture {
                    let impactMed = UIImpactFeedbackGenerator(style: .light)
                    impactMed.impactOccurred()
                    showPicker = false
                    showingCategoryView = true
                }

                ScrollView(showsIndicators: false) {
                    ScrollViewReader { value in
                        VStack(alignment: .trailing, spacing: 8) {
                            ForEach(categories) { item in
                                if item != initialCategory {
                                    HStack(spacing: 7) {
                                        Text(item.wrappedEmoji)
                                            .font(.system(.footnote, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        //                                                    .font(.system(size: 14))
                                        Text(item.wrappedName)
                                            .font(.system(.body, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        //                                                    .font(.system(size: 17.5, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                    }
                                    .id(item.id)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .foregroundColor(
                                        darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground")
                                    )
                                    .background(
                                        item == category ? secondaryBackgroundColor : backgroundColor,
                                        in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                    )
                                    .contentShape(Rectangle())
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                            .strokeBorder(
                                                darkMode ? Color("AlwaysDarkOutline") : Color("AlwaysLightOutline"),
                                                style: StrokeStyle(lineWidth: 1.5))
                                    }
                                    .onTapGesture {
                                        if category == item {
                                            category = nil
                                        } else {
                                            category = item
                                        }

                                        showPicker = false
                                        //
                                    }
                                }
                            }
                        }
                        .onAppear {
                            if let last = categories.last {
                                if category == last && categories.count > 2 {
                                    value.scrollTo(categories[categories.count - 2].id)
                                } else {
                                    value.scrollTo(last.id)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: heightOfScrollView)
        //            }
    }

    init(
        category: Binding<Category?>?, showPicker: Binding<Bool>, showSheet: Binding<Bool>,
        income: Bool, darkMode: Bool
    ) {
        _categories = FetchRequest<Category>(
            sortDescriptors: [
                SortDescriptor(\.order, order: .reverse)
            ], predicate: NSPredicate(format: "income = %d", income))
        self.darkMode = darkMode
        initialCategory = category?.wrappedValue
        _category = category ?? Binding.constant(nil)
        _showPicker = showPicker
        _showingCategoryView = showSheet
    }
}
