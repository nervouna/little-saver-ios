//
//  ColourPickerView.swift
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

struct ColourPickerView: View {
    var selectedColours: [String]

    @Binding var showMenu: Bool
    @Binding var selectedColour: String

    @Binding var showNativePicker: Bool

    @State var customMode: Bool = false
    @State var customSelectedColor = Color.white

    @State var testing = false
    let columns = [
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40))
    ]

    @AppStorage("colourScheme", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Color.colorArray, id: \.self) { suggestedColor in
                if suggestedColor == "#" {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .pink]), center: .center))

                        RoundedRectangle(cornerRadius: 6)
                            .fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground"))
                            .padding(4)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(customSelectedColor)
                            .padding(8)

                        if customMode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(customSelectedColor.luminance() > 0.5 ? Color.black : Color.white)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color.black)
                        }
                    }
                    .frame(width: 40, height: 40, alignment: .center)
                    .onTapGesture {
                        showMenu = false
                        showNativePicker = true
                    }
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: suggestedColor))
                        .frame(height: 40)
                        .opacity(selectedColours.contains(suggestedColor) ? 0.2 : 1)
                        .onTapGesture {
                            if !selectedColours.contains(suggestedColor) {
                                withAnimation {
                                    selectedColour = suggestedColor
                                    customMode = false
                                    showMenu = false
                                }
                            }
                        }
                        .overlay {
                            if selectedColour == suggestedColor && !customMode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color.black)
                            }
                        }
                }
            }
        }
        .padding(6)
        .frame(width: 282)
        .background(RoundedRectangle(cornerRadius: 9).fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground")).shadow(color: darkMode ? Color.clear : Color.gray.opacity(0.25), radius: 6))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(darkMode ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
    }

    init(selectedColor: Binding<String>, showMenu: Binding<Bool>, showNativePicker: Binding<Bool>, toEdit: Category? = nil) {
        _selectedColour = selectedColor
        _showMenu = showMenu
        _showNativePicker = showNativePicker

        if !Color.colorArray.contains(selectedColor.wrappedValue) {
            _customMode = State(initialValue: true)
            _customSelectedColor = State(initialValue: Color(hex: selectedColor.wrappedValue))
        }

        var selectedColours = [String]()

        let dataController = DataController.platformShared

        let categories = dataController.getAllCategories(income: false)

        categories.forEach { category in
            selectedColours.append(category.wrappedColour)
        }

        if let editted = toEdit {
            if !selectedColours.isEmpty {
                selectedColours.remove(at: selectedColours.firstIndex(of: editted.wrappedColour) ?? 0)
            }
        }

        self.selectedColours = selectedColours
    }
}
