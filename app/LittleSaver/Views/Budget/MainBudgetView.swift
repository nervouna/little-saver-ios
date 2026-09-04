//
//  MainBudgetView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

struct MainBudgetView: View {
    let budget: MainBudget
    let snapshot: BudgetReadSnapshot?

    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    @State var toEdit: MainBudget?
    @State var toDelete: MainBudget?
    var totalSpent: Double { snapshot?.spent ?? .nan }

    var soloBudget: Bool

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

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var percentageOfDays: Double { snapshot?.progress ?? 0 }

    var targetPercent: Double { 1 - (snapshot?.progress ?? 0) }

    var triangleOffset: (x: Double, y: Double) {
        var x = 0.0
        var y = -5.0

        let radius = (width / 2) - 5

        if targetPercent > 0.5 {
            let angle = (CGFloat.pi) * (1 - targetPercent)
            y += (radius - (radius * sin(angle)))
            x += (radius * cos(angle))
        } else if targetPercent < 0.5 {
            let angle = (CGFloat.pi) * targetPercent
            y += (radius - (radius * sin(angle)))
            x -= (radius * cos(angle))
        }

        return (x, y)
    }

    var triangleRotation: Double {
        if targetPercent > 0.5 {
            return ((targetPercent - 0.5) / 0.5) * 90
        } else if targetPercent < 0.5 {
            return -((0.5 - targetPercent) / 0.5) * 90
        } else {
            return 0
        }
    }

    var difference: Double {
        return abs(NumericSafety.difference(budgetAmount, totalSpent))
    }

    var percentString: String { BudgetMath.percentageText(spent: totalSpent, budgetAmount: budgetAmount, remaining: true) }

    var percentString1: String { BudgetMath.percentageText(spent: totalSpent, budgetAmount: budgetAmount, remaining: false) }

    var width: CGFloat {
        if soloBudget {
            return UIScreen.main.bounds.width - 90
        } else {
            return 250
        }
    }

    @Environment(\.colorScheme) var colorScheme

    @ViewBuilder var body: some View {
        if snapshot == nil {
            Text("Budget unavailable. Edit this budget to repair its settings.").padding()
        } else { budgetContent }
    }

    private var budgetContent: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                ZStack {
                    DonutSemicircle(percent: 1, cornerRadius: 6.5, width: soloBudget ? 35 : 25)
                        .fill(Color.SecondaryBackground)
                        .frame(width: width, height: width / 2)

                    if BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount) < 0.97 {
                        AnimatedCurvedBarGraphMainBudget(spent: totalSpent, budgetTotal: budgetAmount, cornerRadius: 6.5, width: soloBudget ? 35 : 25)
                            .frame(width: width, height: width / 2)
                    }
                }
                .overlay(alignment: .top) {
                    if budget.type != 1 && totalSpent < budgetAmount && targetPercent > 0 {
                        RoundedTriangle(cornerRadius: 2)

                            .fill((targetPercent * budgetAmount) < (budgetAmount - totalSpent) ? Color.SubtitleText : Color.BudgetRed)
                            .frame(width: 20, height: 10)
                            .rotationEffect(Angle(degrees: triangleRotation), anchor: .bottom)
                            .offset(x: triangleOffset.x, y: triangleOffset.y)
                    }
                }

                Text("OVERALL SPENT: \(percentString1)")
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)
                    .frame(width: width)
                    .offset(y: 20)

                VStack(spacing: -4) {
                    let internalWidth = soloBudget ? width - 90 : width - 60
                    BudgetDollarView(amount: difference, red: totalSpent >= budgetAmount, scale: 3, size: internalWidth)
                        .frame(width: internalWidth)

                    Text(budgetAmount >= totalSpent
                         ? String(localized: "left \(budgetType)")
                         : String(localized: "over \(budgetType)"))
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
//                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                }
            }

            HStack {
                if totalSpent < 1000 && budgetAmount < 1000 {
                    Text("\(totalSpent, specifier: "%.2f")")
                        .frame(width: 60, alignment: .leading)
                    Spacer()
                    Text("\(budgetAmount, specifier: "%.2f")")
                        .frame(width: 60, alignment: .trailing)
                } else {
                    Text(String(format: "%.0f", totalSpent))
                        .frame(width: 60, alignment: .leading)
                    Spacer()
                    Text(String(format: "%.0f", budgetAmount))
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .font(.system(.caption2, design: .rounded).weight(.medium))
//            .font(.system(size: 10, weight: .medium, design: .rounded))
            .frame(width: width)
            .foregroundColor(Color.SubtitleText)
        }
        .padding(.bottom)
        .frame(width: width + 30, height: soloBudget ? 230 : 200, alignment: .bottom)
        .background(soloBudget ? Color.Outline.opacity(0.2) : Color.PrimaryBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
        .sheet(item: $toEdit, onDismiss: {
            toEdit = nil
        }) { budget in
            BrandNewBudgetView(overallBudgetCreated: true, toEditMainBudget: budget)
        }
        .fullScreenCover(item: $toDelete, onDismiss: {
            toDelete = nil
        }) { budget in
            DeleteMainBudgetAlert(toDelete: budget)
        }
    }

    init(budget: MainBudget, solo: Bool, snapshot: BudgetReadSnapshot?) {
        self.budget = budget
        soloBudget = solo

        self.snapshot = snapshot
    }
}
