//
//  InsightsChartChrome.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

func getMaxText(maxi: Double) -> String {
    guard maxi.isFinite else { return "—" }
    return maxi.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
}

struct ChartTimePickerView: View {
    @Namespace var animation
    @State var timeframe = ChartTimeFrame.week
    @Binding var showMenu: Bool

    @AppStorage("colourScheme", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var colourScheme: Int = 0

    @AppStorage("chartTimeFrame", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var chartType = 1

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ChartTimeFrame.allCases, id: \.self) { time in
                HStack {
                    Text(LocalizedStringKey(time.rawValue))
                    Spacer()

                    if time == timeframe {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .padding(5)
                .background {
                    if time == timeframe {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(darkMode ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground"))
                            .matchedGeometryEffect(id: "TAB", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if timeframe == time {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            timeframe = time
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showMenu = false
                        }
                    }
                }
            }
        }
        .foregroundColor(darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground"))
        .padding(4)
        .frame(width: 120)
        .background(RoundedRectangle(cornerRadius: 9).fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground")).shadow(color: darkMode ? Color.clear : Color.gray.opacity(0.25), radius: 6))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(darkMode ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
        .onChange(of: timeframe) { _ in
            if timeframe == .week {
                chartType = 1
            } else if timeframe == .month {
                chartType = 2
            } else if timeframe == .year {
                chartType = 3
            }
        }
        .onAppear {
            if chartType == 1 {
                timeframe = ChartTimeFrame.week
            } else if chartType == 2 {
                timeframe = ChartTimeFrame.month
            } else if chartType == 3 {
                timeframe = ChartTimeFrame.year
            }
        }
    }
}

struct InsightsDollarView: View {
    let amount: Double
    var currencySymbol: String
    var showCents: Bool
    var net: Bool?

    var symbol: String {
        if let netPositive = net {
            if netPositive {
                return "+\(currencySymbol)"
            } else {
                return "-\(currencySymbol)"
            }
        } else {
            return currencySymbol
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1.3) {
            Group {
                Text(symbol)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText) +

                Text(amount.isFinite ? String(format: showCents && amount < 100 ? "%.2f" : "%.0f", amount) : String(localized: "Amount unavailable"))
                    .font(.system(.title, design: .rounded).weight(.medium))
                    .foregroundColor(Color.PrimaryText)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    init(amount: Double, currencySymbol: String, showCents: Bool, net: Bool? = nil) {
        self.amount = amount
        self.currencySymbol = currencySymbol
        self.showCents = showCents
        self.net = net
    }
}

func getAverageText(average: Double) -> String {
    guard average.isFinite else { return "—" }
    return average.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
}

let barHeight = 150.0

func getOffset(maxi: Double, average: Double) -> Double {
    if maxi == 0 {
        return 0
    } else {
        let shiftedAmount = NumericSafety.clamped(NumericSafety.safeRatio(average, maxi), to: 0...1) * (barHeight)
        let height = (barHeight) - (shiftedAmount)
        return height - 10
    }
}

func getBarHeight(point: CGFloat, maxi: Double) -> CGFloat {
    if maxi == 0 {
        return 0
    } else {
        let height = NumericSafety.clamped(NumericSafety.safeRatio(Double(point), maxi), to: 0...1) * barHeight
        return height
    }
}

struct SwipeArrowView: View {
    let left: Bool
    let swipeString: String
    let changeTime: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: left ? "arrow.backward.circle.fill" : "arrow.forward.circle.fill")
                .font(.system(.body, design: .rounded).weight(.medium))
//                                        .font(.system(size: 18, weight: .medium))
                //                                .scaleEffect(changeTime ? 1.3 : 1)
                .foregroundColor(changeTime ? Color.PrimaryText : Color.SecondaryBackground)

            Text(swipeString)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(changeTime ? Color.PrimaryText : Color.SecondaryBackground)
        }
        .drawingGroup()
    }
}

struct SwipeEndView: View {
    let left: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: left ? "eyeglasses" : "sun.haze.fill")
                .font(.system(.title2, design: .rounded).weight(.medium))
//                                        .font(.system(size: 22, weight: .medium))
                .foregroundColor(Color.SubtitleText)

            Text(LocalizedStringKey(left ? "That's all, buddy." : "Into the unknown."))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 90)
                .multilineTextAlignment(.center)
                .foregroundColor(Color.SubtitleText)
        }
        .opacity(0.8)
        .drawingGroup()
    }
}
