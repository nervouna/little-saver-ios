//
//  DetailedBudgetView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

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
