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

        XCTAssertEqual(referenceKeys.count, 430, "Unexpected Localizable.strings baseline key count")
        for (locale, table) in tables {
            XCTAssertEqual(Set(table.keys), referenceKeys, "Localizable.strings keys differ for \(locale)")
            for key in referenceKeys {
                let value = try XCTUnwrap(table[key], "Missing \(key) in \(locale)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(key) in \(locale)")
                XCTAssertEqual(formatTokens(in: value), formatTokens(in: key), "Format signature differs for \(key) in \(locale)")
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

    func testAccessibleCurrencyAmountsUseLocaleFormattingWithoutDuplicateSymbols() {
        let dollars = localizedCurrencyAmount(
            1234.56,
            currencyCode: "USD",
            showCents: true,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(dollars.filter { $0 == "$" }.count, 1)
        XCTAssertTrue(dollars.contains("1,234.56"))

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

    func testCompiledApplicationAndWidgetContainTrilingualResources() throws {
        try assertCompiledResources(in: .main, includeLocalizable: true)

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
        let pattern = #"%(?:@|lld|ld|d|(?:\.\d+)?f|%)"#
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
