//
//  InsightsPieChart.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

struct HorizontalPieChartView: View {
    @Environment(\.managedObjectContext) private var context
    let snapshot: BucketSnapshot

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var income: Bool
    var date: Date
    var total: Double { snapshot.amount }

    @Binding var chosenAmount: Double
    @Binding var chosenName: String

    @Binding var categoryFilterMode: Bool
    @Binding var categoryFilter: Category?
    @Binding var selectedDate: Date?

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 12
        case .small:
            return 13
        case .medium:
            return 14
        case .large:
            return 15
        case .xLarge:
            return 17
        case .xxLarge:
            return 19
        case .xxxLarge:
            return 21
        default:
            return 15
        }
    }

    var percentWidth: CGFloat {
        return "100%".widthOfRoundedString(size: fontSize, weight: .medium) + 4
    }

    var categories: [PowerCategory] {
        snapshot.categories.compactMap { row in
            guard let category: Category = presentationObject(row.id, in: context) else { return nil }
            return PowerCategory(id: row.id, category: category, percent: row.percent, amount: row.amount)
        }
    }

    var body: some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !categoryFilterMode {
                    Text("Categories")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.SubtitleText)

                    GeometryReader { proxy in
                        HStack(spacing: proxy.size.width * 0.015) {
                            ForEach(categories) { category in
                                if category.percent < 0.005 {
                                    EmptyView()
                                } else {
                                    AnimatedHorizontalBarGraph(category: category, index: categories.firstIndex(of: category) ?? 0)
                                        .frame(width: (proxy.size.width * (1.0 - (0.015 * Double(categories.count - 1)))) * category.percent)
                                        .onTapGesture {
                                            withAnimation(.easeInOut) {
                                                if categoryFilter == category.category {
                                                    selectedDate = nil
                                                    categoryFilterMode = false
                                                    categoryFilter = nil
                                                } else {
                                                    selectedDate = nil
                                                    categoryFilterMode = true
                                                    categoryFilter = category.category
                                                    chosenAmount = category.amount
                                                    chosenName = category.category.wrappedName
                                                }
                                            }
                                        }
                                        .opacity(categoryFilterMode ? (categoryFilter == category.category ? 1 : 0.5) : 1)
                                        .overlay {
                                            if categoryFilterMode && categoryFilter == category.category {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(Color.DarkBackground, lineWidth: 1.5)
                                            }
                                        }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 17)
                    .padding(.bottom, 10)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(categories, id: \.self) { category in
                            if !categoryFilterMode || categoryFilter == category.category {
                                let boxColor = category.category.income ? Color(hex: Color.colorArray[categories.firstIndex(of: category) ?? 0]) : Color(hex: category.category.wrappedColour)

                                HStack(spacing: 10) {

                                    Text(category.category.fullName)
                                        .font(.system(.title3, design: .rounded).weight(.semibold))
                                        .foregroundColor(Color.PrimaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(currencySymbol)\(category.amount, specifier: (showCents && category.amount < 100) ? "%.2f" : "%.0f")")
                                        .font(.system(categoryFilterMode && categoryFilter == category.category ? .title3 : .body, design: .rounded).weight(.medium))
                                        .foregroundColor(Color.SubtitleText)
                                        .lineLimit(1)
                                        .layoutPriority(1)

                                    if categoryFilterMode && categoryFilter == category.category {
                                        Button {
                                            withAnimation(.easeInOut) {
                                                selectedDate = nil
                                                categoryFilterMode = false
                                                categoryFilter = nil
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                                .foregroundColor(Color.SubtitleText)
                                                .padding(5)
                                                .background(Color.SecondaryBackground, in: Circle())
                                        }

                                    } else {

                                        Text("\(category.percent * 100, specifier: "%.0f")%")
                                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                            .foregroundColor(boxColor)
                                            .padding(.vertical, 3)
                                            .frame(width: percentWidth)
                                            .background(boxColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                .padding(.vertical, categoryFilterMode && categoryFilter == category.category ? 10 : 5)
                                .padding(.horizontal, categoryFilterMode && categoryFilter == category.category ? 10 : 0)
                                .background(RoundedRectangle(cornerRadius: 12).fill(categoryFilterMode && categoryFilter == category.category ? Color.TertiaryBackground : Color.PrimaryBackground))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(categoryFilterMode && categoryFilter == category.category ? Color.Outline : Color.clear, lineWidth: 1.3))
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .drawingGroup()
                                .onTapGesture {
                                    withAnimation(.easeInOut) {
                                        if !categoryFilterMode {
                                            selectedDate = nil
                                            categoryFilterMode = true
                                            categoryFilter = category.category
                                            chosenAmount = category.amount
                                            chosenName = category.category.wrappedName
                                        }
                                    }
                                }

                            }

                        }
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    init(date: Date, categoryFilter: Binding<Category?>?, categoryFilterMode: Binding<Bool>, selectedDate: Binding<Date?>?, chosenAmount: Binding<Double>, chosenName: Binding<String>, type: ChartTimeFrame, income: Bool, snapshot: BucketSnapshot) {
        self.date = date
        self.income = income
        _categoryFilter = categoryFilter ?? Binding.constant(nil)
        _categoryFilterMode = categoryFilterMode
        _selectedDate = selectedDate ?? Binding.constant(nil)
        _chosenName = chosenName
        _chosenAmount = chosenAmount

        self.snapshot = snapshot
    }
}

struct AnimatedHorizontalBarGraph: View {
    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true
    var category: PowerCategory
    var index: Int

    @State var showBar: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(category.category.income ? Color(hex: Color.colorArray[index]) : Color(hex: category.category.wrappedColour))
                .frame(width: showBar ? nil : 0, alignment: .leading)

            Spacer(minLength: 0)
        }
//        .onAppear {
//            DispatchQueue.main.asyncAfter(deadline: .now()) {
//                if !animated {
//                    showBar = true
//                } else {
//                    withAnimation(.easeInOut(duration: 0.7).delay(Double(index) * 0.5)) {
//                        showBar = true
//                    }
//                }
//            }
//        }
    }
}
