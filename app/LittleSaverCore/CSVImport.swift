import Combine
import CoreData
import Foundation

public enum CSVImportError: LocalizedError, Equatable {
    case malformedCSV(line: Int)
    case emptyDocument
    case invalidMapping
    case missingColumn(row: Int)
    case invalidAmount(row: Int, value: String)
    case invalidDate(row: Int, value: String)
    case conflictingDate(row: Int)
    case invalidType(row: Int, value: String)
    case unmatchedCategory(row: Int, value: String)
    case ambiguousCategory(row: Int, value: String)
    case invalidCategoryReference(row: Int)
    case invalidExportField(row: Int, field: String)

    public var errorDescription: String? {
        switch self {
        case let .malformedCSV(line): return String(localized: "Malformed CSV near line \(line).")
        case .emptyDocument: return String(localized: "The CSV document is empty.")
        case .invalidMapping: return String(localized: "Select a different valid column for each field.")
        case let .missingColumn(row): return String(localized: "Row \(row) is missing a selected column.")
        case let .invalidAmount(row, value): return String(localized: "Row \(row) has an invalid amount: \(value).")
        case let .invalidDate(row, value): return String(localized: "Row \(row) has an invalid date: \(value).")
        case let .conflictingDate(row): return String(localized: "Row \(row) has conflicting Date and DateReferenceSeconds values.")
        case let .invalidType(row, value): return String(localized: "Row \(row) has an invalid type: \(value).")
        case let .unmatchedCategory(row, value): return String(localized: "Row \(row) has an unmatched category: \(value).")
        case let .ambiguousCategory(row, value): return String(localized: "Row \(row) has an ambiguous category: \(value).")
        case let .invalidCategoryReference(row): return String(localized: "Row \(row) references an invalid category.")
        case let .invalidExportField(row, field): return String(localized: "Row \(row) cannot be exported without changing its \(field) field.")
        }
    }
}

/// RFC-style CSV records. Record separators may be CRLF, LF or CR; quoted
/// contents are never normalized. Empty input has no records; a blank record
/// has one empty field. Zero-field records are not representable.
public enum CSVDocumentParser {
    public static func parse(_ text: String) throws -> [[String]] {
        let source = text.unicodeScalars
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        enum State { case unquoted, quoted, afterQuote }
        var state = State.unquoted
        var started = false
        // Only a file-leading BOM is metadata. The encoder quotes a literal BOM
        // at the start of a field so it is never mistaken for this marker.
        var index = source.first == "\u{FEFF}" ? source.index(after: source.startIndex) : source.startIndex
        var line = 1

        func appendRow() {
            row.append(field); rows.append(row)
            row.removeAll(keepingCapacity: true); field.removeAll(keepingCapacity: true)
            started = false
        }

        while index < source.endIndex {
            let scalar = source[index]
            var next = source.index(after: index)
            if scalar == "\"" {
                started = true
                if state == .quoted, next < source.endIndex, source[next] == "\"" {
                    field.append("\""); index = source.index(after: next); continue
                }
                switch state {
                case .unquoted where field.isEmpty: state = .quoted
                case .quoted: state = .afterQuote
                default: throw CSVImportError.malformedCSV(line: line)
                }
            } else if scalar == ",", state != .quoted {
                row.append(field); field.removeAll(keepingCapacity: true)
                started = true; state = .unquoted
            } else if (scalar == "\r" || scalar == "\n"), state != .quoted {
                appendRow(); line += 1; state = .unquoted
                if scalar == "\r", next < source.endIndex, source[next] == "\n" { next = source.index(after: next) }
            } else {
                guard state != .afterQuote else { throw CSVImportError.malformedCSV(line: line) }
                field.unicodeScalars.append(scalar); started = true
                if scalar == "\n" || (scalar == "\r" && (next == source.endIndex || source[next] != "\n")) { line += 1 }
            }
            index = next
        }
        guard state != .quoted else { throw CSVImportError.malformedCSV(line: line) }
        if started || !row.isEmpty { appendRow() }
        return rows
    }

    public static func encode(_ rows: [[String]]) throws -> String {
        try rows.enumerated().map { index, row in
            guard !row.isEmpty else { throw CSVImportError.missingColumn(row: index + 1) }
            return row.map { field in
                if field.isEmpty || field.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) || field.hasPrefix("\u{FEFF}") {
                    let escaped = field.unicodeScalars.reduce(into: "") { result, scalar in
                        result.unicodeScalars.append(scalar)
                        if scalar == "\"" { result.unicodeScalars.append(scalar) }
                    }
                    return "\"" + escaped + "\""
                }
                return field
            }.joined(separator: ",") + "\r\n"
        }.joined()
    }
}

public struct CSVImportMapping: Equatable, Sendable {
    public let categoryColumn: Int
    public let noteColumn: Int
    public let dateColumn: Int
    public let amountColumn: Int
    public let typeColumn: Int?
    public let exactDateColumn: Int?
    public let isCanonical: Bool

    public init(categoryColumn: Int, noteColumn: Int, dateColumn: Int, amountColumn: Int, typeColumn: Int? = nil, exactDateColumn: Int? = nil, isCanonical: Bool = false) {
        self.categoryColumn = categoryColumn; self.noteColumn = noteColumn
        self.dateColumn = dateColumn; self.amountColumn = amountColumn
        self.typeColumn = typeColumn; self.exactDateColumn = exactDateColumn; self.isCanonical = isCanonical
    }

    private var indices: [Int] { [categoryColumn, noteColumn, dateColumn, amountColumn] + [typeColumn, exactDateColumn].compactMap { $0 } }
    public var highestColumn: Int { indices.max() ?? 0 }
    public func validate() throws {
        guard indices.allSatisfy({ $0 >= 0 }), Set(indices).count == indices.count,
              !isCanonical || typeColumn != nil, exactDateColumn == nil || typeColumn != nil else { throw CSVImportError.invalidMapping }
    }

    /// Recognize declared field names, never infer a header from numeric content.
    public static func recognizedHeader(_ header: [String]) throws -> CSVImportMapping? {
        var names = header
        if let first = names.first, first.hasPrefix("\u{FEFF}") { names[0] = String(first.dropFirst()) }
        let required = ["Date", "Note", "Amount", "Category"]
        guard required.allSatisfy(names.contains) else { return nil }
        let recognized = required + ["Type", "DateReferenceSeconds"]
        guard recognized.allSatisfy({ name in names.filter { $0 == name }.count <= 1 }) else { throw CSVImportError.invalidMapping }
        let mapping = CSVImportMapping(categoryColumn: names.firstIndex(of: "Category")!, noteColumn: names.firstIndex(of: "Note")!, dateColumn: names.firstIndex(of: "Date")!, amountColumn: names.firstIndex(of: "Amount")!, typeColumn: names.firstIndex(of: "Type"), exactDateColumn: names.firstIndex(of: "DateReferenceSeconds"), isCanonical: names.contains("Type"))
        try mapping.validate()
        return mapping
    }
}

public struct CSVImportTable: Sendable {
    public let rows: [[String]]
    public let columns: [[String]]
    public init(rows: [[String]]) throws {
        guard !rows.isEmpty else { throw CSVImportError.emptyDocument }
        let width = rows.map(\.count).max() ?? 0
        guard width >= 4 else { throw CSVImportError.invalidMapping }
        self.rows = rows
        // Missing cells stay in their row rather than shifting later preview values.
        columns = (0..<width).map { column in rows.map { $0.indices.contains(column) ? $0[column] : "" } }
    }
}

public struct CSVImportPreviewSelection: Sendable {
    public let originalRows: [[String]]
    public private(set) var skipsHeader: Bool
    public private(set) var table: CSVImportTable
    public init(rows: [[String]], skipsHeader: Bool) throws {
        originalRows = rows; self.skipsHeader = skipsHeader
        table = try CSVImportTable(rows: skipsHeader ? Array(rows.dropFirst()) : rows)
    }
    public mutating func setSkippingHeader(_ value: Bool) throws {
        let next = try CSVImportTable(rows: value ? Array(originalRows.dropFirst()) : originalRows)
        table = next
        skipsHeader = value
    }
}

private struct CSVCategoryKey: Hashable {
    let name: String
    let income: Bool
}

public enum CSVTransactionImporter {
    private struct ValidatedRow: Sendable {
        let rowNumber: Int
        let note: String
        let categoryName: String
        let categoryID: LedgerReference?
        let income: Bool?
        let amount: Double
        let date: Date
    }

    static func dateFormatter(format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone; formatter.dateFormat = format; formatter.isLenient = false
        return formatter
    }

    /// ISO8601DateFormatter accepts impossible dates and trailing input on some
    /// platforms. Validate the complete supported shape and real civil components.
    private static func strictISODate(_ text: String) -> Date? {
        let pattern = #"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(Z|([+-])([0-9]{2}):([0-9]{2}))$"#
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: fullRange), match.range == fullRange else { return nil }
        func field(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        let values = (1...6).compactMap { field($0).flatMap(Int.init) }
        guard values.count == 6 else { return nil }
        let offset: Int
        if field(7) == "Z" { offset = 0 }
        else {
            guard let hours = field(9).flatMap(Int.init), hours <= 23,
                  let minutes = field(10).flatMap(Int.init), minutes <= 59 else { return nil }
            offset = (hours * 3600 + minutes * 60) * (field(8) == "-" ? -1 : 1)
        }
        guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let components = DateComponents(calendar: calendar, timeZone: zone, year: values[0], month: values[1], day: values[2], hour: values[3], minute: values[4], second: values[5])
        guard components.isValidDate else { return nil }
        return components.date
    }

    public static func importRows(
        _ rows: [[String]], mapping: CSVImportMapping, dateFormat: String,
        categoriesByName: [String: LedgerReference], into controller: DataController,
        timeZone: TimeZone = .current
    ) async throws -> Int {
        try mapping.validate()
        guard !rows.isEmpty else { throw CSVImportError.emptyDocument }
        try await controller.waitUntilReady()
        let formatter = dateFormatter(format: dateFormat, timeZone: timeZone)
        let canonicalFormatter = dateFormatter(format: "yyyy-MM-dd HH:mm:ss Z", timeZone: TimeZone(secondsFromGMT: 0)!)
        var validated: [ValidatedRow] = []
        for (offset, row) in rows.enumerated() {
            let number = offset + 1
            guard row.count > mapping.highestColumn else { throw CSVImportError.missingColumn(row: number) }
            let amountText = row[mapping.amountColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Double(amountText), let amount = MoneyAmount(parsed) else { throw CSVImportError.invalidAmount(row: number, value: amountText) }
            let type: Bool?
            if let column = mapping.typeColumn {
                switch row[column].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "income": type = true
                case "expense": type = false
                default: throw CSVImportError.invalidType(row: number, value: row[column])
                }
            } else { type = nil }
            let categoryName = row[mapping.categoryColumn]
            let reference = categoriesByName[categoryName]
            if !mapping.isCanonical, reference == nil { throw CSVImportError.unmatchedCategory(row: number, value: categoryName) }
            let text = row[mapping.dateColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            let readable: Date?
            if mapping.isCanonical {
                readable = canonicalFormatter.date(from: text)
                    ?? dateFormatter(format: "yyyy-MM-dd", timeZone: timeZone).date(from: text)
                    ?? strictISODate(text)
            } else { readable = formatter.date(from: text) }
            guard let readable, LedgerCalendar.isValid(readable) else { throw CSVImportError.invalidDate(row: number, value: text) }
            let date: Date
            if let column = mapping.exactDateColumn {
                let exactText = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let seconds = Double(exactText), seconds.isFinite else { throw CSVImportError.invalidDate(row: number, value: exactText) }
                date = Date(timeIntervalSinceReferenceDate: seconds)
                guard LedgerCalendar.isValid(date) else { throw CSVImportError.invalidDate(row: number, value: exactText) }
                guard floor(readable.timeIntervalSinceReferenceDate) == floor(seconds) else { throw CSVImportError.conflictingDate(row: number) }
            } else { date = readable }
            // Legacy bank CSV signs are interpreted by the manually linked category.
            // Canonical paired transfers retain the signed finite storage value.
            validated.append(ValidatedRow(rowNumber: number, note: row[mapping.noteColumn], categoryName: categoryName, categoryID: reference, income: type, amount: mapping.isCanonical ? amount.value : abs(amount.value), date: date))
        }

        let items = validated
        return try await controller.performCommand { context in
            let categories = mapping.isCanonical ? try context.fetch(Category.fetchRequest()) : []
            let grouped = Dictionary(grouping: categories, by: { CSVCategoryKey(name: $0.name ?? "", income: $0.income) })
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            for item in items {
                let category: Category?
                if mapping.isCanonical {
                    if item.categoryName.isEmpty { category = nil }
                    else {
                        guard !item.categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CSVImportError.invalidCategoryReference(row: item.rowNumber) }
                        let matches = grouped[CSVCategoryKey(name: item.categoryName, income: item.income ?? false)] ?? []
                        guard !matches.isEmpty else { throw CSVImportError.unmatchedCategory(row: item.rowNumber, value: item.categoryName) }
                        guard matches.count == 1 else { throw CSVImportError.ambiguousCategory(row: item.rowNumber, value: item.categoryName) }
                        category = matches[0]
                    }
                } else {
                    category = try item.categoryID?.resolve(in: context, as: Category.self)
                    guard let category else { throw CSVImportError.invalidCategoryReference(row: item.rowNumber) }
                    if let type = item.income, type != category.income { throw CSVImportError.invalidCategoryReference(row: item.rowNumber) }
                }
                let transaction = Transaction(context: context)
                transaction.note = item.note
                transaction.category = category; transaction.income = item.income ?? category?.income ?? false
                transaction.amount = item.amount; transaction.date = item.date
                transaction.id = UUID(); transaction.deduplicationToken = UUID().uuidString.lowercased()
                transaction.day = calendar.startOfDay(for: item.date)
                transaction.month = calendar.date(from: calendar.dateComponents([.month, .year], from: item.date))
                transaction.recurringType = 0; transaction.recurringCoefficient = 1
            }
            return items.count
        }
    }
}

public extension DataController {
    /// Portable transaction fields only, not recurrence state or a full backup.
    func csvExportText() async throws -> String {
        try await performBackgroundRead { context in
            let request = self.fetchRequestForExport()
            request.relationshipKeyPathsForPrefetching = ["category"]
            let transactions = try context.fetch(request)
            let categories = try context.fetch(Category.fetchRequest())
            let grouped = Dictionary(grouping: categories, by: { CSVCategoryKey(name: $0.name ?? "", income: $0.income) })
            let formatter = CSVTransactionImporter.dateFormatter(format: "yyyy-MM-dd HH:mm:ss Z", timeZone: TimeZone(secondsFromGMT: 0)!)
            var rows = [["Date", "Note", "Amount", "Category", "Type", "DateReferenceSeconds"]]
            for (offset, transaction) in transactions.enumerated() {
                let number = offset + 1
                guard let date = transaction.date, LedgerCalendar.isValid(date) else { throw CSVImportError.invalidExportField(row: number, field: "Date") }
                guard let note = transaction.note else { throw CSVImportError.invalidExportField(row: number, field: "Note") }
                guard let money = MoneyAmount(transaction.amount) else { throw CSVImportError.invalidExportField(row: number, field: "Amount") }
                guard transaction.value(forKey: "income") is NSNumber else { throw CSVImportError.invalidExportField(row: number, field: "Type") }
                let name: String
                if let category = transaction.category {
                    guard let rawName = category.name, !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, category.income == transaction.income else { throw CSVImportError.invalidExportField(row: number, field: "Category") }
                    guard grouped[CSVCategoryKey(name: rawName, income: category.income)]?.count == 1 else { throw CSVImportError.ambiguousCategory(row: number, value: rawName) }
                    name = rawName
                } else { name = "" }
                let readableDate = Date(timeIntervalSinceReferenceDate: floor(date.timeIntervalSinceReferenceDate))
                rows.append([formatter.string(from: readableDate), note, String(money.value), name, transaction.income ? "Income" : "Expense", String(date.timeIntervalSinceReferenceDate)])
            }
            return try CSVDocumentParser.encode(rows)
        }
    }
}

public enum CSVExportFile {
    public static func prepare(
        directory: URL = FileManager.default.temporaryDirectory,
        read: () async throws -> String,
        write: @escaping @Sendable (String, URL) throws -> Void = { text, url in try Data(text.utf8).write(to: url, options: .atomic) }
    ) async throws -> URL {
        let text = try await read()
        try Task.checkCancellation()
        let url = directory.appendingPathComponent("LittleSaver-\(UUID().uuidString).csv")
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try write(text, url)
            try Task.checkCancellation()
            return url
        }.value
    }
}

@MainActor
public final class CSVExportPreparation: ObservableObject {
    @Published public private(set) var isPreparing = false
    @Published public private(set) var url: URL?
    @Published public private(set) var error: String?
    public init() {}
    public func clear() { url = nil; error = nil }
    public func prepare(using operation: () async throws -> URL) async {
        guard !isPreparing else { return }
        isPreparing = true; url = nil; error = nil
        defer { isPreparing = false }
        do {
            let fresh = try await operation()
            try Task.checkCancellation()
            url = fresh
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }
}
