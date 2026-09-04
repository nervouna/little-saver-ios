//
//  LogSearchView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import LittleSaverCore
import CoreData
import Foundation
import Popovers
import SwiftUI

struct SearchView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @Environment(\.dismiss) var dismiss

    @State var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @State private var focusLifecycle = SearchFocusLifecycle()

    var body: some View {
        let _ = calendarRevision
        VStack(spacing: 18) {
            HStack(spacing: 9) {
                HStack {
                    Image(systemName: "magnifyingglass")
//                        .font(.system(size: 17))
                        .font(.system(.body, design: .rounded).weight(.regular))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(Color.DarkIcon.opacity(0.8))
                        .accessibility(hidden: true)
                    TextField("Search entry by note", text: $searchQuery)
                        .focused($searchFocused)
                        .font(.system(.body, design: .rounded).weight(.regular))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundColor(Color.PrimaryText)

                    if searchQuery != "" {
                        Button {
                            searchQuery = ""
                            if let focus = focusLifecycle.contentChanged() { searchFocused = focus }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(.subheadline, design: .rounded).weight(.regular))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                                .font(.system(size: 15))
                                .foregroundColor(Color.SubtitleText)
                                .background(Color.SecondaryBackground)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    searchFocused = focusLifecycle.end()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .foregroundColor(Color.PrimaryText)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                }
            }
            
            ScrollView {
                if searchQuery == "" {
                    EmptyView()
                } else {
                    FilteredSearchView(searchQuery: searchQuery)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(15)
        .background(Color.PrimaryBackground)
        .onAppear { if let focus = focusLifecycle.appear() { searchFocused = focus } }
        .onDisappear { searchFocused = focusLifecycle.end() }
        .onChange(of: calendarRevision) { _ in
            if let focus = focusLifecycle.contentChanged() { searchFocused = focus }
        }
    }
}

struct FilteredSearchView: View {
    @EnvironmentObject private var controller: DataController
    @AnalyticsInput private var environment
    let searchQuery: String
    var body: some View {
        AnalyticsReadView(key: LedgerListRequest(query: .search(searchQuery), environment: environment), load: controller.ledgerListSnapshot) { snapshot in
        VStack {
            if searchQuery != "" && snapshot.rows.count == 0 {
                VStack(spacing: 2) {
                    Text("📭️")
                        .font(.system(size: 50))
                        .padding(.bottom, 15)
                    Text("No entries found.")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(Color.PrimaryText)
                    Text("Try a different search query!")
                        .font(.system(.subheadline, design: .rounded).weight(.regular))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                }
                .frame(alignment: .center)
                .opacity(0.8)
                .padding(.top, 80)
            }

            ListView(snapshot: snapshot)
        }
        .frame(maxHeight: .infinity)
        }
    }
}
