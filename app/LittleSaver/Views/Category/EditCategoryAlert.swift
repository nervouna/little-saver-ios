//
//  EditCategoryAlert.swift
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

struct EditCategoryAlert: View {
    let toEdit: Category
    @Binding var showRootToast: Bool
    @Binding var rootToastTitle: String
    @Binding var rootToastImage: String
    @Binding var positive: Bool

    let bottomSpacers: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    @Namespace var animation

    // existing categories

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)], predicate: NSPredicate(format: "income = %d", false)) private var expenseCategories: FetchedResults<Category>

    // state
    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var showingColourPicker = false
    @State private var selectedColour: String = "#FFFFFF"

    @FocusState var focusedField: FocusedField?

    enum FocusedField: Hashable {
        case emoji, name
    }

    // toasts
    @State var outcome = CategoryError.none
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    // delete mode
    @State private var deleteMode = false
    @State private var toDelete: Category?
    var alertMessage: String {
        "Delete '" + (toDelete?.wrappedName ?? "") + "'?"
    }

    @State var showNativePicker: Bool = false
    @State var customSelectedColor = Color.white

    var body: some View { content.modifier(MutationPendingModifier()) }

    @ViewBuilder private var content: some View {
        VStack {
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(Color.SecondaryBackground, in: Circle())
                            .contentShape(Circle())
                    }

                    Spacer()

                    if showToast {
                        HStack(spacing: 5) {
                            Image(systemName: toastImage)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.AlertRed)

                            Text(toastTitle)
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .lineLimit(1)
//                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.AlertRed)
                        }
                        .padding(6)
                        .background(Color.AlertRed.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                        .frame(maxWidth: 200)
                    } else {
                        Text(LocalizedStringKey(toEdit.income ? "Income" : "Expense"))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }

                    Spacer()

                    Button {
                        toDelete = toEdit
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.AlertRed)
                            .padding(7)
                            .background(Color.AlertRed.opacity(0.23), in: Circle())
                            .contentShape(Circle())
                    }
                }
                .frame(height: 30)

                Spacer()

                ZStack {
                    EmojiTextField(text: $newEmoji)
                        .focused($focusedField, equals: .emoji)
                        .onReceive(Just(newEmoji), perform: { _ in
                            if String(self.newEmoji.onlyEmoji().suffix(1)) != self.newEmoji.onlyEmoji().prefix(1) {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().suffix(1))
                            } else {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().prefix(1))
                            }
                        })
                        .font(.system(size: 160))
                        .padding(8)
                        .frame(width: 80, height: 80, alignment: .center)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .emoji && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    if newEmoji == "" {
                        Image("emoji-happy")
                            .resizable()
                            .foregroundColor(Color.PrimaryText)
                            .frame(width: 35, height: 35, alignment: .center)
                            .allowsHitTesting(false)
                    }
                }

                Spacer()

                HStack {
                    if !toEdit.income {
                        Button {
                            showingColourPicker = true
                        } label: {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(hex: selectedColour))
                                .padding(8)
                                .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .frame(width: 50, height: 50)
                                .overlay {
                                    if showingColourPicker {
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(Color.SubtitleText, lineWidth: 2.2)
                                    }
                                }
                        }
                        .popover(present: $showingColourPicker, attributes: {
                            $0.position = .absolute(
                                originAnchor: .topLeft,
                                popoverAnchor: .bottomLeft
                            )
                            $0.rubberBandingMode = .none
                            $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
                            $0.presentation.animation = .easeInOut(duration: 0.2)
                            $0.dismissal.animation = .easeInOut(duration: 0.3)
                        }) {
                            ColourPickerView(selectedColor: $selectedColour, showMenu: $showingColourPicker, showNativePicker: $showNativePicker, toEdit: toEdit)
                                .environment(\.managedObjectContext, self.moc)

                        } background: {
                            Color.PrimaryBackground.opacity(0.3)
                        }
                    }

                    NormalTextField(text: $newName, placeholder: "Category Name", action: verification)
                        .focused($focusedField, equals: .name)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .frame(height: 50)
                        .foregroundColor(Color.PrimaryText)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .name && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    Button {
                        verification()
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundColor(Color.LightIcon)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 50, height: 50)
                            .background(Color.DarkBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .padding(13)
            .frame(maxHeight: bottomSpacers ? 350 : .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .fullScreenCover(item: $toDelete, onDismiss: {
            toDelete = nil
        }) { category in
            DeleteCategoryAlert(toDelete: category, deleted: $deleteMode)
        }
        .onChange(of: expenseCategories.count) { _ in
            if expenseCategories.count == 24 {
                dismiss()
            }
        }
        .onChange(of: customSelectedColor) { _ in
            print("changed")
            selectedColour = customSelectedColor.toHex() ?? "#FFFFFF"
        }
        .colorPickerSheet(isPresented: $showNativePicker, selection: $customSelectedColor, supportsAlpha: false, title: "")
        .onChange(of: deleteMode) { _ in
            dismiss()
        }
        .onAppear {
            newName = toEdit.wrappedName
            newEmoji = toEdit.wrappedEmoji
            selectedColour = toEdit.wrappedColour
        }
    }

    func verification() {
        let results = dataController.categoryCheckEdit(name: newName, emoji: newEmoji, toEdit: toEdit)

        outcome = results.error

        if outcome != .none {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            switch outcome {
            case .incomplete:
                toastTitle = String(localized: "Incomplete Entry")
                toastImage = "questionmark.app"
            case .missingEmoji:
                toastTitle = String(localized: "Missing Emoji")
                toastImage = "person.fill"

                focusedField = .emoji
            case .missingName:
                toastTitle = String(localized: "Missing Name")
                toastImage = "character.cursor.ibeam"

                focusedField = .name
            case .duplicate:
                toastTitle = String(localized: "Duplicate Found")
                toastImage = "externaldrive"
            case .duplicateEmoji:
                toastTitle = String(localized: "Duplicate Emoji")
                toastImage = "person.fill"

                focusedField = .emoji
            case .duplicateName:
                toastTitle = String(localized: "Duplicate Name")
                toastImage = "character.cursor.ibeam"

                focusedField = .name
            default:
                return
            }

            showToast = true
        } else {
            let input = CategoryInput(reference: LedgerReference(toEdit), name: newName, emoji: newEmoji, colour: selectedColour, income: toEdit.income)
            dataController.submitMutation({
                try await dataController.saveCategory(input)
            }, success: { _ in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                rootToastTitle = "Edited \(input.name)"
                rootToastImage = "checkmark.circle.fill"
                positive = true
                showRootToast = true
                dismiss()
            })
        }
    }
}
