//
//  LogFilterPickerView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 19/5/22.
//

import LittleSaverCore
import CoreData
import Foundation
import Popovers
import SwiftUI

struct FilterPickerView: View {
    @Namespace var animation
    @Namespace var animation1
    @Binding var filterType: FilterType
    @Binding var showMenu: Bool

    @AppStorage("colourScheme", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(FilterType.allCases, id: \.self) { filter in
                HStack {
                    Image(systemName: FilterType.imageDictionary[filter] ?? "")
//                        .font(.system(size: 16))
                        .font(.system(.callout, design: .rounded).weight(.regular))
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .frame(width: 20)
                    Text(LocalizedStringKey(filter.rawValue))
//                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .lineLimit(1)
                    Spacer()

                    if filterType == filter {
                        Image(systemName: "checkmark")
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
//                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(5)
                .background {
                    if filterType == filter {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(darkMode ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground"))
                            .matchedGeometryEffect(id: "TAB", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if filterType == filter {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            filterType = filter
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showMenu = false
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
            }
        }
        .foregroundColor(darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground"))
        .padding(4)
        .frame(width: dynamicTypeSize > .xLarge ? 220 : 190)
        .background(RoundedRectangle(cornerRadius: 9).fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground")).shadow(color: darkMode ? Color.clear : Color.gray.opacity(0.25), radius: 6))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(darkMode ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
    }
}
