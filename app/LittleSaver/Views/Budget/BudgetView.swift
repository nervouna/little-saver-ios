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
