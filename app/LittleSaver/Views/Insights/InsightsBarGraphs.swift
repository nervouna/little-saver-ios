//
//  InsightsBarGraphs.swift
//  LittleSaver
//
//  Created by Rafael Soh on 20/5/22.
//

import LittleSaverCore
import Foundation
import Popovers
import SwiftUI

struct AverageLineView: View {
    var getMax: Double
    var average: Double

//    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true
//    @State var showLine: Bool = false
//    @State var offset: CGFloat

//    var calculatedOffset: CGFloat {
//        return getOffset(maxi: getMax, average: average)
//    }

    var body: some View {
        HStack(spacing: 2) {
            PencilView(text: getAverageText(average: average))

            Line()
                .stroke(Color.SubtitleText, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5]))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
//        .opacity(showLine ? 1 : 0)
        .offset(y: getOffset(maxi: getMax, average: average))
        .opacity((NumericSafety.safeRatio(average, getMax)) < 0.1 || (NumericSafety.safeRatio(average, getMax)) > 0.9 ? 0 : 1)
//        .onAppear {
//            DispatchQueue.main.sync {
//                withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
//                    print(calculatedOffset)
//                    offset = calculatedOffset
//                }
//            }
//        }
//        .onChange(of: showLine) { newValue in
//            if newValue {
//                DispatchQueue.main.asyncAfter(deadline: .now()) {
//                    if !animated {
//                        offset = calculatedOffset
//                    } else {
//                        
//                    }
//                }
//            }
//        }
//        .onChange(of: calculatedOffset) { newValue in
//            print(calculatedOffset)
//            if newValue != 0 {
//                if showLine {
//                    if !animated {
//                        offset = calculatedOffset
//                    } else {
//                        withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
//                            offset = calculatedOffset
//                        }
//                    }
//                }
//            }
//        }

    }
}

struct SingleWeekBarGraphView: View {
    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool


    var daysOfWeek = [Date]()

    var dayDictionary = [Date: Double]()

    var max: Double = 0
    var weekTotal: Double = 0
    var weekAverage: Double = 0
    var actualDays: Int = 0

    var getMax: Double {
        return NumericSafety.graphMaximum(max)
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 8) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)
                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(spacing: 7) {
                    ForEach(daysOfWeek, id: \.self) { day in
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.SecondaryBackground)
                                    .frame(height: barHeight)

                                AnimatedBarGraph(index: daysOfWeek.firstIndex(of: day) ?? 0)
                                    .frame(height: getBarHeight(point: dayDictionary[day] ?? 0, maxi: getMax))
                                    .opacity(selectedDate == nil ? 1 : (selectedDate == day ? 1 : 0.4))
                            }

                            Text(getWeekday(day: day).prefix(1))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color.SubtitleText)
                        }
                        .opacity(day > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(day > Date.now))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == day {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = day
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            // average line
            AverageLineView(getMax: getMax, average: weekAverage)
                .opacity(actualDays <= 1 ? 0 : 1)

        }
    }

    func getWeekday(day: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("EEE")

        return dateFormatter.string(from: day)
    }

    init(week: Date, date: Binding<Date?>?, mode: Binding<Bool>, snapshot: BucketSnapshot) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode

        let loaded = snapshot

        daysOfWeek = loaded.dates
        dayDictionary = loaded.totals
        self.max = loaded.maximum
        weekTotal = loaded.amount
        weekAverage = loaded.average
        actualDays = loaded.nonzeroCount
    }
}

struct SingleMonthBarGraphView: View {
    @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var firstDayOfMonth: Int = 1

    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool

    var daysOfMonth = [Date]()

    var dayDictionary = [Date: Double]()

    var max: Double = 0
    var monthTotal: Double = 0
    var monthAverage: Double = 0
    var actualDays: Int = 0

    var getMax: Double {
        return NumericSafety.graphMaximum(max)
    }

    let numberArray = [1, 8, 15, 22, 29]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 3) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(alignment: .top, spacing: 2) {
                    ForEach(daysOfMonth, id: \.self) { day in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.SecondaryBackground)
                                .frame(height: barHeight)
                                .zIndex(0)

                            AnimatedBarGraph(index: daysOfMonth.firstIndex(of: day) ?? 0)
                                .frame(height: getBarHeight(point: dayDictionary[day] ?? 0, maxi: getMax))
                                .opacity(selectedDate == nil ? 1 : (selectedDate == day ? 1 : 0.4))
                                .zIndex(0)
                                .overlay(alignment: .bottom) {
                                    if numberArray.contains(((daysOfMonth.firstIndex(of: day) ?? -1) + 1)) && firstDayOfMonth == 1 {
                                        Text("\((daysOfMonth.firstIndex(of: day) ?? -1) + 1)")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.SubtitleText)
                                            .frame(width: 20, alignment: .center)
                                            .offset(y: 20)
                                    }
                                }
                        }
                        .padding(.bottom, firstDayOfMonth == 1 ? 22 : 0)
                        .opacity(day > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(day > Date.now))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == day {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = day
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

            }
            .frame(maxWidth: .infinity)

            //                .frame(maxHeight: .infinity)

            // average line

            AverageLineView(getMax: getMax, average: monthAverage)
                .opacity(actualDays <= 1 ? 0 : 1)

        }
    }

    init(month: Date, date: Binding<Date?>?, mode: Binding<Bool>, snapshot: BucketSnapshot) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode

        let loaded = snapshot

        daysOfMonth = loaded.dates
        dayDictionary = loaded.totals
        self.max = loaded.maximum
        monthTotal = loaded.amount
        monthAverage = loaded.average
        actualDays = loaded.nonzeroCount
    }
}

struct SingleYearBarGraphView: View {
    @Binding var selectedDate: Date?
    @Binding var categoryFilterMode: Bool

    var monthsOfYear = [Date]()

    var monthDictionary = [Date: Double]()

    var max: Double = 0

    var getMax: Double {
        return NumericSafety.graphMaximum(max)
    }

    var yearTotal: Double = 0
    var yearAverage: Double = 0
    var actualMonths: Int = 0
    var pastYearTotal: Double = 0

    let numberArray = [1, 4, 7, 10]
    let monthNames: [Int: String] = [1: "Jan", 4: "Apr", 7: "Jul", 10: "Oct"]

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 3) {
                // axes
                VStack(alignment: .leading) {
                    Text(getMaxText(maxi: getMax))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                    Spacer()

                    Text("0")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.SubtitleText)

                }
                .frame(height: barHeight)
                .padding(.trailing, 3)

                // bars
                HStack(alignment: .top, spacing: 4) {
                    ForEach(monthsOfYear, id: \.self) { month in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.SecondaryBackground)
                                .frame(height: barHeight)
                                .zIndex(0)

                            AnimatedBarGraph(index: monthsOfYear.firstIndex(of: month) ?? 0)
                                .frame(height: getBarHeight(point: monthDictionary[month] ?? 0, maxi: getMax))
                                .opacity(selectedDate == nil ? 1 : (selectedDate == month ? 1 : 0.4))
                                .zIndex(0)
                                .overlay(alignment: .bottom) {
                                    if numberArray.contains(((monthsOfYear.firstIndex(of: month) ?? 0) + 1)) {
                                        Text(LocalizedStringKey(monthNames[((monthsOfYear.firstIndex(of: month) ?? 0) + 1)] ?? ""))
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(Color.SubtitleText)
                                            .frame(width: 30)
                                            .offset(y: 20)
                                    }
                                }
                        }
                        .padding(.bottom, 22)
                        .opacity(month > Date.now ? 0.3 : 1)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(!(month > Date.now))
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if selectedDate == month {
                                    selectedDate = nil
                                    categoryFilterMode = false
                                } else {
                                    selectedDate = month
                                    categoryFilterMode = false
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

            }
            .frame(maxWidth: .infinity)

            // average line

            AverageLineView(getMax: getMax, average: yearAverage)
                .opacity(actualMonths <= 1 ? 0 : 1)

        }
    }

    func getMonth(month: Date) -> String {
        let dateFormatter = DateFormatter()

        dateFormatter.setLocalizedDateFormatFromTemplate("M")

        return dateFormatter.string(from: month)
    }

    init(year: Date, date: Binding<Date?>?, mode: Binding<Bool>, snapshot: BucketSnapshot) {
        _selectedDate = date ?? Binding.constant(nil)
        _categoryFilterMode = mode

        let loaded = snapshot

        monthsOfYear = loaded.dates
        monthDictionary = loaded.totals
        self.max = loaded.maximum
        yearTotal = loaded.amount
        yearAverage = loaded.average
        actualMonths = loaded.nonzeroCount
    }
}

struct AnimatedBarGraph: View {
    var index: Int

    @AppStorage("animated", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var animated: Bool = true
    @State var showBar: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.DarkBackground)
                .frame(height: showBar ? nil : 0, alignment: .bottom)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                if !animated {
                    showBar = true
                } else {
                    withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8).delay(Double(index) * 0.1)) {
                        showBar = true
                    }
                }
            }
        }
    }
}
