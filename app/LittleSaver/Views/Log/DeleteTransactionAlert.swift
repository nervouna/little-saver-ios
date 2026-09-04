//
//  DeleteTransactionAlert.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import LittleSaverCore
import CoreData
import Foundation
import Popovers
import SwiftUI

struct DeleteTransactionAlert: View {
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var transactionManager: OverallTransactionManager

    var stopRecurring: Bool {
        if let unwrapped = transactionManager.toDelete {
            return transactionManager.future && unwrapped.wrappedDate < Date.now && unwrapped.recurringType > 0
        } else {
            return false
        }
    }

    @Environment(\.colorScheme) var systemColorScheme

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0

    var body: some View {
        if let unwrappedToDelete = transactionManager.toDelete {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(stopRecurring
                     ? String(localized: "Stop Recurring?")
                     : String(localized: "Delete '\(unwrappedToDelete.wrappedNote)'?"))
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 25, weight: .medium, design: .rounded))
                    .foregroundColor(.PrimaryText)
                    .accessibilityLabel(String(localized: "Delete \(unwrappedToDelete.wrappedNote) transaction confirmation. This action cannot be undone."))

                Text(stopRecurring
                     ? String(localized: "The transaction will no longer be automatically logged.")
                     : String(localized: "This action cannot be undone."))
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.SubtitleText)
                    .padding(.bottom, 25)
                    .accessibility(hidden: true)

                Button {
                    let reference = LedgerReference(unwrappedToDelete)
                    if stopRecurring {
                        dataController.submitMutation({
                            try await dataController.stopRecurringTransaction(reference)
                        }, success: {
                            transactionManager.showPopup = false
                            transactionManager.toDelete = nil
                        })
                    } else {
                        dataController.submitMutation({
                            try await dataController.deleteTransaction(reference)
                        }, success: { snapshot in
                            transactionManager.deletionSnapshot = snapshot
                            transactionManager.showPopup = false
                            transactionManager.toDelete = nil
                            transactionManager.showToast = true
                        })
                    }
                } label: {
                    DeleteButton(text: stopRecurring ? "Confirm" : "Delete", red: true)
                }
                .padding(.bottom, 8)

                Button {
                    transactionManager.showPopup = false
                } label: {
                    DeleteButton(text: "Cancel", red: false)
                }
            }
            .padding(13)
            //            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
//            .offset(y: offset)
//            .gesture(
//                DragGesture()
//                    .onChanged { gesture in
//                        if gesture.translation.height < 0 {
//                            offset = gesture.translation.height / 3
//                        } else {
//                            offset = gesture.translation.height
//                        }
//                    }
//                    .onEnded { value in
//                        if value.translation.height > 20 {
//                            dismiss()
//                        } else {
//                            withAnimation {
//                                offset = 0
//                            }
//
//                        }
//                    }
//            )
            .padding(.horizontal, 17)
            .padding(.bottom, bottomEdge == 0 ? 13 : bottomEdge)
        }
    }
}

struct BackgroundBlurView: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}
}
