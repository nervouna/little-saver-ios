# Transaction CSV contract

CSV transfers transaction fields, not the complete database. IDs, recurrence schedules,
budgets, templates, deletion history and sync metadata are not exported or reconstructed.
Import creates new transaction IDs and does not deduplicate existing records.

## Canonical format

The first five headers remain `Date,Note,Amount,Category,Type`. Current exports append
`DateReferenceSeconds`. Recognized headers are matched by exact field name, independently
of column order. Import requires user confirmation before any database write.

- `Date` is a readable UTC timestamp in `yyyy-MM-dd HH:mm:ss Z` format. Export deliberately
  floors the original reference-time value to a whole second for this display field.
- `DateReferenceSeconds`, when present, is authoritative: it is the original
  `Date.timeIntervalSinceReferenceDate` Double (seconds since 2001-01-01 00:00:00 UTC),
  serialized with Swift's locale-independent round-trippable Double representation.
  Both fields must parse, be supported dates, and identify the same whole reference second.
  A missing, non-finite, out-of-range or conflicting exact value fails the entire import.
  Edit both date fields consistently, or intentionally use the legacy five-column format.
- `Note` is a required string value and is preserved verbatim, including empty strings,
  leading/trailing spaces, quotes, commas, Unicode and embedded CR/LF/CRLF.
- `Amount` retains the exact finite signed Double value. Negative zero is normalized to
  positive zero, as elsewhere in the ledger. It is not rounded to currency precision,
  converted, or made absolute. The selected currency is a display preference only.
- `Type` is `Income` or `Expense` (input matching is case-insensitive). A nonempty category
  matches an existing category by both exact name and type, not name alone. Missing or
  ambiguous matches fail; categories are never created automatically. An empty Category
  field explicitly means no category. Resolve unknown names/types in Settings and retry.

Export rejects transaction fields that cannot be represented without substitution, including
missing dates/notes/types, non-finite money, empty/blank real category names, ambiguous category
names within a type, and a transaction whose type disagrees with its linked category. It does
not replace missing dates with today or turn a damaged real category into no category.

## Legacy/manual imports

Old five-column LittleSaver/Dime exports and the bundled sample remain supported. Their
Date.description-style timestamps carry whole-second precision; fractions already absent
from old exports cannot be recovered. Canonical imports without an exact field also accept
ISO-8601 timestamps with the complete `yyyy-MM-ddTHH:mm:ssZ` or
`yyyy-MM-ddTHH:mm:ss+HH:mm` / `-HH:mm` shape, or date-only values. ISO components must
form a real Gregorian date; impossible days/months and trailing characters are rejected,
including when an exact reference value would match a silently normalized date.

Four-column files retain manual column mapping, date-format selection and category linking.
Recognizing four column names only removes the declared header; it does not bypass category
linking. Unrecognized headers are skipped only when the user explicitly selects that option,
never because the first row does or does not contain digits. Preview changes are atomic;
an invalid header selection leaves both the old selection and old preview unchanged.

Manual imports retain the legacy bank-statement convention: amounts are made absolute and
the linked category determines income versus expense. Notes are nevertheless preserved
verbatim. If a manually mapped file declares Type, it must agree with the linked category.
Negative or repeated mapping indexes, missing selected cells, invalid dates and non-finite
amounts fail without partial commits. Ragged preview rows retain empty placeholder cells
without shifting later rows into their positions.

## CSV records and file handling

The paired codec follows the quoting rules in [RFC 4180 section 2](https://www.rfc-editor.org/rfc/rfc4180#section-2):
comma/quote/newline-bearing fields are quoted and embedded ASCII quotes are doubled.
Encoding uses CRLF record separators. Parsing accepts CRLF, LF and CR separators but never
normalizes quoted contents. Field spaces and Unicode scalars are retained.
A single file-leading UTF-8 BOM is accepted as metadata, including before a quoted header.
The encoder quotes a literal BOM-leading first field so it remains data on the next read.

Empty input has zero records. A blank record has one empty field; a quoted empty field at
EOF is also retained. Empty fields and interior blank records are preserved by the codec,
then required transaction fields are validated at the import boundary. Zero-field records
cannot be encoded. One terminal record separator does not create an extra record.

Import reads UTF-8 files without modifying them and balances every successful security-scoped
access acquisition on success, decode failure or read failure. All database imports use one
throwing command. Export reads and writes off the main actor, uses a fresh unique URL per
attempt, prevents duplicate pending requests, and opens the share sheet only after both
reading and writing succeed. A failure never shares an older export file.
