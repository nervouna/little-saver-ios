//
//  SingleBudgetView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

struct SingleBudgetView: View {
    let budget: Budget
    let snapshot: BudgetReadSnapshot?

    @Binding var toDelete: Budget?
    @Binding var toEdit: Budget?

    var totalSpent: Double { snapshot?.spent ?? .nan }

    var budgetRows: Bool

    var width: CGFloat {
        ((UIScreen.main.bounds.width - 75) / 2) - 30
    }

    var rowWidth: CGFloat {
        (UIScreen.main.bounds.width - 80) / 2
    }

    var budgetAmount: Double { snapshot?.amount ?? .nan }

    var budgetType: String {
        switch snapshot?.type {
        case 1:
            return String(localized: "today")
        case 2:
            return String(localized: "this week")
        case 3:
            return String(localized: "this month")
        case 4:
            return String(localized: "this year")
        default:
            return "this week"
        }
    }

    var timeLeft: String {
        guard let snapshot else { return String(localized: "Date unavailable") }
        if snapshot.type == 1 {
            let hours = NumericSafety.roundedInt(ceil(max(0, snapshot.endDate.timeIntervalSince(snapshot.readDate)) / 3600))
            return budgetRows ? String(localized: "\(hours)h left") : String(localized: "\(hours) hours left")
        }
        let lower = Calendar.current.startOfDay(for: max(snapshot.startDate, snapshot.readDate))
        let days = max(0, Calendar.current.dateComponents([.day], from: lower, to: snapshot.endDate).day ?? 0)
        return budgetRows ? String(localized: "\(days)d left") : String(localized: "\(days) days left")
    }

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var difference: Double {
        return abs(NumericSafety.difference(budgetAmount, totalSpent))
    }

    var percentString: String { BudgetMath.percentageText(spent: totalSpent, budgetAmount: budgetAmount, remaining: true) }

    var percentString1: String { BudgetMath.percentageText(spent: totalSpent, budgetAmount: budgetAmount, remaining: false) }

    var targetPercent: Double { 1 - (snapshot?.progress ?? 0) }

    @Environment(\.colorScheme) var colorScheme

    // swipe to delete
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @State private var offset: CGFloat = 0
    @State private var deleted: Bool = false

    var deletePopup: Bool {
        return abs(offset) > UIScreen.main.bounds.width * 0.15
    }

    var deleteConfirm: Bool {
        return abs(offset) > UIScreen.main.bounds.width * 0.50
    }

    @GestureState var isDragging = false

    @ViewBuilder var body: some View {
        if snapshot == nil {
            Text("Budget unavailable. Edit this budget to repair its settings.").padding()
        } else { budgetContent }
    }

    private var budgetContent: some View {
        Group {
            if budgetRows {
                ZStack(alignment: .trailing) {
                    Image(systemName: "xmark")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
//                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(deleteConfirm ? Color.AlertRed : Color.SubtitleText)
                        .padding(5)
                        .background(deleteConfirm ? Color.AlertRed.opacity(0.23) : Color.SecondaryBackground, in: Circle())
                        .scaleEffect(deleteConfirm ? 1.1 : 1)
                        .contentShape(Circle())
                        .opacity(deleted ? 0 : 1)
                        .padding(.horizontal, 10)
                        .offset(x: 80)
                        .offset(x: max(-80, offset))

                    HStack {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white)

                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: budget.wrappedColour).opacity(0.3))
                            }
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(budget.wrappedEmoji)
                                    .font(.system(size: 20))
                            }

                            VStack(alignment: .leading, spacing: -0.5) {
                                Text(budget.wrappedName)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
//                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundColor(Color.PrimaryText)

                                Text("\(timeLeft) • \(percentString1) spent")
                                    .font(.system(.footnote, design: .rounded).weight(.medium))
//                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundColor(Color.SubtitleText)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: -4) {
                            BudgetDollarView(amount: difference, red: totalSpent >= budgetAmount, scale: 1, size: 80)

                            Text(budgetAmount >= totalSpent
                                 ? String(localized: "left \(budgetType)")
                                 : String(localized: "over \(budgetType)"))
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundColor(Color.SubtitleText)
                        }
                    }
                    .padding(10)
                    .background(colorScheme == .dark ? Color.Outline.opacity(0.2) : Color.Outline.opacity(0.35), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 13))
                    .contextMenu {
                        Button {
                            toEdit = budget

                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            toDelete = budget
                        } label: {
                            Label("Delete", systemImage: "xmark.bin")
                        }
                    }
                    .offset(x: offset)
                }
                .padding(.horizontal, 30)
                .onChange(of: deletePopup) { _ in
                    if deletePopup {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onChange(of: deleteConfirm) { _ in
                    if deleteConfirm {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    }
                }
                .animation(.default, value: deletePopup)
                .simultaneousGesture(
                    DragGesture()
                        .updating($isDragging, body: { _, state, _ in
                            state = true
                        })
                        .onChanged { value in
                            if value.translation.width < 0 {
                                offset = value.translation.width
                            }
                        }.onEnded { _ in
                            if deleteConfirm {
                                let reference = LedgerReference(budget)
                                dataController.submitMutation({
                                    try await dataController.deleteBudget(reference)
                                }, success: {
                                    deleted = true
                                    offset = 0
                                }, failure: { error in
                                    offset = 0
                                    MutationPresentation.show(error)
                                })

                            } else if deletePopup {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    offset = 0
                                }

                                toDelete = budget
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    offset = 0
                                }
                            }
                        }
                )
                .onChange(of: isDragging) { _ in
                    if !isDragging && !deleted {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                        }
                    }
                }
            } else {
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 0.5) {
                            HStack(spacing: 4) {
                                Text(budget.wrappedEmoji)
                                    .font(.system(.caption, design: .rounded))
//                                    .font(.system(size: 11.5))

                                Text(budget.wrappedName)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundColor(Color.PrimaryText)
                            }

                            Text(timeLeft)
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
//                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 30)

                    HStack {
                        VStack(alignment: .leading, spacing: -2) {
                            if totalSpent < budgetAmount {
                                Text("\(percentString1) SPENT")
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
//                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundColor(BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount) > 1 ? Color("BudgetRed") : Color.IncomeGreen)
                                    .padding(.bottom, 5)
                            }

                            BudgetDollarView(amount: difference, red: totalSpent >= budgetAmount, scale: 2, size: width - 40)

                            Text(budgetAmount >= totalSpent
                                 ? String(localized: "left \(budgetType)")
                                 : String(localized: "over \(budgetType)"))
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                                .foregroundColor(Color.SubtitleText)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                .fill(Color.SecondaryBackground)
                                .frame(width: proxy.size.width)

                            if BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount) < 0.98 {
                                if let category = budget.category {
                                    AnimatedHorizontalBarGraphBudget(category: category)
                                        .frame(width: proxy.size.width * (1 - BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount)))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .topLeading) {
                            if budget.type != 1 && totalSpent < budgetAmount && targetPercent > 0 && targetPercent < 0.95 {
                                RoundedTriangle(cornerRadius: 1.3)
                                    .fill((targetPercent * budgetAmount) <= (budgetAmount - totalSpent) ? Color.DarkBackground : Color.BudgetRed)
                                    .frame(width: 14, height: 6.5)
                                    .offset(x: (targetPercent * proxy.size.width) - 7, y: -3.5)
                            }
                        }
                    }
                    .frame(height: 17.5)
                }
                .padding(15)
                .frame(width: width + 30)
                .background(colorScheme == .dark ? Color.Outline.opacity(0.2) : Color.Outline.opacity(0.35), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 13))
                .contextMenu {
                    Button {
                        toEdit = budget

                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        toDelete = budget
                    } label: {
                        Label("Delete", systemImage: "xmark.bin")
                    }
                }
            }
        }
    }

    init(budget: Budget, toDelete: Binding<Budget?>?, toEdit: Binding<Budget?>?, budgetRows: Bool, snapshot: BudgetReadSnapshot?) {
        self.budget = budget
        self.budgetRows = budgetRows
        _toDelete = toDelete ?? Binding.constant(nil)
        _toEdit = toEdit ?? Binding.constant(nil)

        self.snapshot = snapshot
    }
}
