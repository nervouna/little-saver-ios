import Foundation
import XCTest
@testable import LittleSaver

final class LocalizationContractTests: XCTestCase {
    private let supportedLocalizations = ["en", "zh-Hans", "ja"]

    func testLocalizableStringsHaveMatchingNonemptyKeysAndFormatSignatures() throws {
        let tables = try supportedLocalizations.map { locale in
            (locale, try strings(at: appRoot
                .appendingPathComponent("Localizations")
                .appendingPathComponent("\(locale).lproj/Localizable.strings")))
        }
        let referenceKeys = Set(tables[0].1.keys)

        XCTAssertEqual(referenceKeys.count, 486, "Unexpected Localizable.strings baseline key count")
        let englishTable = tables[0].1
        for (locale, table) in tables {
            XCTAssertEqual(Set(table.keys), referenceKeys, "Localizable.strings keys differ for \(locale)")
            for key in referenceKeys {
                let value = try XCTUnwrap(table[key], "Missing \(key) in \(locale)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(key) in \(locale)")
                XCTAssertEqual(formatTokens(in: value), formatTokens(in: englishTable[key] ?? key), "Format signature differs for \(key) in \(locale)")
            }
        }
    }

    func testPluralTablesHaveMatchingKeysAndValidRules() throws {
        let tables = try supportedLocalizations.map { locale in
            (locale, try dictionary(at: appRoot
                .appendingPathComponent("Localizations")
                .appendingPathComponent("\(locale).lproj/Localizable.stringsdict")))
        }
        let referenceKeys = Set(tables[0].1.keys)

        XCTAssertEqual(referenceKeys.count, 8, "Unexpected Localizable.stringsdict baseline key count")
        for (locale, table) in tables {
            XCTAssertEqual(Set(table.keys), referenceKeys, "Localizable.stringsdict keys differ for \(locale)")
            for key in referenceKeys {
                let entry = try XCTUnwrap(table[key] as? [String: Any])
                XCTAssertEqual(entry["NSStringLocalizedFormatKey"] as? String, "%#@VARIABLE@")
                let variable = try XCTUnwrap(entry["VARIABLE"] as? [String: Any])
                XCTAssertEqual(variable["NSStringFormatSpecTypeKey"] as? String, "NSStringPluralRuleType")
                XCTAssertEqual(variable["NSStringFormatValueTypeKey"] as? String, "lld")
                let other = try XCTUnwrap(variable["other"] as? String, "Missing other rule for \(key) in \(locale)")
                XCTAssertFalse(other.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(formatTokens(in: other), ["%lld"], "Unsafe plural format for \(key) in \(locale)")
            }
        }
    }

    func testWidgetConfigurationStringsHaveMatchingNonemptyKeysAndPlaceholders() throws {
        let tables = try supportedLocalizations.map { locale in
            (locale, try strings(at: appRoot
                .appendingPathComponent("LittleSaverWidget")
                .appendingPathComponent("\(locale).lproj/WidgetConfiguration.strings")))
        }
        let referenceKeys = Set(tables[0].1.keys)

        XCTAssertFalse(referenceKeys.isEmpty)
        for (locale, table) in tables {
            XCTAssertEqual(Set(table.keys), referenceKeys, "WidgetConfiguration.strings keys differ for \(locale)")
            for key in referenceKeys {
                let value = try XCTUnwrap(table[key])
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(value.components(separatedBy: "${count}").count, tables[0].1[key]?.components(separatedBy: "${count}").count)
            }
        }
    }

    func testEveryBundleHasTrilingualInfoPlistStrings() throws {
        let bundleDirectories = ["LittleSaver", "LittleSaverWidget", "LittleSaverIntent", "LittleSaverIntentUI"]
        for directory in bundleDirectories {
            let tables = try supportedLocalizations.map { locale in
                try strings(at: appRoot
                    .appendingPathComponent(directory)
                    .appendingPathComponent("\(locale).lproj/InfoPlist.strings"))
            }
            let referenceKeys = Set(tables[0].keys)
            XCTAssertFalse(referenceKeys.isEmpty, "Missing metadata keys for \(directory)")
            for table in tables {
                XCTAssertEqual(Set(table.keys), referenceKeys, "InfoPlist.strings keys differ for \(directory)")
                XCTAssertTrue(table.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }

        let expectedAppNames = [
            "en": "LittleSaver",
            "zh-Hans": "小小存钱罐",
            "ja": "小さな貯金箱",
        ]
        for (locale, expectedName) in expectedAppNames {
            let table = try strings(at: appRoot
                .appendingPathComponent("LittleSaver")
                .appendingPathComponent("\(locale).lproj/InfoPlist.strings"))
            XCTAssertEqual(table["CFBundleDisplayName"], expectedName)
        }
    }

    func testPreferredLocalizationFollowsSupportedSystemLanguagesAndFallsBackToEnglish() {
        XCTAssertEqual(preferredLocalization(for: ["zh-Hans-CN"]), "zh-Hans")
        XCTAssertEqual(preferredLocalization(for: ["ja-JP"]), "ja")
        XCTAssertEqual(preferredLocalization(for: ["en-GB"]), "en")
        XCTAssertEqual(preferredLocalization(for: ["fr-FR"]), "en")
    }

    func testSuggestedCategoriesUseStableLocalizationKeys() throws {
        let expectedExpenseKeys = [
            "Food", "Transport", "Rent", "Subscriptions", "Groceries", "Family",
            "Utilities", "Fashion", "Healthcare", "Pets", "Sneakers", "Gifts",
        ]
        let expectedIncomeKeys = ["Paycheck", "Allowance", "Part-Time", "Investments", "Gifts", "Tips"]

        XCTAssertEqual(SuggestedCategory.expenses.map(\.localizationKey), expectedExpenseKeys)
        XCTAssertEqual(SuggestedCategory.incomes.map(\.localizationKey), expectedIncomeKeys)
        XCTAssertTrue((SuggestedCategory.expenses + SuggestedCategory.incomes).allSatisfy {
            !$0.localizedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })

        for locale in supportedLocalizations {
            let table = try strings(at: appRoot
                .appendingPathComponent("Localizations")
                .appendingPathComponent("\(locale).lproj/Localizable.strings"))
            for key in Set(expectedExpenseKeys + expectedIncomeKeys) {
                XCTAssertNotNil(table[key], "Missing suggested-category key \(key) in \(locale)")
            }
        }
    }

    func testConfigurationErrorsHaveCatalogEntries() throws {
        let keys = [
            "Unsupported bundle identifier: %@",
            "The App Group container is unavailable: %@",
            "The managed object model is unavailable: %@",
        ]

        for locale in supportedLocalizations {
            let table = try strings(at: appRoot
                .appendingPathComponent("Localizations")
                .appendingPathComponent("\(locale).lproj/Localizable.strings"))
            for key in keys {
                XCTAssertNotNil(table[key], "Missing configuration-error key \(key) in \(locale)")
            }
        }
    }

    func testWidgetAndShortcutMetadataHaveCatalogEntries() throws {
        let keys = [
            "Overall Budget",
            "ADD\nBUDGET",
            "New Transaction",
            "Get Insights",
            "Get Budget Insights",
            "Log an ${income} of ${amount} under ${expenseCategory}",
            "Log an ${income} of ${amount} under ${incomeCategory}",
            "Calculate ${type} for ${timeframe}",
            "Calculate leftover amount for the ${budget} ${type}",
        ]

        let englishTable = try strings(at: appRoot
            .appendingPathComponent("Localizations")
            .appendingPathComponent("en.lproj/Localizable.strings"))

        for locale in supportedLocalizations {
            let table = try strings(at: appRoot
                .appendingPathComponent("Localizations")
                .appendingPathComponent("\(locale).lproj/Localizable.strings"))
            for key in keys {
                let localizedValue = try XCTUnwrap(table[key], "Missing Widget or Shortcut key \(key) in \(locale)")
                let englishValue = try XCTUnwrap(englishTable[key])
                XCTAssertEqual(
                    namedPlaceholders(in: localizedValue),
                    namedPlaceholders(in: englishValue),
                    "Named placeholders differ for \(key) in \(locale)"
                )
            }
        }
    }

    func testAppShortcutPhrasesHaveMatchingKeysAndNamedPlaceholders() throws {
        let expectedKeys = [
            "Log a new transaction in ${applicationName}",
            "Get insights in ${applicationName}",
            "Extract leftover amount for your budgets in ${applicationName}",
        ]
        let tables = try supportedLocalizations.map { locale in
            (locale, try strings(at: appRoot
                .appendingPathComponent("Localizations")
                .appendingPathComponent("\(locale).lproj/AppShortcuts.strings")))
        }
        let referenceKeys = Set(tables[0].1.keys)

        XCTAssertEqual(referenceKeys, Set(expectedKeys))
        for (locale, table) in tables {
            XCTAssertEqual(Set(table.keys), referenceKeys, "AppShortcuts.strings keys differ for \(locale)")
            for key in referenceKeys {
                let value = try XCTUnwrap(table[key])
                XCTAssertEqual(namedPlaceholders(in: value), ["${applicationName}"])
            }
        }
    }

    func testAccessibleCurrencyAmountsUseLocaleFormattingWithoutDuplicateSymbols() {
        let dollars = localizedCurrencyAmount(
            1234.56,
            currencyCode: "USD",
            showCents: true,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(dollars.filter { $0 == "$" }.count, 1)
        XCTAssertTrue(dollars.contains("1,234.56"))

        let signedDollars = localizedCurrencyAmount(
            1234.56,
            currencyCode: "USD",
            showCents: true,
            showPositiveSign: true,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(signedDollars.contains("+"))
        XCTAssertEqual(signedDollars.filter { $0 == "$" }.count, 1)

        let negativeEuros = localizedCurrencyAmount(
            -1234.56,
            currencyCode: "EUR",
            showCents: true,
            locale: Locale(identifier: "de_DE")
        )
        XCTAssertTrue(negativeEuros.contains("€"))
        XCTAssertTrue(negativeEuros.contains("-"))
        XCTAssertTrue(negativeEuros.contains("1.234,56"))

        let yen = localizedCurrencyAmount(
            1234.56,
            currencyCode: "JPY",
            showCents: false,
            locale: Locale(identifier: "ja_JP")
        )
        XCTAssertTrue(yen.contains("￥") || yen.contains("¥"))
        XCTAssertFalse(yen.contains(".56"))
    }

    func testWidgetDateIntervalsFollowLocaleConventions() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 8))!

        func expected(locale: Locale) -> String {
            let formatter = DateIntervalFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: start, to: end)
        }

        let english = localizedDateInterval(from: start, to: end, locale: Locale(identifier: "en_US"), timeZone: timeZone)
        let german = localizedDateInterval(from: start, to: end, locale: Locale(identifier: "de_DE"), timeZone: timeZone)
        let japanese = localizedDateInterval(from: start, to: end, locale: Locale(identifier: "ja_JP"), timeZone: timeZone)

        XCTAssertEqual(english, expected(locale: Locale(identifier: "en_US")))
        XCTAssertEqual(german, expected(locale: Locale(identifier: "de_DE")))
        XCTAssertEqual(japanese, expected(locale: Locale(identifier: "ja_JP")))
        XCTAssertNotEqual(english, german)
        XCTAssertNotEqual(english, japanese)
    }

    func testWidgetSingleDatesFollowLocaleOrderAndDensity() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 3))!
        let locales = ["en_US", "zh_Hans", "ja_JP"]

        for identifier in locales {
            let locale = Locale(identifier: identifier)
            for template in ["dMMMyyyy", "dMMMyy"] {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = timeZone
                formatter.setLocalizedDateFormatFromTemplate(template)

                let value = localizedDate(date, template: template, locale: locale, timeZone: timeZone)
                XCTAssertEqual(value, formatter.string(from: date))
                XCTAssertTrue(value.contains("3"))
                XCTAssertTrue(value.contains("9") || value.localizedCaseInsensitiveContains("Sep"))
            }
        }

        let english = localizedDate(date, template: "dMMMyyyy", locale: Locale(identifier: "en_US"), timeZone: timeZone)
        let chinese = localizedDate(date, template: "dMMMyyyy", locale: Locale(identifier: "zh_Hans"), timeZone: timeZone)
        let japanese = localizedDate(date, template: "dMMMyyyy", locale: Locale(identifier: "ja_JP"), timeZone: timeZone)
        XCTAssertNotEqual(english, chinese)
        XCTAssertNotEqual(english, japanese)
    }

    func testDynamicWidgetAndShortcutSentencesAreCompleteReorderableFormats() throws {
        let signatures: [String: [String]] = [
            "widget.recent.summary": ["%1$@", "%2$@"],
            "widget.recent.inline.summary": ["%1$@", "%2$@", "%3$@"],
            "widget.insights.summary": ["%1$@", "%2$@"],
            "widget.budget.amount.status.period": ["%1$@", "%2$@", "%3$@"],
            "widget.budget.inline.status": ["%1$@", "%2$@", "%3$@"],
            "widget.budget.left.period": ["%1$@"],
            "widget.budget.over.period": ["%1$@"],
            "widget.budget.spent.percent": ["%1$@"],
            "widget.insights.no.transactions.period": ["%1$@"],
            "shortcut.insights.summary": ["%1$@", "%2$@"],
            "shortcut.budget.left": ["%1$@"],
            "shortcut.budget.over": ["%1$@"],
        ]

        for locale in supportedLocalizations {
            let table = try strings(at: appRoot
                .appendingPathComponent("Localizations")
                .appendingPathComponent("\(locale).lproj/Localizable.strings"))
            for (key, expectedSignature) in signatures {
                let format = try XCTUnwrap(table[key], "Missing dynamic sentence format \(key) in \(locale)")
                XCTAssertEqual(formatTokens(in: format), expectedSignature.sorted())
                let rendered = String(format: format, locale: Locale(identifier: locale), arguments: ["A", "B", "C"])
                XCTAssertFalse(rendered.contains("%@"))
                XCTAssertFalse(rendered.contains("$@"))
            }
        }
    }

    func testCompiledApplicationAndWidgetContainTrilingualResources() throws {
        try assertCompiledResources(in: .main, includeLocalizable: true)
        for locale in supportedLocalizations {
            XCTAssertNotNil(Bundle.main.url(forResource: "AppShortcuts", withExtension: "strings", subdirectory: nil, localization: locale))
        }

        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let widgetBundle = try XCTUnwrap(Bundle(url: plugInsURL.appendingPathComponent("LittleSaverWidget.appex")))
        try assertCompiledResources(in: widgetBundle, includeLocalizable: true)

        for extensionName in ["LittleSaverIntent.appex", "LittleSaverIntentUI.appex"] {
            let extensionBundle = try XCTUnwrap(Bundle(url: plugInsURL.appendingPathComponent(extensionName)))
            try assertCompiledResources(in: extensionBundle, includeLocalizable: false)
        }
    }

    private var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func strings(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String], "Invalid strings file: \(url.path)")
    }

    private func dictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any], "Invalid property list: \(url.path)")
    }

    private func formatTokens(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:@|lld|ld|d|(?:\.\d+)?f|%)"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }.sorted()
    }

    private func namedPlaceholders(in value: String) -> [String] {
        let pattern = #"\$\{[^}]+\}"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }.sorted()
    }

    private func preferredLocalization(for preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: supportedLocalizations, forPreferences: preferences).first ?? "en"
    }

    private func assertCompiledResources(in bundle: Bundle, includeLocalizable: Bool) throws {
        XCTAssertTrue(Set(supportedLocalizations).isSubset(of: Set(bundle.localizations)), "Missing compiled localizations in \(bundle.bundleURL.path)")
        for locale in supportedLocalizations {
            XCTAssertNotNil(bundle.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: locale))
            XCTAssertNotNil(bundle.url(forResource: "WidgetConfiguration", withExtension: "strings", subdirectory: nil, localization: locale))
            if includeLocalizable {
                XCTAssertNotNil(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: locale))
                XCTAssertNotNil(bundle.url(forResource: "Localizable", withExtension: "stringsdict", subdirectory: nil, localization: locale))
            }
        }
    }
}
