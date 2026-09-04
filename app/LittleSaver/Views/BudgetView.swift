//
//  BudgetView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

struct BudgetView: View {
    var request: BudgetNavigationRequest? = nil
    @StateObject private var model = SnapshotModel<AnalyticsEnvironment, BudgetDashboardSnapshot>()
    @State private var navigation = BudgetNavigationState()
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @EnvironmentObject private var controller: DataController
    @Environment(\.ledgerMetadata) private var metadata
    @AnalyticsInput private var environment

    var body: some View {
        AnalyticsResultView(model: model, key: environment, load: controller.budgetDashboardSnapshot) { snapshot in
            content(snapshot)
        }
        .onAppear { resolveRequest() }
        .onChange(of: request?.id) { _ in resolveRequest() }
        .onChange(of: model.isLoading) { loading in if !loading { resolveRequest() } }
        .overlay(alignment: .top) {
            if navigation.unavailable { Text("This budget is unavailable.").padding().background(Color.PrimaryBackground) }
        }
    }

    private func resolveRequest() { navigation.resolve(request, snapshot: model.value(for: environment)) }

    @ViewBuilder private func content(_ snapshot: BudgetDashboardSnapshot) -> some View {
        if metadata?.categories.isEmpty != false && snapshot.budgets.isEmpty && snapshot.main == nil {
            VStack(spacing: 5) {
                Image("category-3")
                    .resizable()
                    .frame(width: 75, height: 75)
                    .padding(.bottom, 20)

                Text("Budget Your Finances")
                    .font(.system(.title2, design: .rounded).weight(.medium))
//                    .font(.system(size: 23.5, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.PrimaryText.opacity(0.8))

                Text("Link budgets to categories and set appropriate expenditure goals")
                    .font(.system(.body, design: .rounded).weight(.medium))
//                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.SubtitleText.opacity(0.7))
            }
            .padding(.horizontal, 30)
            .frame(height: 250, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .background(Color.PrimaryBackground)

        } else {
            ActualBudgetView(snapshot: snapshot, navigation: $navigation)
        }
    }
}

struct ActualBudgetView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @Environment(\.colorScheme) var colorScheme
    @State private var showInfo = false

    let snapshot: BudgetDashboardSnapshot
    @Binding var navigation: BudgetNavigationState
    private var budgets: [Budget] { snapshot.budgets.compactMap { presentationObject($0.id, in: moc) } }
    private var mainBudget: [MainBudget] { snapshot.main.flatMap { presentationObject($0.id, in: moc, as: MainBudget.self) }.map { [$0] } ?? [] }
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var tabBarManager: TabBarManager

    @State var newBudget = false

    @State private var showMenu = false

    @State private var toDelete: Budget?
    @State private var toEdit: Budget?

    let layout = [
        GridItem(.flexible(), spacing: 15),
        GridItem(.flexible(), spacing: 15)
    ]

    @AppStorage("budgetViewStyle", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var budgetRows: Bool = false

    @Namespace var animation


    @State var date = Date.now

    var body: some View {
        let _ = calendarRevision
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text("Budgets")
                        .font(.system(.title, design: .rounded).weight(.semibold))
//                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .accessibility(addTraits: .isHeader)

                    Button {
                        newBudget = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(4)
                            .background(Color.SecondaryBackground, in: Circle())
                            .contentShape(Circle())
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.horizontal, 30)
                .padding(.bottom, 20)

                if !budgets.isEmpty || !mainBudget.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack {
                            if let first = mainBudget.first {
                                Button { navigation.select(first.objectID.uriRepresentation(), isMainBudget: true) } label: {
                                    if budgets.count == 0 {
                                        MainBudgetView(budget: first, solo: true, snapshot: snapshot.byReference[first.objectID.uriRepresentation()])
                                            .padding(.horizontal, 25)
                                            .padding(.bottom, 15)
                                    } else {
                                        MainBudgetView(budget: first, solo: false, snapshot: snapshot.byReference[first.objectID.uriRepresentation()])
                                            .padding(.horizontal, 25)
                                            .padding(.bottom, 15)
                                    }
                                }
                            }

                            if budgetRows {
                                VStack(spacing: 10) {
                                    ForEach(budgets, id: \.self) { budget in
                                        Button { navigation.select(budget.objectID.uriRepresentation()) } label: {
                                            SingleBudgetView(budget: budget, toDelete: $toDelete, toEdit: $toEdit, budgetRows: budgetRows, snapshot: snapshot.byReference[budget.objectID.uriRepresentation()])
                                        }
                                    }
                                }

                            } else {
                                LazyVGrid(columns: layout, spacing: 15) {
                                    ForEach(budgets, id: \.self) { budget in
                                        Button { navigation.select(budget.objectID.uriRepresentation()) } label: {
                                            SingleBudgetView(budget: budget, toDelete: $toDelete, toEdit: $toEdit, budgetRows: budgetRows, snapshot: snapshot.byReference[budget.objectID.uriRepresentation()])
                                        }
                                    }
                                }
                                .padding(.horizontal, 25)
                                .padding(5)
                            }
                        }
                        .padding(.bottom, 70)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 5) {
                        Spacer()
                        Text("🙈")
                            .font(.system(.largeTitle, design: .rounded))
//                            .font(.system(size: 45))
                            .padding(.bottom, 9)

                        Text("No Budgets Found")
                            .font(.system(.title2, design: .rounded).weight(.medium))
//                            .font(.system(size: 23.5, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color.PrimaryText.opacity(0.8))

                        Text("Add your first budget today!")
                            .font(.system(.body, design: .rounded).weight(.medium))
//                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color.SubtitleText.opacity(0.7))

                        Spacer()
                        Spacer()
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .background(Color.PrimaryBackground)
            .background {
                NavigationLink(isActive: Binding(get: { navigation.reference != nil }, set: { if !$0 { navigation.dismiss() } })) {
                    if let reference = navigation.reference {
                        Group {
                            if navigation.isMainBudget, let budget = presentationObject(reference, in: moc, as: MainBudget.self) {
                                DetailedMainBudgetView(budget: budget)
                            } else if !navigation.isMainBudget, let budget = presentationObject(reference, in: moc, as: Budget.self) {
                                DetailedBudgetView(budget: budget)
                            } else { Text("This budget is unavailable.") }
                        }
                        .id(reference)
                        .onAppear { tabBarManager.navigationHideTab() }
                        .onDisappear { tabBarManager.navigationShowTab() }
                    }
                } label: { EmptyView() }
                .hidden()
            }
            .sheet(item: $toEdit, onDismiss: {
                toEdit = nil
            }) { budget in
                BrandNewBudgetView(overallBudgetCreated: !mainBudget.isEmpty, toEditBudget: budget)
            }
            .sheet(isPresented: $newBudget) {
                BrandNewBudgetView(overallBudgetCreated: !mainBudget.isEmpty)
            }
            .fullScreenCover(item: $toDelete, onDismiss: {
                toDelete = nil
            }) { budget in
                DeleteBudgetAlert(toDelete: budget)
            }
        }
    }
}

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

struct AnimatedBudgetBarGraph: View {
    var color: Color
    var percent: Double

    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true
    @State var showBar: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.3))
                    .frame(height: proxy.size.height)

                if percent > 0 {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color.opacity(0.73))
                            .frame(height: showBar ? nil : 0, alignment: .bottom)
                    }
                    .frame(height: proxy.size.height * NumericSafety.clamped(percent, to: 0...1))
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if !animated {
                    showBar = true
                } else {
                    withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
                        showBar = true
                    }
                }
            }
        }
    }
}

struct BudgetDollarView: View {
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    var amount: Double
    var red: Bool
    var scale: Int
    var size: CGFloat

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var dynamicTypeSizes: (symbol: Font.TextStyle, amount: Font.TextStyle) {
        if scale == 1 {
            return (.callout, .title3)
        } else if scale == 2 {
            return (.body, .title2)
        } else {
            return (.title2, .largeTitle)
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1.3) {
            Group {
                Text(currencySymbol)
                    .font(.system(dynamicTypeSizes.symbol, design: .rounded).weight(.medium))
                    .foregroundColor(red ? Color("BudgetRed") : Color.SubtitleText) +

                Text(amount.isFinite ? String(format: showCents && amount < 100 ? "%.2f" : "%.0f", amount) : String(localized: "Amount unavailable"))
                    .font(.system(dynamicTypeSizes.amount, design: .rounded).weight(.medium))
                    .foregroundColor(red ? Color("BudgetRed") : Color.PrimaryText)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}

struct DetailedBudgetDollarView: View {
    var amount: Double
    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1.3) {
            Group {
                Text(currencySymbol)
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText) +

                Text(amount.isFinite ? String(format: showCents && amount < 100 ? "%.2f" : "%.0f", amount) : String(localized: "Amount unavailable"))
                    .font(.system(.largeTitle, design: .rounded).weight(.medium))
                    .foregroundColor(Color.PrimaryText)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}

struct DetailedBudgetDifferenceDollarView: View {
    var amount: Double
    var red: Bool

    @AppStorage("showCents", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showCents: Bool = true

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1.3) {
            Group {
                Text(currencySymbol)
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .foregroundColor(red ? Color("BudgetRed") : Color.SubtitleText) +

                Text(amount.isFinite ? String(format: showCents && amount < 100 ? "%.2f" : "%.0f", amount) : String(localized: "Amount unavailable"))
                    .font(.system(.largeTitle, design: .rounded).weight(.medium))
                    .foregroundColor(red ? Color("BudgetRed") : Color.PrimaryText)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}

struct DeleteBudgetAlert: View {
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    let toDelete: Budget
    @Environment(\.colorScheme) var systemColorScheme

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            VStack(alignment: .leading, spacing: 1.5) {
                Text("Delete the '\(toDelete.category?.wrappedName ?? "")' budget?")
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .foregroundColor(.PrimaryText)

                Text("This action cannot be undone.")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundColor(.SubtitleText)
                    .padding(.bottom, 25)

                Button {
                    let reference = LedgerReference(toDelete)
                    dataController.submitMutation({
                        try await dataController.deleteBudget(reference)
                    }, success: {
                        dismiss()
                        self.presentationMode.wrappedValue.dismiss()
                    })

                } label: {
                    DeleteButton(text: "Delete", red: true)
                }
                .padding(.bottom, 8)

                Button {
                    withAnimation(.easeOut(duration: 0.7)) {
                        dismiss()
                    }

                } label: {
                    DeleteButton(text: "Cancel", red: false)
                }
            }
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
            .offset(y: offset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.height < 0 {
                            offset = gesture.translation.height / 3
                        } else {
                            offset = gesture.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 20 {
                            dismiss()
                        } else {
                            withAnimation {
                                offset = 0
                            }
                        }
                    }
            )
            .padding(.horizontal, 17)
            .padding(.bottom, bottomEdge == 0 ? 13 : bottomEdge)
        }
        .edgesIgnoringSafeArea(.all)
        .background(BackgroundBlurView())
    }
}

struct DeleteMainBudgetAlert: View {
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss
    let toDelete: MainBudget
    @Environment(\.colorScheme) var systemColorScheme

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            VStack(alignment: .leading, spacing: 1.5) {
                Text("Delete your overall budget?")
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .foregroundColor(.PrimaryText)

                Text("This action cannot be undone.")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundColor(.SubtitleText)
                    .padding(.bottom, 25)

                Button {
                    dataController.submitMutation({
                        try await dataController.deleteMainBudget()
                    }, success: { dismiss() })

                } label: {
                    DeleteButton(text: "Delete", red: true)
                }
                .padding(.bottom, 8)

                Button {
                    withAnimation(.easeOut(duration: 0.7)) {
                        dismiss()
                    }

                } label: {
                    DeleteButton(text: "Cancel", red: false)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
            .offset(y: offset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.height < 0 {
                            offset = gesture.translation.height / 3
                        } else {
                            offset = gesture.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 20 {
                            dismiss()
                        } else {
                            withAnimation {
                                offset = 0
                            }
                        }
                    }
            )
            .padding(.horizontal, 17)
            .padding(.bottom, bottomEdge == 0 ? 13 : bottomEdge)
        }
        .edgesIgnoringSafeArea(.all)
        .background(BackgroundBlurView())
    }
}

struct DetailedBudgetView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    let budget: Budget

    @State private var toDelete: Budget?

    @State var newTransaction = false

    @State private var toEdit: Budget?

    var body: some View {
        let _ = calendarRevision
        VStack(spacing: 15) {
            HStack {
                Button {
                    self.presentationMode.wrappedValue.dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)

                        Text("Back")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    .background(Color.SecondaryBackground, in: Capsule())
                }

                Spacer()

                DetailedBudgetViewTopBarButton(imageName: "plus", color: Color("110")) {
                    newTransaction = true
                }

                DetailedBudgetViewTopBarButton(imageName: "pencil", color: Color("6")) {
                    toEdit = budget
                }

                DetailedBudgetViewTopBarButton(imageName: "trash.fill", color: Color.AlertRed) {
                    toDelete = budget
                }
            }
            .padding(.horizontal, 20)

            if budget.currentWindow() != nil {
                TimeBudgetView(budget: budget)
            } else {
                Text("Budget unavailable. Edit this budget to repair its settings.")
                    .padding()
            }
        }
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitle("")
        .navigationBarHidden(true)
        .background(Color.PrimaryBackground)
        .sheet(item: $toEdit, onDismiss: {
            toEdit = nil
        }) { budget in
            BrandNewBudgetView(overallBudgetCreated: false, toEditBudget: budget)
        }
        .fullScreenCover(isPresented: $newTransaction) {
            TransactionView(category: budget.category)
        }
        .fullScreenCover(item: $toDelete, onDismiss: {
            toDelete = nil
        }) { budget in
            DeleteBudgetAlert(toDelete: budget)
        }
    }
}

struct DetailedMainBudgetView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @FetchRequest(sortDescriptors: []) private var mainBudgetCandidates: FetchedResults<MainBudget>
    private let initialBudget: MainBudget
    private var currentBudget: MainBudget? {
        LedgerMaintenance.currentMainBudget(from: Array(mainBudgetCandidates))
    }
    private var budget: MainBudget { currentBudget ?? initialBudget }

    init(budget: MainBudget) { initialBudget = budget }

    @State private var toDelete: MainBudget?

    @State private var toEdit: MainBudget?

    var body: some View {
        let _ = calendarRevision
        VStack(spacing: 15) {
            HStack {
                Button {
                    self.presentationMode.wrappedValue.dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)

                        Text("Back")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
//                    .frame(height: 30, alignment: .center)
                    .background(Color.SecondaryBackground, in: Capsule())
                }

                Spacer()

                DetailedBudgetViewTopBarButton(imageName: "pencil", color: Color("6")) {
                    toEdit = budget
                }

                DetailedBudgetViewTopBarButton(imageName: "trash.fill", color: Color.AlertRed) {
                    toDelete = budget
                }
            }
            .padding(.horizontal, 20)

            if budget.currentWindow() != nil {
                TimeMainBudgetView(budget: budget)
                    .id(budget.objectID)
            } else {
                Text("Budget unavailable. Edit this budget to repair its settings.")
                    .padding()
            }
        }
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitle("")
        .navigationBarHidden(true)
        .background(Color.PrimaryBackground)
        .opacity(currentBudget == nil ? 0 : 1)
        .onChange(of: currentBudget?.objectID) { identity in
            if identity == nil { presentationMode.wrappedValue.dismiss() }
        }
        .onAppear {
            if currentBudget == nil { presentationMode.wrappedValue.dismiss() }
        }
        .fullScreenCover(item: $toEdit, onDismiss: {
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
}

struct TimeBudgetView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    @StateObject private var reads = SnapshotModel<LedgerListRequest, LedgerListSnapshot>()
    let budget: Budget

    var budgetAmount: Double {
        return budget.amount
    }

    var budgetType: Int {
        return Int(budget.type)
    }

    @State private var selectedPeriodIndex: Int?

    var selectedWindow: BudgetWindow? {
        guard let current = budget.currentWindow(now: environment.now, calendar: environment.calendar), let anchor = budget.startDate else { return nil }
        guard let selectedPeriodIndex else { return current }
        return BudgetPeriod(rawValue: budget.type)?.window(anchor: anchor, index: min(selectedPeriodIndex, current.index), calendar: environment.calendar)
    }

    private var startDate: Date {
        get { selectedWindow?.start ?? .distantPast }
        nonmutating set {
            guard let anchor = budget.startDate,
                  let selected = BudgetPeriod(rawValue: budget.type)?.window(anchor: anchor, containing: newValue, calendar: environment.calendar),
                  let current = budget.currentWindow(now: environment.now, calendar: environment.calendar) else { return }
            selectedPeriodIndex = selected.index >= current.index ? nil : selected.index
        }
    }

    var dateString: String {
        guard let window = selectedWindow else { return String(localized: "Date unavailable") }
        return localizedDateInterval(from: window.start, to: window.end.addingTimeInterval(-1))
    }

    private var request: LedgerListRequest {
        LedgerListRequest(query: .interval(start: startDate, end: selectedWindow?.end ?? startDate, income: false, category: budget.category?.objectID.uriRepresentation()), environment: environment)
    }
    private var totalSpent: Double { reads.value(for: request)?.spent ?? .nan }

    var timeLeft: String {
        if budgetType == 1 {
            let hours = NumericSafety.roundedInt(ceil(max(0, (selectedWindow?.end.timeIntervalSince(environment.now) ?? 0)) / 3600))
            return String(localized: "\(hours) hours left")
        }
        return String(localized: "\(daysLeftNumber) days left")
    }

    var subtitleText: String {
        if (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) == startDate {
            return timeLeft
        } else {
            return dateString
        }
    }

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var difference: Double {
        abs(NumericSafety.difference(budgetAmount, totalSpent))
    }

    var differenceSubtitle: String {
        if budgetAmount >= totalSpent {
            if startDate == (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) {
                if budgetType == 1 {
                    return String(localized: "left today")
                } else if budgetType == 2 {
                    return String(localized: "left this week")
                } else if budgetType == 3 {
                    return String(localized: "left this month")
                } else if budgetType == 4 {
                    return String(localized: "left this year")
                } else {
                    return ""
                }
            } else {
                if budgetType == 1 {
                    let dateFormatter = DateFormatter()
                    dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                    return String(localized: "left on \(dateFormatter.string(from: startDate))")
                } else if budgetType == 2 {
                    let components = Calendar.current.dateComponents([.day], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let weekString = String(localized: "\((components.day ?? 0) / 7) weeks ago")
                    return String(localized: "left \(weekString)")
                } else if budgetType == 3 {
                    let components = Calendar.current.dateComponents([.month], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let monthString = String(localized: "\((components.month ?? 0)) months ago")
                    return String(localized: "left \(monthString)")
                } else if budgetType == 4 {
                    let components = Calendar.current.dateComponents([.year], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let yearString = String(localized: "\((components.year ?? 0)) years ago")
                    return String(localized: "left \(yearString)")
                } else {
                    return ""
                }
            }
        } else {
            if startDate == (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) {
                if budgetType == 1 {
                    return String(localized: "over today")
                } else if budgetType == 2 {
                    return String(localized: "over this week")
                } else if budgetType == 3 {
                    return String(localized: "over this month")
                } else if budgetType == 4 {
                    return String(localized: "over this year")
                } else {
                    return ""
                }
            } else {
                if budgetType == 1 {
                    let dateFormatter = DateFormatter()
                    dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                    return String(localized: "over on \(dateFormatter.string(from: startDate))")
                } else if budgetType == 2 {
                    let components = Calendar.current.dateComponents([.day], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let weekString = String(localized: "\((components.day ?? 0) / 7) weeks ago")
                    return String(localized: "over \(weekString)")
                } else if budgetType == 3 {
                    let components = Calendar.current.dateComponents([.month], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let monthString = String(localized: "\((components.month ?? 0)) months ago")
                    return String(localized: "over \(monthString)")
                } else if budgetType == 4 {
                    let components = Calendar.current.dateComponents([.year], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let yearString = String(localized: "\((components.year ?? 0)) years ago")
                    return String(localized: "over \(yearString)")
                } else {
                    return ""
                }
            }
        }
    }

    // for week, month, year only

    var daysLeftNumber: Int { budget.currentWindow(now: environment.now, calendar: environment.calendar)?.daysRemaining(at: environment.now, calendar: environment.calendar) ?? 0 }

    var leftPerDay: Double {
        if budgetType >= 2 {
            return NumericSafety.safeRatio(NumericSafety.difference(budgetAmount, totalSpent), Double(daysLeftNumber))
        } else {
            return 0
        }
    }

    var showExtraDetails: Bool {
        if budgetType >= 2 {
            return (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) == startDate && totalSpent < budgetAmount && daysLeftNumber != 1
        } else {
            return false
        }
    }

    var body: some View {
        AnalyticsResultView(model: reads, key: request, load: controller.ledgerListSnapshot) { snapshot in
            if snapshot.spent.isFinite { content(snapshot) }
            else { Text("Amount unavailable") }
        }
    }

    private func content(_ snapshot: LedgerListSnapshot) -> some View {
        VStack(spacing: 20) {
            // budget name and emoji and time left
            VStack(spacing: 10) {
                HStack(spacing: 7.5) {
                    Text(budget.wrappedEmoji)
                        .font(.system(.subheadline, design: .rounded))
                    Text(budget.wrappedName)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .lineLimit(1)
                }
                .foregroundColor(Color.PrimaryText)

                Text(subtitleText)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.SubtitleText)
                    .padding(4)
                    .padding(.horizontal, 7)
                    .background(Color.SecondaryBackground, in: Capsule())
            }
            .padding(.bottom, 15)

            // amount left and averages

            if budgetType >= 2 {
                HStack(alignment: .top, spacing: 15) {
                    VStack(alignment: showExtraDetails ? .leading : .center, spacing: -4) {
                        DetailedBudgetDifferenceDollarView(amount: difference, red: totalSpent >= budgetAmount)

                        Text(differenceSubtitle)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .frame(maxWidth: .infinity, alignment: showExtraDetails ? .leading : .center)

                    if showExtraDetails {
                        VStack(alignment: .trailing, spacing: -4) {
                            DetailedBudgetDollarView(amount: leftPerDay)

                            Text("left each day")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
//                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 25)
            } else {
                VStack(spacing: -4) {
                    DetailedBudgetDifferenceDollarView(amount: difference, red: totalSpent >= budgetAmount)

                    Text(differenceSubtitle)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
//                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                }
                .padding(.horizontal, 25)
            }

            // bar graph

            VStack(spacing: 5) {
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
                }
                .frame(height: 28)

                HStack {
                    Text("\(currencySymbol)\(totalSpent, specifier: "%.2f")")
                    Spacer()
                    Text("\(currencySymbol)\(budgetAmount, specifier: "%.2f")")
                }
                .frame(maxWidth: .infinity)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Color.SubtitleText)
            }
            .padding(.bottom, budgetType >= 2 ? 20 : 0)
            .padding(.horizontal, 25)

            if budgetType == 1 {
                Divider()
                    .overlay(Color.Outline)
                    .padding(.horizontal, 25)
            }

            if let category = budget.category {
                ScrollView(showsIndicators: false) {
                    ListView(snapshot: snapshot, dayHeaders: budgetType != 1)
                        .padding(.horizontal, 15)
                }
                .frame(maxHeight: .infinity)

                BudgetStepperView(category: category, date: Binding(get: { startDate }, set: { startDate = $0 }), startDate: budget.startDate, budgetType: budgetType)
                    .padding(.horizontal, 25)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct TimeMainBudgetView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    @StateObject private var reads = SnapshotModel<LedgerListRequest, LedgerListSnapshot>()
    let budget: MainBudget

    var budgetAmount: Double {
        return budget.amount
    }

    var budgetType: Int {
        return Int(budget.type)
    }

    @State private var selectedPeriodIndex: Int?

    var selectedWindow: BudgetWindow? {
        guard let current = budget.currentWindow(now: environment.now, calendar: environment.calendar), let anchor = budget.startDate else { return nil }
        guard let selectedPeriodIndex else { return current }
        return BudgetPeriod(rawValue: budget.type)?.window(anchor: anchor, index: min(selectedPeriodIndex, current.index), calendar: environment.calendar)
    }

    private var startDate: Date {
        get { selectedWindow?.start ?? .distantPast }
        nonmutating set {
            guard let anchor = budget.startDate,
                  let selected = BudgetPeriod(rawValue: budget.type)?.window(anchor: anchor, containing: newValue, calendar: environment.calendar),
                  let current = budget.currentWindow(now: environment.now, calendar: environment.calendar) else { return }
            selectedPeriodIndex = selected.index >= current.index ? nil : selected.index
        }
    }

    var dateString: String {
        guard let window = selectedWindow else { return String(localized: "Date unavailable") }
        return localizedDateInterval(from: window.start, to: window.end.addingTimeInterval(-1))
    }

    private var request: LedgerListRequest {
        LedgerListRequest(query: .interval(start: startDate, end: selectedWindow?.end ?? startDate, income: false, category: nil), environment: environment)
    }
    private var totalSpent: Double { reads.value(for: request)?.spent ?? .nan }

    var timeLeft: String {
        if budgetType == 1 {
            let hours = NumericSafety.roundedInt(ceil(max(0, (selectedWindow?.end.timeIntervalSince(environment.now) ?? 0)) / 3600))
            return String(localized: "\(hours) hours left")
        }
        return String(localized: "\(daysLeftNumber) days left")
    }

    var subtitleText: String {
        if (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) == startDate {
            return timeLeft
        } else {
            return dateString
        }
    }

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var difference: Double {
        abs(NumericSafety.difference(budgetAmount, totalSpent))
    }

    var differenceSubtitle: String {
        if budgetAmount >= totalSpent {
            if startDate == (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) {
                if budgetType == 1 {
                    return String(localized: "left today")
                } else if budgetType == 2 {
                    return String(localized: "left this week")
                } else if budgetType == 3 {
                    return String(localized: "left this month")
                } else if budgetType == 4 {
                    return String(localized: "left this year")
                } else {
                    return ""
                }
            } else {
                if budgetType == 1 {
                    let dateFormatter = DateFormatter()
                    dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                    return String(localized: "left on \(dateFormatter.string(from: startDate))")
                } else if budgetType == 2 {
                    let components = Calendar.current.dateComponents([.day], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let weekString = String(localized: "\((components.day ?? 0) / 7) weeks ago")
                    return String(localized: "left \(weekString)")
                } else if budgetType == 3 {
                    let components = Calendar.current.dateComponents([.month], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let monthString = String(localized: "\((components.month ?? 0)) months ago")
                    return String(localized: "left \(monthString)")
                } else if budgetType == 4 {
                    let components = Calendar.current.dateComponents([.year], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let yearString = String(localized: "\((components.year ?? 0)) years ago")
                    return String(localized: "left \(yearString)")
                } else {
                    return ""
                }
            }
        } else {
            if startDate == (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) {
                if budgetType == 1 {
                    return String(localized: "over today")
                } else if budgetType == 2 {
                    return String(localized: "over this week")
                } else if budgetType == 3 {
                    return String(localized: "over this month")
                } else if budgetType == 4 {
                    return String(localized: "over this year")
                } else {
                    return ""
                }
            } else {
                if budgetType == 1 {
                    let dateFormatter = DateFormatter()
                    dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
                    return String(localized: "over on \(dateFormatter.string(from: startDate))")
                } else if budgetType == 2 {
                    let components = Calendar.current.dateComponents([.day], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let weekString = String(localized: "\((components.day ?? 0) / 7) weeks ago")
                    return String(localized: "over \(weekString)")
                } else if budgetType == 3 {
                    let components = Calendar.current.dateComponents([.month], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let monthString = String(localized: "\((components.month ?? 0)) months ago")
                    return String(localized: "over \(monthString)")
                } else if budgetType == 4 {
                    let components = Calendar.current.dateComponents([.year], from: startDate, to: (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast))
                    let yearString = String(localized: "\((components.year ?? 0)) years ago")
                    return String(localized: "over \(yearString)")
                } else {
                    return ""
                }
            }
        }
    }

    // for week, month, year only

    var daysLeftNumber: Int { budget.currentWindow(now: environment.now, calendar: environment.calendar)?.daysRemaining(at: environment.now, calendar: environment.calendar) ?? 0 }

    var leftPerDay: Double {
        if budgetType >= 2 {
            return NumericSafety.safeRatio(NumericSafety.difference(budgetAmount, totalSpent), Double(daysLeftNumber))
        } else {
            return 0
        }
    }

    var showExtraDetails: Bool {
        if budgetType >= 2 {
            return (budget.currentWindow(now: environment.now, calendar: environment.calendar)?.start ?? .distantPast) == startDate && totalSpent < budgetAmount && daysLeftNumber != 1
        } else {
            return false
        }
    }

    var body: some View {
        AnalyticsResultView(model: reads, key: request, load: controller.ledgerListSnapshot) { snapshot in
            if snapshot.spent.isFinite { content(snapshot) }
            else { Text("Amount unavailable") }
        }
    }

    private func content(_ snapshot: LedgerListSnapshot) -> some View {
        VStack(spacing: 20) {
            // budget name and emoji and time left
            VStack(spacing: 10) {
                Text("Overall Budget")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .lineLimit(1)
                    .foregroundColor(Color.PrimaryText)

                Text(subtitleText)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.SubtitleText)
                    .padding(4)
                    .padding(.horizontal, 7)
                    .background(Color.SecondaryBackground, in: Capsule())
            }
            .padding(.bottom, 15)

            // amount left and averages

            if budgetType >= 2 {
                HStack(alignment: .top, spacing: 15) {
                    VStack(alignment: showExtraDetails ? .leading : .center, spacing: -4) {
                        DetailedBudgetDifferenceDollarView(amount: difference, red: totalSpent >= budgetAmount)

                        Text(differenceSubtitle)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .frame(maxWidth: .infinity, alignment: showExtraDetails ? .leading : .center)

                    if showExtraDetails {
                        VStack(alignment: .trailing, spacing: -4) {
                            DetailedBudgetDollarView(amount: leftPerDay)

                            Text("left each day")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundColor(Color.SubtitleText)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 25)
            } else {
                VStack(spacing: -4) {
                    DetailedBudgetDifferenceDollarView(amount: difference, red: totalSpent >= budgetAmount)

                    Text(differenceSubtitle)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                }
                .padding(.horizontal, 25)
            }

            // bar graph

            VStack(spacing: 5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                            .fill(Color.SecondaryBackground)
                            .frame(width: proxy.size.width)

                        if BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount) < 0.98 {
                            AnimatedHorizontalBarGraphMainBudget()
                                .frame(width: proxy.size.width * (1 - BudgetMath.spendingRatio(spent: totalSpent, budgetAmount: budgetAmount)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 28)

                HStack {
                    Text("\(currencySymbol)\(totalSpent, specifier: "%.2f")")
                    Spacer()
                    Text("\(currencySymbol)\(budgetAmount, specifier: "%.2f")")
                }
                .frame(maxWidth: .infinity)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Color.SubtitleText)
            }
            .padding(.bottom, budgetType >= 2 ? 20 : 0)
            .padding(.horizontal, 25)

            if budgetType == 1 {
                Divider()
                    .overlay(Color.Outline)
                    .padding(.horizontal, 25)
            }

            ScrollView(showsIndicators: false) {
                ListView(snapshot: snapshot, dayHeaders: budgetType != 1)
                    .padding(.horizontal, 15)
            }
            .frame(maxHeight: .infinity)

            BudgetStepperView(category: nil, date: Binding(get: { startDate }, set: { startDate = $0 }), startDate: budget.startDate, budgetType: budgetType)
                .padding(.horizontal, 25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct AnimatedHorizontalBarGraphBudget: View {
    let category: Category

    @State var showBar: Bool = false
    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                .foregroundColor(Color(hex: category.wrappedColour))
                .frame(width: showBar ? nil : 0, alignment: .leading)

            Spacer(minLength: 0)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if !animated {
                    showBar = true
                } else {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        showBar = true
                    }
                }
            }
        }
    }
}

struct AnimatedHorizontalBarGraphMainBudget: View {
    @State var showBar: Bool = false
    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                .fill(Color.DarkBackground)
                .frame(width: showBar ? nil : 0, alignment: .leading)

            Spacer(minLength: 0)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if !animated {
                    showBar = true
                } else {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        showBar = true
                    }
                }
            }
        }
    }
}

struct AnimatedCurvedBarGraphBudget: View {
    var spent: Double
    var budgetTotal: Double
    let cornerRadius: Double
    let width: Double
    let color: String
    var percent: Double { 1 - BudgetMath.gaugeRatio(spent: spent, budgetAmount: budgetTotal) }

    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true

    var body: some View {
        DonutSemicircle(percent: percent, cornerRadius: cornerRadius, width: width)
            .fill(Color(color))
            .animation(animated ? .easeInOut(duration: 0.7) : nil, value: percent)
    }
}

struct AnimatedCurvedBarGraphMainBudget: View {
    var spent: Double
    var budgetTotal: Double
    let cornerRadius: Double
    let width: Double

    var percent: Double { 1 - BudgetMath.gaugeRatio(spent: spent, budgetAmount: budgetTotal) }

    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true

    var body: some View {
        DonutSemicircle(percent: percent, cornerRadius: cornerRadius, width: width)
            .fill(Color.DarkBackground)
            .animation(animated ? .easeInOut(duration: 0.7) : nil, value: percent)
    }
}

struct BudgetStepperView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    @StateObject private var boundary = SnapshotModel<TransactionBoundaryRequest, Date?>()
    let categoryReference: URL?
    private var request: TransactionBoundaryRequest { TransactionBoundaryRequest(category: categoryReference, environment: environment) }
    @Binding var date: Date
    let startDate: Date?
    let type: Int

    private var period: BudgetPeriod? { Int16(exactly: type).flatMap(BudgetPeriod.init(rawValue:)) }
    private var selected: BudgetWindow? {
        guard let anchor = startDate else { return nil }
        return period?.window(anchor: anchor, containing: date, calendar: environment.calendar)
    }
    private var latest: BudgetWindow? { period?.currentWindow(anchor: startDate, amount: 1, now: environment.now, calendar: environment.calendar) }
    private var earliestIndex: Int {
        guard let anchor = startDate, let earliest = boundary.value(for: request) ?? nil else { return latest?.index ?? 0 }
        return min(latest?.index ?? 0, period?.window(anchor: anchor, containing: earliest, calendar: environment.calendar)?.index ?? 0)
    }
    private func move(_ delta: Int) {
        guard let anchor = startDate, let selected, let latest else { return }
        let index = min(latest.index, max(earliestIndex, selected.index + delta))
        if let window = period?.window(anchor: anchor, index: index, calendar: environment.calendar) { date = window.start }
    }
    var body: some View {
        VStack(spacing: 8) {
            navigation
            if let error = boundary.error {
                Text(error).font(.caption).multilineTextAlignment(.center)
                Button("Retry") { Task { await boundary.load(key: request, using: controller.earliestTransactionDate) } }
            }
        }
        .task(id: request) { await boundary.load(key: request, using: controller.earliestTransactionDate) }
    }

    private var navigation: some View {
        HStack {
            StepperButtonView(left: true, disabled: (selected?.index ?? 0) <= earliestIndex) { move(-1) }
            Spacer()
            Text(selected.map { localizedDateInterval(from: $0.start, to: $0.end.addingTimeInterval(-1)) } ?? String(localized: "Date unavailable"))
                .font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            StepperButtonView(left: false, disabled: (selected?.index ?? 0) >= (latest?.index ?? 0)) { move(1) }
        }
        .frame(maxWidth: .infinity)
    }
    init(category: Category?, date: Binding<Date>, startDate: Date?, budgetType: Int) {
        categoryReference = category?.objectID.uriRepresentation()
        _date = date
        self.startDate = startDate
        type = budgetType
    }
}
