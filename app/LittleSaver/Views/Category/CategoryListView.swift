//
//  CategoryListView.swift
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

struct CategoryListView: View {
    @Binding var income: Bool
    var mode: CategoryViewMode

    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var bottomEdge: Double = 15

    @AppStorage("categorySuggestions", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var showSuggestions: Bool = true
    @State var suggestionsToast = false

    @State private var offset: CGFloat = 0

    @FetchRequest private var categories: FetchedResults<Category>

    @State var isEditing = false

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var allCategories: FetchedResults<Category>

    // delete mode
    @State private var deleteMode = false
    @State private var toDelete: Category?
    var alertMessage: String {
        "Delete '" + (toDelete?.wrappedName ?? "") + "'?"
    }

    // edit mode
    @State private var toEdit: Category?

    // toasts
    @Binding var showToast: Bool
    @Binding var toastTitle: String
    @Binding var toastImage: String
    @Binding var positive: Bool

    var toastColor: Color {
        positive ? Color.IncomeGreen : Color.AlertRed
    }

    var sectionHeader: LocalizedStringKey {
        if income {
            return "INCOME CATEGORIES"
        } else {
            return "EXPENSE CATEGORIES"
        }
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        VStack(spacing: 5) {
            if showToast {
                HStack(spacing: 6.5) {
                    Image(systemName: toastImage)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(toastColor)

                    Text(toastTitle)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
//                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(toastColor)
                }
                .padding(8)
                .background(toastColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                .frame(maxWidth: 250)
                .frame(height: 35)
                .padding(20)
            } else {
                if mode == .welcome {
                    HStack(spacing: 8) {
                        if categories.count > 1 {
                            if isEditing {
                                Circle()
                                    .fill(Color.IncomeGreen.opacity(0.23))
                                    .frame(width: 33, height: 33)
                                    .overlay {
                                        Image(systemName: "checkmark")
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Color.IncomeGreen)
                                    }
                                    .onTapGesture {
                                        withAnimation {
                                            isEditing.toggle()
                                        }
                                    }
                            } else {
                                Circle()
                                    .fill(Color.SecondaryBackground)
                                    .frame(width: 33, height: 33)
                                    .overlay {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                            .foregroundColor(Color.SubtitleText)
                                    }
                                    .onTapGesture {
                                        withAnimation {
                                            isEditing.toggle()
                                        }
                                    }
                            }
                        }

                        Circle()
                            .fill(Color.SecondaryBackground)
                            .frame(width: 33, height: 33)
                            .overlay {
                                Image(systemName: showSuggestions ? "eye.slash" : "eye")
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                    .foregroundColor(Color.SubtitleText)
                                    .offset(y: 0.8)
                            }
                            .onTapGesture {
                                withAnimation {
                                    showSuggestions.toggle()
                                }
                            }

                        Spacer()

                        Circle()
                            .fill(!allCategories.isEmpty ? Color.IncomeGreen.opacity(0.23) : Color.clear)
                            .frame(width: 33, height: 33)
                            .overlay {
                                ZStack {
                                    Image(systemName: "arrow.right")
                                        .font(.system(.callout, design: .rounded).weight(.semibold))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(!allCategories.isEmpty ? Color.IncomeGreen : Color.Outline.opacity(0.8))

                                    if allCategories.count == 0 {
                                        Circle()
                                            .stroke(Color.Outline.opacity(0.4), lineWidth: 1.3)
                                            .frame(width: 33, height: 33)
                                    }
                                }
                            }
                            .onTapGesture {
                                if allCategories.count > 0 {
                                    dismiss()
                                }
                            }
                    }
                    .frame(height: 35)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text("Categories")
                            .font(.system(.title3, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 20, weight: .medium, design: .rounded))
                    }
                    .padding(20)

                } else {
                    HStack(spacing: 8) {
                        if mode == .settings {
                            Circle()
                                .fill(Color.SecondaryBackground)
                                .frame(width: 33, height: 33)
                                .overlay {
                                    Image(systemName: "chevron.left")
                                        .font(.system(.body, design: .rounded).weight(.semibold))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(Color.SubtitleText)
                                        .offset(y: 0.8)
                                }
                                .onTapGesture {
                                    self.presentationMode.wrappedValue.dismiss()
                                }
                        } else {
                            Circle()
                                .fill(Color.SecondaryBackground)
                                .frame(width: 33, height: 33)
                                .overlay {
                                    Image(systemName: "chevron.down")
                                        .font(.system(.body, design: .rounded).weight(.semibold))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(Color.SubtitleText)
                                        .offset(y: 0.8)
                                }
                                .onTapGesture {
                                    dismiss()
                                }
                        }

                        Spacer()

                        Circle()
                            .fill(Color.SecondaryBackground)
                            .frame(width: 33, height: 33)
                            .overlay {
                                Image(systemName: showSuggestions ? "eye.slash" : "eye")
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.SubtitleText)
                                    .offset(y: 0.8)
                            }
                            .onTapGesture {
                                withAnimation {
                                    showSuggestions.toggle()
                                }
                            }

                        if categories.count > 1 {
                            if isEditing {
                                Circle()
                                    .fill(Color.IncomeGreen.opacity(0.23))
                                    .frame(width: 33, height: 33)
                                    .overlay {
                                        Image(systemName: "checkmark")
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Color.IncomeGreen)
                                    }
                                    .onTapGesture {
                                        withAnimation {
                                            isEditing.toggle()
                                        }
                                    }
                            } else {
                                Circle()
                                    .fill(Color.SecondaryBackground)
                                    .frame(width: 33, height: 33)
                                    .overlay {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Color.SubtitleText)
                                    }
                                    .onTapGesture {
                                        withAnimation {
                                            isEditing.toggle()
                                        }
                                    }
                            }
                        }
                    }
                    .frame(height: 35)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text("Categories")
                            .font(.system(.title3, design: .rounded).weight(mode == .settings ? .semibold : .medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 20, weight: mode == .settings ? .semibold : .medium, design: .rounded))
                    }
                    .padding(20)
                }
            }

            VStack {
                if #available(iOS 16.0, *) {
                    List {
                        Section(header: Text(sectionHeader).foregroundColor(Color.SubtitleText)) {
                            if categories.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "tray")
                                        .font(.system(.largeTitle, design: .rounded).weight(.light))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                        .font(.system(size: 37, weight: .light))
                                        .foregroundColor(Color.SubtitleText)

                                    Group {
                                        if income {
                                            Text("no_income_categories")
                                        } else {
                                            Text("no_expense_categories")
                                        }
                                    }
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                    .font(.system(size: 17, weight: .medium, design: .rounded))
                                    .italic()
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(Color.SubtitleText)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 37)
                                .listRowBackground(Color.SettingsBackground)
                            } else {
                                ForEach(categories) { category in
                                    HStack(spacing: 10) {
                                        Text(category.wrappedEmoji)
                                            .font(.system(.subheadline, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 15))
                                        Text(category.wrappedName)
                                            .font(.system(.body, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 18.5, weight: .regular, design: .rounded))
                                            .lineLimit(1)
                                            .foregroundColor(toDelete == category ? Color.AlertRed : Color.PrimaryText)

                                        Spacer()

                                        if !income {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(Color(hex: category.wrappedColour))
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    .listRowBackground(Color.SettingsBackground)
                                    .listRowSeparatorTint(Color.Outline)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toEdit = category
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            toDelete = category
                                        } label: {
                                            Image(systemName: "trash.fill")
                                        }
                                        .tint(Color.AlertRed)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            toEdit = category
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .tint(Color("Yellow"))
                                    }
                                }
                                .onMove(perform: moveItem)
                            }

//                                .onDelete(perform: deleteItem)
                        }

                        if showSuggestions {
                            SuggestedCategoriesView(income: income)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))
                } else {
                    List {
                        Section(header: Text(LocalizedStringKey(income ? "INCOME CATEGORIES" : "EXPENSE CATEGORIES")).foregroundColor(Color.SubtitleText)) {
                            if categories.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "tray")
                                        .font(.system(.largeTitle, design: .rounded).weight(.light))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                        .font(.system(size: 37, weight: .light))
                                        .foregroundColor(Color.SubtitleText)

                                    Text(LocalizedStringKey(income ? "no_income_categories" : "no_expense_categories"))
                                        .font(.system(.body, design: .rounded).weight(.medium))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                        .font(.system(size: 17, weight: .medium, design: .rounded))
//                                        .italic()
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(Color.SubtitleText)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 37)
                                .listRowBackground(Color.SettingsBackground)
                            } else {
                                ForEach(categories) { category in
                                    HStack(spacing: 10) {
                                        Text(category.wrappedEmoji)
                                            .font(.system(.subheadline, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 15))
                                        Text(category.wrappedName)
                                            .font(.system(.body, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                            .font(.system(size: 18.5, weight: .regular, design: .rounded))
                                            .lineLimit(1)
                                            .foregroundColor(toDelete == category ? Color.AlertRed : Color.PrimaryText)

                                        Spacer()

                                        if !income {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(Color(hex: category.wrappedColour))
                                                .frame(width: 20, height: 20)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    .listRowBackground(Color.SettingsBackground)
                                    .listRowSeparatorTint(Color.Outline)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toEdit = category
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            toDelete = category
                                        } label: {
                                            Image(systemName: "trash.fill")
                                        }
                                        .tint(Color.AlertRed)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            toEdit = category
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .tint(Color("Yellow"))
                                    }
                                }
                                .onMove(perform: moveItem)
                            }

//                                .onDelete(perform: deleteItem)
                        }

                        if showSuggestions {
                            SuggestedCategoriesView(income: income)
                        }
                    }
                    .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: toDelete) { _ in
            if toDelete != nil {
                deleteMode = true
            }
        }
        .fullScreenCover(isPresented: $deleteMode, onDismiss: {
            toDelete = nil
        }) {
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        deleteMode = false
                    }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text("Delete '\(toDelete?.wrappedName ?? "")'?")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.PrimaryText)

                    Text("This action cannot be undone, and all \(toDelete?.wrappedName ?? "") transactions would be deleted.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.SubtitleText)
                        .padding(.bottom, 15)

                    Button {
                        guard let toDelete else { return }
                        let reference = LedgerReference(toDelete)
                        dataController.submitMutation({
                            try await dataController.deleteCategories([reference])
                        }, success: {
                            self.toDelete = nil
                            deleteMode = false
                        })

                    } label: {
                        Text("Delete")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(height: 45)
                            .frame(maxWidth: .infinity)
                            .background(Color.AlertRed, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .padding(.bottom, 8)

                    Button {
                        withAnimation(.easeOut(duration: 0.7)) {
                            deleteMode = false
                            offset = 0
                        }

                    } label: {
                        Text("Cancel")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.PrimaryText.opacity(0.9))
                            .frame(height: 45)
                            .frame(maxWidth: .infinity)
                            //                        .background(Color("13").opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                                deleteMode = false
                                offset = 0
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
        .sheet(item: $toEdit, onDismiss: {
            toEdit = nil
        }) { category in
            if #available(iOS 16.0, *) {
                EditCategoryAlert(toEdit: category, showRootToast: $showToast, rootToastTitle: $toastTitle, rootToastImage: $toastImage, positive: $positive, bottomSpacers: false)
                    .presentationDetents([.height(270)])
            } else {
                EditCategoryAlert(toEdit: category, showRootToast: $showToast, rootToastTitle: $toastTitle, rootToastImage: $toastImage, positive: $positive, bottomSpacers: true)
            }
        }
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: showSuggestions) { newValue in
            if !newValue {
                toastTitle = String(localized: "Suggestions Hidden")
                toastImage = "eye.slash"
                showToast = true
                positive = true
            }
        }
    }

    private func moveItem(at sets: IndexSet, destination: Int) {
        var references = categories.map(LedgerReference.init)
        references.move(fromOffsets: sets, toOffset: destination)
        let ordered = references
        dataController.submitMutation { try await dataController.reorderCategories(ordered) }
    }

    init(income: Binding<Bool>, mode: CategoryViewMode, showToast: Binding<Bool>, toastTitle: Binding<String>, toastImage: Binding<String>, positive: Binding<Bool>) {
        _categories = FetchRequest<Category>(sortDescriptors: [
            SortDescriptor(\.order)
        ], predicate: NSPredicate(format: "income = %d", income.wrappedValue))

        _income = income
        _showToast = showToast
        _toastTitle = toastTitle
        _toastImage = toastImage
        _positive = positive
        self.mode = mode
    }
}
