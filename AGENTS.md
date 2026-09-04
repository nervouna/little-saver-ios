# Agent constraints

LittleSaver is a Dime fork with no shipped user base. The local `main` on GitHub is still Dime until a release is explicitly published.

## Ledger

- `LittleSaverV1` is frozen. Do not add identity, generation, token, suppression, or reconciliation machinery.
- Do not invent another historical development model.
- Do not change amount storage from `Double` in this cycle. Type changes are not CloudKit-additive.
- Leave `DataFoundationTests` alone unless a change you made makes an assertion false.

See `docs/schema-and-platform-policy.md`.

## Product work

- Next work is the UI surface, not persistence. Split `LogView` first, then `TransactionView`. Do not use a view split as cover for ledger changes.
- Keep GPL attribution: Rafael Soh / Dime in LICENSE, README, and Settings.

## Git

- Do not fast-forward unpublished work onto local `main`.
- Do not push `main`. Feature branches only.
- Do not squash the existing LittleSaver rewrite commits.
