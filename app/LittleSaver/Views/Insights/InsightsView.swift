//
//  InsightsView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

struct InsightsView: View {
    @Environment(\.ledgerCalendarRevision) private var calendarRevision
    @Environment(\.ledgerMetadata) private var metadata

    @State private var showTimeMenu = false
    @AppStorage("chartTimeFrame", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var chartType = 1

    var chartTypeString: String {
        if chartType == 1 {
            return String(localized: "week")
        } else if chartType == 2 {
            return String(localized: "month")
        } else if chartType == 3 {
            return String(localized: "year")
        } else {
            return ""
        }
    }

    var body: some View {
        let _ = calendarRevision
        if metadata == nil { ProgressView() }
        else if metadata?.hasTransactions != true {
            VStack(spacing: 5) {
                Image("chart")
                    .resizable()
                    .frame(width: 75, height: 75)
                    .padding(.bottom, 20)

                Text("Analyse Your Expenditure")
                    .font(.system(.title2, design: .rounded).weight(.medium))
//                    .font(.system(size: 23.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText.opacity(0.8))
                    .multilineTextAlignment(.center)

                Text("As transactions start piling up")
                    .font(.system(.body, design: .rounded).weight(.medium))
//                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(Color.SubtitleText.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
            .frame(height: 250, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .background(Color.PrimaryBackground)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

        } else {
            VStack(spacing: 5) {
                HStack {
                    Text("Insights")
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .accessibility(addTraits: .isHeader)
                    Spacer()

                    Button {
                        showTimeMenu = true
                    } label: {
                        HStack(spacing: 4.5) {
                            Text(chartTypeString)
                                .font(.system(.body, design: .rounded).weight(.medium))

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                        }
                        .padding(3)
                        .padding(.horizontal, 6)
                        .foregroundColor(Color.PrimaryText.opacity(0.9))
                        .background(Color.Outline, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .popover(present: $showTimeMenu, attributes: {
                        $0.position = .absolute(
                            originAnchor: .bottomRight,
                            popoverAnchor: .topRight
                        )
                        $0.rubberBandingMode = .none
                        $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
                        $0.presentation.animation = .easeInOut(duration: 0.2)
                        $0.dismissal.animation = .easeInOut(duration: 0.3)
                    }) {
                        ChartTimePickerView(showMenu: $showTimeMenu)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)
                .padding(.bottom, 20)

                if chartType == 1 {
                    WeekGraphView()
                } else if chartType == 2 {
                    MonthGraphView()
                } else if chartType == 3 {
                    YearGraphView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.PrimaryBackground)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}
