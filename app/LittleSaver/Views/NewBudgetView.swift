//
//  NewBudgetView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 15/7/23.
//

import LittleSaverCore
import SwiftUI

struct PickerStyle: ViewModifier {
    var colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.PrimaryBackground).shadow(color: colorScheme == .light ? Color.Outline : Color.clear, radius: 6))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(colorScheme == .light ? Color.clear : Color.Outline.opacity(0.4), lineWidth: 1.3))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
    }
}

struct InstructionHeadings {
    let title: String
    let subtitle: String
}

struct BrandNewBudgetView: View {
    @FetchRequest private var categories: FetchedResults<Category>

    @AppStorage("firstWeekday", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var firstWeekday: Int = 1
    @AppStorage("firstDayOfMonth", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var firstDayOfMonth: Int = 1

    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    @Environment(\.dismiss) var dismiss

    @Environment(\.colorScheme) var colorScheme

    @State var progress = 1
    var initialProgress: Double

    @State var showToast: Bool = false
    @State var toastMessage: String = String(localized: "Missing Category")

    // stage one (ignore if editing), overall budget or category budget
    @State var categoryBudget: Bool = false
    var overallBudgetCreated: Bool

    // stage two (ignore if overall budget or editing)
    @State var selectedCategory: Category?
    @State var showingCategoryView = false

    // stage 3
    @State var budgetTimeFrame = BudgetTimeFrame.week

    // stage 4
    @State var chosenDayWeek = 1
    @State var chosenDayMonth = 1
    @State var chosenDayYear = Date.now

    let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var timeFrameString: String {
        switch budgetTimeFrame {
        case .day:
            return String(localized: "day")
        case .week:
            return String(localized: "weekNewBudget")
        case .month:
            return String(localized: "monthNewBudget")
        case .year:
            return String(localized: "yearNewBudget")
        }
    }

    var oneYearAgo: Date {
        return Calendar.current.date(byAdding: .year, value: -1, to: Date.now)!
    }

    // stage 5
//    var budgetAmount: Double {
//        return (amount as NSString).doubleValue
//    }

    @AppStorage("numberEntryType", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var numberEntryType: Int = 1

    @State private var price: Double = 0
    @State private var category: Category?
    @State var isEditingDecimal = false
    @State var decimalValuesAssigned: AssignedDecimal = .none
    @State private var priceString: String = "0"

    @AppStorage("currency", store: UserDefaults(suiteName: AppIdentifiers.appGroup)) var currency: String = (Locale.current.currencyCode ?? "USD")
    var currencySymbol: String {
        return (Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency)
    }

    var amountPerDayString: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = currency

        let average: Double

        if budgetTimeFrame == .week {
            average = price / 7
        } else if budgetTimeFrame == .month {
            average = price / 30
        } else {
            average = price / 365
        }

        numberFormatter.maximumFractionDigits = 0

        let amount = numberFormatter.string(from: NSNumber(value: average)) ?? "0"
        return String(localized: "About \(amount) per day")
    }

    // height of pickers

    var heightOfPicker: CGFloat {
        return (("Sunday".heightOfRoundedString(size: UIFont.textStyleSize(.title3), weight: .medium) + 16) * 5) + 10
    }

    // editMode
    let toEditBudget: Budget?
    let toEditMainBudget: MainBudget?
    var editMode: Bool {
        toEditBudget != nil || toEditMainBudget != nil
    }

    @Namespace var animation

    var labelHeight: CGFloat {
        progress == 5 ? 130 : 170
    }

    var showBackButton: Bool {
        canGoBack(from: progress)
    }

    func canGoBack(from step: Int) -> Bool {
        step > Int(initialProgress)
    }

    var instructions: [InstructionHeadings] {
        [
            InstructionHeadings(title: String(localized: "Indicate budget type"), subtitle: String(localized: "The overall budget tracks all expenses, while a category budget only tracks expenses in one category.")),
            InstructionHeadings(title: String(localized: "Select a category"), subtitle: String(localized: "Begin by linking this budget to an existing category.")),
            InstructionHeadings(title: String(localized: "Choose a time frame"), subtitle: String(localized: "The budget will periodically refresh according to your preference.")),
            InstructionHeadings(title: String(localized: "Pick a start date"), subtitle: String(localized: "Which day of the \(timeFrameString) do you want your budget to start from?")),
            InstructionHeadings(title: String(localized: "Set budget amount"), subtitle: String(localized: "Try to stay under this limit. You can change it later."))
        ]
    }

    var body: some View { content.modifier(MutationPendingModifier()) }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            HStack {
                if #available(iOS 17.0, *) {
                    Button {
                        if showBackButton {
                            withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
                                if progress == 3 && !categoryBudget && !editMode {
                                    progress -= 2
                                } else if progress == 5 && budgetTimeFrame == .day {
                                    progress -= 2
                                } else if progress > 1 {
                                    progress -= 1
                                }
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: showBackButton ? "chevron.left" : "xmark")
                            .font(.system(.callout, design: .rounded).weight(.semibold))

                            .foregroundColor(Color.SubtitleText)
                            .padding(8)
                            .background(Color.SecondaryBackground, in: Circle())
                    }
                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol))
                } else {
                    Button {
                        if showBackButton {
                            withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
                                if progress == 3 && !categoryBudget && !editMode {
                                    progress -= 2
                                } else if progress == 5 && budgetTimeFrame == .day {
                                    progress -= 2
                                } else if progress > 1 {
                                    progress -= 1
                                }
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: showBackButton ? "chevron.left" : "xmark")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(8)
                            .background(Color.SecondaryBackground, in: Circle())
                    }
                }

                Spacer()

                CustomCapsuleProgress(percent: (Double(progress) - initialProgress + 1) / (6 - initialProgress), width: 4, topStroke: Color.DarkBackground, bottomStroke: Color.SecondaryBackground)
                    .frame(width: 60)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if showToast {
                    HStack(spacing: 6.5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.AlertRed)

                        Text(toastMessage)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.AlertRed)
                    }
                    .padding(8)
                    .background(Color.AlertRed.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                    .frame(width: 250)
                }
            }
            .padding(.bottom, 50)
            .animation(.easeInOut, value: showBackButton)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(instructions[progress - 1].title)
                        .foregroundColor(.PrimaryText)
                        .font(.system(.title2, design: .rounded).weight(.semibold))

                    if progress == 2 {
                        Button {
                            showingCategoryView = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                                .foregroundColor(Color.SubtitleText)
                                .padding(4)
                                .background(Color.SecondaryBackground, in: Circle())
                                .contentShape(Circle())
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                Text(instructions[progress - 1].subtitle)
                    .foregroundColor(.SubtitleText)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: labelHeight, alignment: .top)

            if progress == 1 {
                VStack {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Overall Budget")
                            Spacer()

                            if !categoryBudget {
                                Checkmark()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(Color.PrimaryText)
                        .font(.system(.title3, design: .rounded).weight(.medium))
//                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .padding(8)
                        .background {
                            if !categoryBudget {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.SecondaryBackground)
                                    .matchedGeometryEffect(id: "TAB1", in: animation)
                            }
                        }
//                        .frame(height: 40)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.15)) {
                                categoryBudget = false
                            }
                        }

                        HStack {
                            Text("Category Budget")
                            Spacer()

                            if categoryBudget {
                                Checkmark()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(Color.PrimaryText)
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .padding(8)
//                        .frame(height: 40)
                        .background {
                            if categoryBudget {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.SecondaryBackground)
                                    .matchedGeometryEffect(id: "TAB1", in: animation)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeIn(duration: 0.15)) {
                                categoryBudget = true
                            }
                        }
                    }
                    .modifier(PickerStyle(colorScheme: colorScheme))

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if progress == 2 {
                VStack {
                    if categories.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(.largeTitle, design: .rounded))
//                                .font(.system(size: 38, weight: .regular, design: .rounded))
                                .foregroundColor(Color.SubtitleText.opacity(0.7))
                                .padding(.top, 20)

                            Text("No remaining\ncategories.")
                                .font(.system(.title3, design: .rounded).weight(.medium))
//                                .font(.system(size: 21, weight: .medium, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundColor(Color.SubtitleText.opacity(0.7))
                                .padding(.bottom, 20)

                            Spacer()
                        }
                        .frame(maxHeight: .infinity)

                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 10) {
                                ForEach(getRows(), id: \.self) { rows in

                                    HStack(spacing: 10) {
                                        ForEach(rows) { row in

                                            // Row View....
                                            RowView(category: row)
                                        }
                                    }
                                }
                            }
                            .padding(15)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 15)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if progress == 3 {
                VStack {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(BudgetTimeFrame.allCases, id: \.self) { time in
                            HStack {
                                Text(LocalizedStringKey(time.rawValue))
                                Spacer()

                                if time == budgetTimeFrame {
                                    Checkmark()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(Color.PrimaryText)
                            .font(.system(.title3, design: .rounded).weight(.medium))
//                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .padding(8)
//                            .frame(height: 40)
                            .background {
                                if time == budgetTimeFrame {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.SecondaryBackground)
                                        .matchedGeometryEffect(id: "TAB2", in: animation)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeIn(duration: 0.15)) {
                                    budgetTimeFrame = time
                                }
                            }
                        }
                    }
                    .modifier(PickerStyle(colorScheme: colorScheme))

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if progress == 4 {
                VStack {
                    switch budgetTimeFrame {
                    case .day:
                        EmptyView()
                    case .week:
                        ScrollView(showsIndicators: false) {
                            ScrollViewReader { value in
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(weekdays, id: \.self) { day in
                                        HStack {
                                            Text(LocalizedStringKey(day))
                                            Spacer()

                                            if chosenDayWeek == (weekdays.firstIndex(of: day)! + 1) {
                                                Checkmark()
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(Color.PrimaryText)
                                        .font(.system(.title3, design: .rounded).weight(.medium))
//                                        .font(.system(size: 20, weight: .medium, design: .rounded))
                                        .padding(8)
//                                        .frame(height: 40)
                                        .background {
                                            if chosenDayWeek == (weekdays.firstIndex(of: day)! + 1) {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.SecondaryBackground)
//                                                    .matchedGeometryEffect(id: "TAB3", in: animation)
                                            }
                                        }
                                        .id(weekdays.firstIndex(of: day)! + 1)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.easeIn(duration: 0.15)) {
                                                chosenDayWeek = (weekdays.firstIndex(of: day)! + 1)
                                            }
                                        }
                                    }
                                }
                                .onAppear {
                                    value.scrollTo(chosenDayWeek)
                                }
                            }
                        }
                        .modifier(PickerStyle(colorScheme: colorScheme))
                        .frame(height: min(heightOfPicker, 250))
                    case .month:
                        ScrollView(showsIndicators: false) {
                            ScrollViewReader { value in
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(1 ..< 29) { day in
                                        HStack {
                                            if Int(day) == 1 {
                                                Text("Start of month")
                                            } else {
                                                Text(String.localizedStringWithFormat(
                                                    NSLocalizedString("%lld of month", comment: "Budget start day within month"),
                                                    Int64(day)
                                                ))
                                            }

                                            Spacer()

                                            if chosenDayMonth == day {
                                                Checkmark()
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(Color.PrimaryText)
                                        .font(.system(.title3, design: .rounded).weight(.medium))
                                        .padding(8)
                                        .background {
                                            if chosenDayMonth == day {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.SecondaryBackground)
//                                                    .matchedGeometryEffect(id: "TAB3", in: animation)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .id(day)
                                        .onTapGesture {
                                            withAnimation(.easeIn(duration: 0.15)) {
                                                chosenDayMonth = day
                                            }
                                        }
                                    }
                                }
                                .onAppear {
                                    value.scrollTo(chosenDayMonth)
                                }
                            }
                        }
                        .modifier(PickerStyle(colorScheme: colorScheme))
                        .frame(height: min(heightOfPicker, 250))
                    case .year:
                        // in: oneYearAgo...Date.now,
                        DatePicker("Date", selection: $chosenDayYear, in: oneYearAgo ... Date.now, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(Color.AlertRed)
                            .padding(.horizontal, 5)
                            .modifier(PickerStyle(colorScheme: colorScheme))
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if progress == 5 {
                VStack(spacing: 10) {
                    NumberPadTextView(
                      price: $price,
                      isEditingDecimal: $isEditingDecimal,
                      decimalValuesAssigned: $decimalValuesAssigned
                    )

                    if budgetTimeFrame != .day && price > 0 {
                        Text(amountPerDayString)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
//                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.SubtitleText)
                            .padding(4)
                            .padding(.horizontal, 7)
                            .background(Color.SecondaryBackground, in: Capsule())
                    }

                    Spacer()

                    NumberPad(
                      price: $price,
                      category: $category,
                      isEditingDecimal: $isEditingDecimal,
                      decimalValuesAssigned: $decimalValuesAssigned
                    ) {
                      submit()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if progress < 5 {
                Button {
                    if progress == 2 && selectedCategory == nil {
                        showToast = true
                        toastMessage = String(localized: "Missing Category")
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        return
                    }

                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.8)) {
                        if progress < 5 {
                            if progress == 1 {
                                if categoryBudget {
                                    progress += 1
                                } else {
                                    progress += 2
                                }
                            } else if progress == 3 {
                                if budgetTimeFrame == .day {
                                    progress += 2
                                } else {
                                    progress += 1
                                }
                            } else {
                                progress += 1
                            }
                        }
                    }
                } label: {
                    Text("Continue")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
//                        .font(.system(size: 19, weight: .semibold, design: .rounded))

                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .foregroundColor((selectedCategory == nil && progress == 2) ? Color.SubtitleText : Color.LightIcon)
                        .background((selectedCategory == nil && progress == 2) ? Color.clear : Color.DarkBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            if selectedCategory == nil && progress == 2 {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(Color.Outline, lineWidth: 1.3)
                            }
                        }
                }
                .buttonStyle(BouncyButton(duration: 0.2, scale: 0.8))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Color.PrimaryBackground)
        .sheet(isPresented: $showingCategoryView) {
            if #available(iOS 16.0, *) {
                NewCategoryAlert(income: Binding.constant(false), bottomSpacers: false, budgetMode: true)
                    .presentationDetents([.height(270)])
            } else {
                NewCategoryAlert(income: Binding.constant(false), bottomSpacers: true, budgetMode: true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
    }

    @ViewBuilder
    func Checkmark() -> some View {
        Image(systemName: "checkmark")
            .font(.system(.callout, design: .rounded).weight(.medium))
    }

    func submit() {
        if price == 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            showToast = true
            toastMessage = String(localized: "Missing Amount")
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let budgetType = getBudgetTypeInteger(budgetTimeFrame)
        let today = Calendar.current.startOfDay(for: Date.now)
        var startDate: Date

        switch budgetTimeFrame {
        case .day:
            startDate = today
        case .week:
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = 1
            calendar.minimumDaysInFirstWeek = 4

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: today)

            let sunday = calendar.date(from: dateComponents)!

            let holdingDate = calendar.date(byAdding: .day, value: chosenDayWeek - 1, to: sunday)!

            if holdingDate > today {
                let newHoldingDate = calendar.date(byAdding: .day, value: -7, to: holdingDate)!

                startDate = newHoldingDate
            } else {
                startDate = holdingDate
            }
        case .month:
            guard let anchor = LedgerCalendar.monthlyScheduleAnchor(day: chosenDayMonth, onOrBefore: today) else {
                MutationPresentation.show(LedgerCommandError.invalidInput)
                return
            }
            startDate = anchor
        case .year:
            startDate = Calendar.current.startOfDay(for: chosenDayYear)
        }

        startDate = retainedScheduleAnchor(proposed: startDate)

        let category = selectedCategory
        let amount = price
        let type = Int16(budgetType)
        let isCategoryBudget = toEditBudget != nil || (toEditMainBudget == nil && categoryBudget)
        dataController.submitMutation({
            if isCategoryBudget {
                try await saveCategoryBudget(using: dataController, category: category, amount: amount, proposedStart: startDate)
            } else {
                try await dataController.upsertMainBudget(amount: amount, startDate: startDate, type: type)
            }
        }, success: {
            dismiss()
        })
    }

    // This is the same submission path used after the category repair step.
    @MainActor
    func saveCategoryBudget(using controller: DataController, category: Category?, amount: Double, proposedStart: Date, calendar: Calendar = .current) async throws {
        guard let category else { throw LedgerCommandError.invalidInput }
        try await controller.saveBudget(reference: toEditBudget.map(LedgerReference.init), category: LedgerReference(category), amount: amount, startDate: retainedScheduleAnchor(proposed: proposedStart, calendar: calendar), type: Int16(getBudgetTypeInteger(budgetTimeFrame)))
    }

    func retainedScheduleAnchor(proposed: Date, calendar: Calendar = .current) -> Date {
        let budgetType = getBudgetTypeInteger(budgetTimeFrame)
        let originalAnchor = toEditBudget?.startDate ?? toEditMainBudget?.startDate
        let originalType = toEditBudget?.type ?? toEditMainBudget?.type
        if let originalAnchor, LedgerCalendar.isValid(originalAnchor), originalType == Int16(budgetType) {
            let unchanged = budgetType == 1
                || (budgetType == 2 && calendar.component(.weekday, from: originalAnchor) == chosenDayWeek)
                || (budgetType == 3 && calendar.component(.day, from: originalAnchor) == chosenDayMonth)
                || (budgetType == 4 && calendar.isDate(originalAnchor, inSameDayAs: chosenDayYear))
            if unchanged { return originalAnchor }
        }
        return proposed
    }

    func getRows() -> [[Category]] {
        var rows: [[Category]] = []
        var currentRow: [Category] = []

        var totalWidth: CGFloat = 0

        let screenWidth: CGFloat = UIScreen.main.bounds.width - 50

        categories.forEach { category in

//            let roundedFont = UIFont.rounded(ofSize: UIFont.textStyleSize(.title3), weight: .semibold)
//
//            let attributes = [NSAttributedString.Key.font: roundedFont]
//
//            let size = (category.fullName as NSString).size(withAttributes: attributes)

            let categoryWidth = category.fullName.widthOfRoundedString(size: UIFont.textStyleSize(.title3), weight: .semibold) + 12 + 12 + 10

            totalWidth += categoryWidth

            if totalWidth > screenWidth {
                totalWidth = (!currentRow.isEmpty || rows.isEmpty ? categoryWidth : 0)

                rows.append(currentRow)
                currentRow.removeAll()
                currentRow.append(category)

            } else {
                currentRow.append(category)
            }
        }

        // Safe check...
        // if having any value storing it in rows...
        if !currentRow.isEmpty {
            rows.append(currentRow)
            currentRow.removeAll()
        }

        return rows
    }

    @ViewBuilder
    func RowView(category: Category) -> some View {
        Button {
            if selectedCategory == category {
                selectedCategory = nil
            } else {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 5) {
                Text(category.wrappedEmoji)
                    .font(.system(.subheadline, design: .rounded))
                    .font(.system(size: 15))
                Text(category.wrappedName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
//                    .font(.system(size: 19, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundColor(selectedCategory == category ? Color(hex: category.wrappedColour) : Color.PrimaryText)
            .background(selectedCategory == category ? Color(hex: category.wrappedColour).opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if selectedCategory != category {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.Outline,
                                      style: StrokeStyle(lineWidth: 1.5))
                }
            }
            .opacity(selectedCategory == nil ? 1 : (selectedCategory == category ? 1 : 0.4))
        }
        .buttonStyle(BouncyButton(duration: 0.2, scale: 0.8))
    }

    func getOrdinal(_ number: Int) -> String {
        if number == 1 {
            return String(localized: "Start")
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal

        return formatter.string(from: number as NSNumber)!.replacingOccurrences(of: ".", with: "")
    }

    func getBudgetTypeInteger(_ budget: BudgetTimeFrame) -> Int {
        switch budget {
        case .day:
            return 1
        case .week:
            return 2
        case .month:
            return 3
        case .year:
            return 4
        }
    }

    init(overallBudgetCreated: Bool, toEditBudget: Budget? = nil, toEditMainBudget: MainBudget? = nil, calendar: Calendar = .current, preferredWeekday: Int? = nil, preferredMonthDay: Int? = nil) {
        if let toEditBudget {
            self.overallBudgetCreated = overallBudgetCreated
            let firstStep = toEditBudget.category == nil ? 2 : 3
            _progress = State(initialValue: firstStep)
            _categoryBudget = State(initialValue: true)
            initialProgress = Double(firstStep)
        } else if toEditMainBudget != nil {
            self.overallBudgetCreated = overallBudgetCreated
            _progress = State(initialValue: 3)
            _categoryBudget = State(initialValue: false)
            initialProgress = 3
        } else {
            if overallBudgetCreated {
                self.overallBudgetCreated = true
                _progress = State(initialValue: 2)
                _categoryBudget = State(initialValue: true)
                initialProgress = 2
            } else {
                self.overallBudgetCreated = false
                initialProgress = 1
            }
        }

        self.toEditBudget = toEditBudget
        self.toEditMainBudget = toEditMainBudget

        // Initialize once. Returning from category creation must not reset edits,
        // and category-budget values must not be overwritten by main-budget defaults.
        let preferences = UserDefaults(suiteName: AppIdentifiers.appGroup)
        let type = toEditBudget?.type ?? toEditMainBudget?.type
        let anchor = (toEditBudget?.startDate ?? toEditMainBudget?.startDate).flatMap { LedgerCalendar.isValid($0) ? $0 : nil } ?? Date.now
        let amount = MoneyAmount(toEditBudget?.amount ?? toEditMainBudget?.amount ?? 0)?.value ?? 0
        let defaultWeekday = preferredWeekday ?? preferences?.integer(forKey: "firstWeekday") ?? 1
        let defaultMonthDay = preferredMonthDay ?? preferences?.integer(forKey: "firstDayOfMonth") ?? 1
        _selectedCategory = State(initialValue: toEditBudget?.category)
        _budgetTimeFrame = State(initialValue: type == 1 ? .day : type == 3 ? .month : type == 4 ? .year : .week)
        _chosenDayWeek = State(initialValue: type == 2 ? calendar.component(.weekday, from: anchor) : (1...7).contains(defaultWeekday) ? defaultWeekday : 1)
        _chosenDayMonth = State(initialValue: type == 3 ? calendar.component(.day, from: anchor) : (1...31).contains(defaultMonthDay) ? defaultMonthDay : 1)
        _chosenDayYear = State(initialValue: anchor)
        _price = State(initialValue: amount)
        let editingDecimal = amount.truncatingRemainder(dividingBy: 1) > 0 && preferences?.integer(forKey: "numberEntryType") == 2
        _isEditingDecimal = State(initialValue: editingDecimal)
        _decimalValuesAssigned = State(initialValue: editingDecimal ? .second : .none)

        let budgetPredicate = NSPredicate(format: "%K == nil", #keyPath(Category.budget))
        let incomePredicate = NSPredicate(format: "income = %d", false)

        let andPredicate = NSCompoundPredicate(type: .and, subpredicates: [budgetPredicate, incomePredicate])

//        self.toEdit = toEdit

        _categories = FetchRequest<Category>(sortDescriptors: [
            SortDescriptor(\.order)
        ], predicate: andPredicate)
    }
}

struct RowProgressIndicator: View {
    let count: Double
    @Binding var progress: Int
    let initialProgess: Double

    var body: some View {
//        ZStack(alignment: .leading) {
//            Rectangle()
//                .foregroundColor(Color.SecondaryBackground)
//                .frame(maxWidth: .infinity)
//
//            GeometryReader { proxy in
//                Rectangle()
//                    .foregroundColor(Color.DarkBackground)
//                    .frame(width: proxy.size.width * CGFloat((Double(progress) - initialProgess + 1)/count), height: 5)
//            }
//            .frame(maxWidth: .infinity)
//        }
//        .frame(height: 5)
//        .frame(maxWidth: .infinity)
//        .mask {
//            HStack(spacing: 5) {
//                ForEach(0..<Int(count), id: \.self) { num in
//                    Capsule()
//                        .frame(height: 5)
//                        .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
//                        .onTapGesture {
//                            print("tapped")
//                        }
//
//                }
//            }
//        }
//

        HStack(spacing: 6) {
            ForEach(0 ..< Int(count), id: \.self) { num in
                Capsule()
                    .frame(width: 15, height: 5)
                    .foregroundColor(num == progress - Int(initialProgess) ? Color.DarkBackground : Color.SecondaryBackground)

//                    .transaction { transaction in
//                        transaction.animation = .easeIn.delay(0.2)
//                    }
//                    .onTapGesture {
//                        print("tapped")
//                    }
            }
        }
        .padding(.bottom, 20)
//        .overlay(alignment: .leading) {
//            Capsule()
//                .frame(width: 30, height: 5)
//                .offset(x: CGFloat((progress - Int(initialProgess)) * 11))
//                .foregroundColor(Color.DarkBackground)
//        }
    }
}
