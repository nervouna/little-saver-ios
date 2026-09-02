import CoreData
import Foundation
public enum CSVImportError: LocalizedError, Equatable {
    case malformedCSV(line: Int)
    case emptyDocument
    case missingColumn(row: Int)
    case invalidAmount(row: Int, value: String)
    case invalidDate(row: Int, value: String)
    case unmatchedCategory(row: Int, value: String)
    case invalidCategoryReference(row: Int)

    public var errorDescription: String? {
        switch self {
        case let .malformedCSV(line): return String(localized: "Malformed CSV near line \(line).")
        case .emptyDocument: return String(localized: "The CSV document is empty.")
        case let .missingColumn(row): return String(localized: "Row \(row) is missing a selected column.")
        case let .invalidAmount(row, value): return String(localized: "Row \(row) has an invalid amount: \(value).")
        case let .invalidDate(row, value): return String(localized: "Row \(row) has an invalid date: \(value).")
        case let .unmatchedCategory(row, value): return String(localized: "Row \(row) has an unmatched category: \(value).")
        case let .invalidCategoryReference(row): return String(localized: "Row \(row) references an invalid category.")
        }
    }
}

public enum CSVDocumentParser {
    public static func parse(_ text: String) throws -> [[String]] {
        // Swift treats CRLF as a single extended grapheme cluster. Normalize line
        // endings first so record boundaries are parsed consistently.
        let source = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows = [[String]]()
        var row = [String]()
        var field = ""
        enum FieldState {
            case unquoted
            case quoted
            case afterQuote
        }

        var state = FieldState.unquoted
        var index = source.startIndex
        var line = 1

        func appendRow() {
            row.append(field)
            if row.contains(where: { !$0.isEmpty }) {
                rows.append(row)
            }
            row.removeAll(keepingCapacity: true)
            field.removeAll(keepingCapacity: true)
        }

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            if character == "\"" {
                if state == .quoted, next < source.endIndex, source[next] == "\"" {
                    field.append("\"")
                    index = source.index(after: next)
                    continue
                }
                switch state {
                case .unquoted where field.isEmpty:
                    state = .quoted
                case .quoted:
                    state = .afterQuote
                default:
                    throw CSVImportError.malformedCSV(line: line)
                }
            } else if character == ",", state != .quoted {
                row.append(field)
                field.removeAll(keepingCapacity: true)
                state = .unquoted
            } else if character == "\n", state != .quoted {
                appendRow()
                line += 1
                state = .unquoted
            } else {
                guard state != .afterQuote else {
                    throw CSVImportError.malformedCSV(line: line)
                }
                field.append(character)
                if character == "\n" { line += 1 }
            }
            index = source.index(after: index)
        }

        guard state != .quoted else { throw CSVImportError.malformedCSV(line: line) }
        if !field.isEmpty || !row.isEmpty { appendRow() }
        guard !rows.isEmpty else { throw CSVImportError.emptyDocument }
        return rows
    }
}

public struct CSVImportMapping: Equatable, Sendable {
    public init(categoryColumn: Int, noteColumn: Int, dateColumn: Int, amountColumn: Int) {
        self.categoryColumn = categoryColumn
        self.noteColumn = noteColumn
        self.dateColumn = dateColumn
        self.amountColumn = amountColumn
    }

    public let categoryColumn: Int
    public let noteColumn: Int
    public let dateColumn: Int
    public let amountColumn: Int

    public var highestColumn: Int {
        max(categoryColumn, noteColumn, dateColumn, amountColumn)
    }
}

public enum CSVTransactionImporter {
    private struct ValidatedRow: Sendable {
        let rowNumber: Int
        let note: String
        let categoryID: LedgerReference
        let amount: Double
        let date: Date
    }

    public static func importRows(
        _ rows: [[String]],
        mapping: CSVImportMapping,
        dateFormat: String,
        categoriesByName: [String: LedgerReference],
        into controller: DataController,
        timeZone: TimeZone = .current
    ) async throws -> Int {
        try await controller.waitUntilReady()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        formatter.isLenient = false

        var validated = [ValidatedRow]()
        for (offset, row) in rows.enumerated() {
            let rowNumber = offset + 1
            guard row.count > mapping.highestColumn else {
                throw CSVImportError.missingColumn(row: rowNumber)
            }
            let categoryName = row[mapping.categoryColumn]
            guard let category = categoriesByName[categoryName] else {
                throw CSVImportError.unmatchedCategory(row: rowNumber, value: categoryName)
            }
            let amountText = row[mapping.amountColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Double(amountText), let amount = MoneyAmount(parsed) else {
                throw CSVImportError.invalidAmount(row: rowNumber, value: amountText)
            }
            let dateText = row[mapping.dateColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = formatter.date(from: dateText) else {
                throw CSVImportError.invalidDate(row: rowNumber, value: dateText)
            }
            validated.append(ValidatedRow(
                rowNumber: rowNumber,
                note: row[mapping.noteColumn].trimmingCharacters(in: .whitespacesAndNewlines),
                categoryID: category,
                amount: abs(amount.value),
                date: date
            ))
        }

        let items = validated
        return try await controller.performCommand { context in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            for item in items {
                let category = try item.categoryID.resolve(in: context, as: Category.self)
                let transaction = Transaction(context: context)
                transaction.note = item.note.isEmpty ? category.wrappedName : item.note
                transaction.category = category
                transaction.income = category.income
                transaction.amount = item.amount
                transaction.date = item.date
                transaction.id = UUID()
                transaction.deduplicationToken = UUID().uuidString.lowercased()
                transaction.day = calendar.startOfDay(for: item.date)
                transaction.month = calendar.date(from: calendar.dateComponents([.month, .year], from: item.date))
                transaction.recurringType = 0
                transaction.recurringCoefficient = 1
            }
            return items.count
        }
    }
}
