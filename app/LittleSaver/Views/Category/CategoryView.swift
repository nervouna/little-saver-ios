//
//  CategoryView.swift
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

enum CategoryViewMode {
    case welcome, settings, transaction
}

struct CategoryView: View {
    var mode: CategoryViewMode
//    @Environment(\.colorScheme) var colorScheme
    @State var income = false
    @Namespace var animation

    @State var newCategory = false

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)], predicate: NSPredicate(format: "income = %d", false)) private var expenseCategories: FetchedResults<Category>

    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""
    @State var positive = false

    var disabled: Bool {
        income == false && expenseCategories.count >= 24
    }

    var body: some View { content.modifier(MutationPendingModifier()) }

    @ViewBuilder private var content: some View {
        VStack(spacing: 5) {
            CategoryListView(income: $income, mode: mode, showToast: $showToast, toastTitle: $toastTitle, toastImage: $toastImage, positive: $positive)

            HStack {
                HStack(spacing: 0) {
                    Text("Expense")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(income == false ? Color.PrimaryText : Color.SubtitleText)
                        .padding(6)
                        .padding(.horizontal, 8)
                        .background {
                            if income == false {
                                Capsule()
                                    .fill(Color.SecondaryBackground)
                                    .matchedGeometryEffect(id: "TAB1", in: animation)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            DispatchQueue.main.async {
                                withAnimation(.easeIn(duration: 0.15)) {
                                    income = false
                                }
                            }
                        }

                    Text("Income")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(income == true ? Color.PrimaryText : Color.SubtitleText)
                        .padding(6)
                        .padding(.horizontal, 8)
                        .background {
                            if income == true {
                                Capsule()
                                    .fill(Color.SecondaryBackground)
                                    .matchedGeometryEffect(id: "TAB1", in: animation)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            DispatchQueue.main.async {
                                withAnimation(.easeIn(duration: 0.15)) {
                                    income = true
                                }
                            }
                        }
                }
                .padding(3)
                .layoutPriority(1)
                .overlay(Capsule().stroke(Color.Outline.opacity(0.4), lineWidth: 1.3))

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))

                    Text("New")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(Color.PrimaryText)
                .padding(6)
                .padding(.horizontal, 4.5)
                .background(Color.SecondaryBackground, in: Capsule())
                .opacity(disabled ? 0.5 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    if disabled {
                        showToast = true
                        toastImage = "exclamationmark.triangle.fill"
                        toastTitle = String(localized: "Limit Exceeded")
                        positive = false
                    } else {
                        newCategory = true
                    }
                }
            }
            .padding(25)
        }
        .sheet(isPresented: $newCategory) {
            if #available(iOS 16.0, *) {
                NewCategoryAlert(income: $income, bottomSpacers: false)
                    .presentationDetents([.height(270)])
            } else {
                NewCategoryAlert(income: $income, bottomSpacers: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard, edges: .all)
        .background(Color.PrimaryBackground)
    }
}
