//
//  RecurringPickerView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 14/5/22.
//

import LittleSaverCore
import Combine
import Foundation
import Popovers
import SwiftUI

struct RecurringPickerView: View {
    @Namespace var animation
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showMenu: Bool

    @Binding var showPicker: Bool

    let stringArray = ["none", "daily", "weekly", "monthly"]
    let stringArray2 = ["", "days", "weeks", "months"]

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
    var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0

    @State var holdingType = 0
    @State var holdingCoefficient = 0

    @AppStorage("colourScheme", store: UserDefaults(suiteName: AppIdentifiers.appGroup))
    var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(stringArray, id: \.self) { string in
                HStack {
                    Text(LocalizedStringKey(string))
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                    Spacer()

                    if repeatType == (stringArray.firstIndex(of: string) ?? 0) && repeatCoefficient == 1 {
                        Image(systemName: "checkmark")
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        //                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                //                .font(.system(size: 18, weight: .medium, design: .rounded))
                .padding(5)
                .background {
                    if repeatType == (stringArray.firstIndex(of: string) ?? 0) && repeatCoefficient == 1 {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                darkMode
                                ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground")
                            )
                            .matchedGeometryEffect(id: "TAB", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if repeatType == (stringArray.firstIndex(of: string) ?? 0) && repeatCoefficient == 1 {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            repeatType = (stringArray.firstIndex(of: string) ?? 0)
                            repeatCoefficient = 1
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showMenu = false
                        }
                    }
                }
            }

            HStack {
                if repeatCoefficient == 1 {
                    Text("custom")
                } else {
                    if repeatType == 1 {
                        Text(String(localized: "\(repeatCoefficient) days"))
                    } else if repeatType == 2 {
                        Text(String(localized: "\(repeatCoefficient) weeks"))
                    } else if repeatType == 3 {
                        Text(String(localized: "\(repeatCoefficient) months"))
                    }
                }

                Spacer()

                if repeatCoefficient > 1 {
                    Image(systemName: "checkmark")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    //                        .font(.system(size: 14, weight: .medium))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(.body, design: .rounded).weight(.medium))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            //            .font(.system(size: 18, weight: .medium, design: .rounded))
            .padding(5)
            .background {
                if repeatCoefficient > 1 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            darkMode
                            ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground")
                        )
                        .matchedGeometryEffect(id: "TAB", in: animation)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if repeatCoefficient == 1 {
                    repeatCoefficient = 2
                    repeatType = 2

                    holdingType = repeatType
                    holdingCoefficient = repeatCoefficient
                }

                withAnimation {
                    showPicker = true
                }
            }
            .onChange(of: showPicker) { newValue in
                // holdingType != repeatType || holdingCoefficient != repeatCoefficient
                if !newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showMenu = false
                    }
                }
            }
        }
        .foregroundColor(darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground"))
        .padding(4)
        .frame(width: 150)
        .background(
            RoundedRectangle(cornerRadius: 9).fill(
                darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground")
            ).shadow(color: darkMode ? Color.clear : Color.gray.opacity(0.25), radius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9).stroke(
                darkMode ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
    }
}

struct CustomRecurringView: View {
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showPicker: Bool

    @Environment(\.colorScheme) var systemColorScheme
    var stringArray: [String] {
        return [
            "", "\(holdingCoefficient) days", "\(holdingCoefficient) weeks",
            "\(holdingCoefficient) months"
        ]
    }

    @Environment(\.dismiss) var dismiss

    @State var holdingType = 0
    @State var holdingCoefficient = 0

    var body: some View {
        VStack(spacing: 35) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    //                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.SubtitleText)
                        .padding(7)
                        .background(Color.SecondaryBackground, in: Circle())
                        .contentShape(Circle())
                }

                Spacer()

                Text("Custom Interval")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                //                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Spacer()

                Button {
                    repeatType = holdingType
                    repeatCoefficient = holdingCoefficient

                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    dismiss()

                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    //                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.IncomeGreen)
                        .padding(7)
                        .background(Color.IncomeGreen.opacity(0.23), in: Circle())
                        .contentShape(Circle())
                }
            }

            HStack(spacing: 10) {
                Text("Repeats every")
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .padding(.trailing, 3)

                VStack {
                    Button {
                        holdingCoefficient += 1
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingCoefficient == 30 ? 0.25 : 1)
                    }
                    .disabled(holdingCoefficient == 30)

                    Text("\(holdingCoefficient)")
                        .font(.system(size: 23, weight: .medium, design: .rounded))
                        .padding(7)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.SecondaryBackground)
                                .frame(width: 40, height: 40)
                        }

                    Button {
                        holdingCoefficient -= 1
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingCoefficient == 2 ? 0.25 : 1)
                    }
                    .disabled(holdingCoefficient == 2)
                }

                VStack {
                    Button {
                        holdingType -= 1
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingType == 1 ? 0.25 : 1)
                    }
                    .disabled(holdingType == 1)

                    Group {
                        if holdingType == 1 {
                            Text("\(holdingCoefficient) days")
                        } else if holdingType == 2 {
                            Text("\(holdingCoefficient) weeks")
                        } else if holdingType == 3 {
                            Text("\(holdingCoefficient) months")
                        }
                    }
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .padding(7)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.SecondaryBackground)
                            .frame(height: 40)
                    }

                    Button {
                        holdingType += 1
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingType == 3 ? 0.25 : 1)
                    }
                    .disabled(holdingType == 3)
                }
            }
            .padding(.bottom, 20)
        }
        .padding(13)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            holdingType = repeatType
            holdingCoefficient = repeatCoefficient
        }
    }
}
