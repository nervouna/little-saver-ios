//
//  BudgetDollarViews.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

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
