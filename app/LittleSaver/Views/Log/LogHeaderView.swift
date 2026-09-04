//
//  LogHeaderView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import LittleSaverCore
import Popovers
import SwiftUI

struct LogHeaderView: View {
    @Binding var searchMode: Bool
    @Binding var showFilter: Bool
    @Binding var filter: FilterType
    @Binding var categoryFilter: Category?
    var dateFilter: Binding<Date>
    var weekFilter: Binding<Date>
    var monthFilter: Binding<Date>
    @Binding var income: Bool
    var progress: Double
    var topEdge: CGFloat

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    searchMode = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(.title2, design: .rounded).weight(.regular))
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .foregroundColor(Color.DarkIcon)
                        .padding(5)
                        .contentShape(Rectangle())
                        .background {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.SecondaryBackground)
                                .scaleEffect(progress == 1 ? 1.5 : 1.0)
                                .opacity(progress)
                        }
                }
                .accessibilityLabel("Search")

                Spacer()

                switch filter {
                case .all:
                    EmptyView()
                case .category:
                    filterTagView(text: "filter-tag-category")
                case .day:
                    filterTagView(text: "filter-tag-day")
                case .week:
                    filterTagView(text: "filter-tag-week")
                case .month:
                    filterTagView(text: "filter-tag-month")
                case .recurring:
                    filterTagView(text: "filter-tag-recurring")
                case .type:
                    filterTagView(text: "filter-tag-type")
                case .upcoming:
                    filterTagView(text: "filter-tag-upcoming")
                }

                Spacer()

                Button {
                    showFilter = true
                } label: {
                    Image(systemName: filter == .all ? "triangle" : "triangle.tophalf.filled")
                        .font(.system(.title2, design: .rounded).weight(.regular))
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .foregroundColor(Color.DarkIcon)
                        .rotationEffect(Angle(degrees: 180))
                        .padding(5)
                        .contentShape(Rectangle())
                        .background {
                            if showFilter {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.SecondaryBackground)
                            }
                        }
                }
                .accessibilityLabel("Filter")
                .popover(present: $showFilter, attributes: {
                    $0.position = .absolute(
                        originAnchor: .bottomRight,
                        popoverAnchor: .topRight
                    )
                    $0.rubberBandingMode = .none
                    $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
                    $0.presentation.animation = .easeInOut(duration: 0.2)
                    $0.dismissal.animation = .easeInOut(duration: 0.3)
                }) {
                    FilterPickerView(filterType: $filter, showMenu: $showFilter)
                }
            }

            switch filter {
            case .all:
                EmptyView()
            case .category:
                CategoryStepperView(categoryFilter: $categoryFilter)
            case .day:
                DateStepperView(date: dateFilter)
            case .week:
                WeekStepperView(showingDate: weekFilter)
            case .month:
                MonthStepperView(showingDate: monthFilter)
            case .recurring:
                EmptyView()
            case .type:
                IncomeFilterToggleView(income: $income)
            case .upcoming:
                EmptyView()
            }
        }
        .padding(.horizontal, 25)
        .frame(height: (filter == .all || filter == .recurring || filter == .upcoming) ? 50 : 110, alignment: .top)
        .padding(.top, topEdge + 10)
    }

    @ViewBuilder
    func filterTagView(text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(.body, design: .rounded).weight(.medium))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Button {
                withAnimation(.easeIn(duration: 0.15)) {
                    filter = .all
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.caption, design: .rounded).weight(.regular))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundColor(Color.PrimaryText.opacity(0.7))
            }
            .accessibilityLabel("remove filter")
        }
        .padding(4)
        .padding(.horizontal, 6)
        .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .foregroundColor(Color.PrimaryText)
    }
}
