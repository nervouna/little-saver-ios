# Schema and platform compatibility policy

## Persistence and CloudKit

`LittleSaverV1` is frozen for this development cycle. Do not add identity, generation, token,
suppression, or reconciliation fields. Later model changes are only for real product fields, and
must stay CloudKit-additive: existing entity and attribute names and types stay as they are.

`LittleSaverCore` owns the model and persistence lifecycle. `LittleSaverDevelopmentV0` is the
exact historical development model; do not rewrite it. `LittleSaverV1` is its additive,
CloudKit-compatible successor. Preserve migration/reopen tests whenever changing the model.
Never silently erase an incompatible store or detach a live SQLite coordinator to make a test pass.

Future model changes must preserve existing entity/attribute names and types. Add optional fields
or new entities with compatible defaults, optional inverse relationships, and no unique constraints.
Keep family/occurrence identities, deletion suppression, and MainBudget revision projection intact.
Deterministic reconciliation, tombstones and throwing serial commands define the supported
synchronization semantics. Preserve their existing rules, including removal of redundant records
after deterministic reconciliation; do not substitute arbitrary destructive cleanup or uniqueness
constraints for those rules.

Schema initialization requires all three existing conditions: a DEBUG build, `cloudSync` mode,
and the explicit `--initialize-cloudkit-schema` process argument. Ordinary launches, local stores,
unit tests, Release builds and CI must never initialize a remote schema. The explicit argument
is not authorization to reset a container or deploy production changes.

CloudKit schema deployment is a separate, explicitly authorized operation after compatibility
testing. Production evolution is additive: record types/fields cannot be renamed, removed or
have their type changed. Follow Apple's [Core Data CloudKit model guidance](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)
and [schema deployment policy](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).

## Authentication and navigation

App Lock uses a fresh `LAContext` and `.deviceOwnerAuthentication` per action, allowing the system
to provide device-passcode fallback. Enable/disable preferences are written only after success.
Inactive scenes keep the content cover and pending system request; success is held until active.
Backgrounding clears request identity before invalidating the context. Stale callbacks cannot
unlock or change preferences. Settings recovery is always an explicit user action.

Budget Widget destinations prefer the budget business UUID. Legacy name links require exactly
one match across all budget records, including invalid records. Missing, invalid or ambiguous
targets display unavailable and do not fall back to another budget. Each request has a separate
identity, is retained until a current snapshot is ready, and is consumed once after unlocking.
Manual selection and Widget selection use the same navigation state. Search uses iOS 15 native
FocusState, requesting focus only at presentation entry and releasing it on cancel/disappear.

## Privacy manifests and validation

Each first-party executable/dynamic framework carries `PrivacyInfo.xcprivacy` in its own bundle:

| Bundle | Direct required-reason APIs |
| --- | --- |
| App | UserDefaults `CA92.1` (own-app lock preference), `1C8F.1` (App Group preferences); ActiveKeyboards `54BD.1` (visible emoji input UI) |
| Widget | UserDefaults `1C8F.1` |
| Core framework | UserDefaults `1C8F.1` |
| Intent, Intent UI | No direct required-reason APIs; valid empty declarations |

The app does not track users or collect data for developer access. Ledger data remains in local
storage and the user's private iCloud container when sync is enabled. Keyboard information is
used only for visible input behavior, never transmitted. Do not add speculative reasons to cover
APIs that a target merely reaches through another framework; review direct calls and linked SDKs.
See Apple's [required reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
and [manifest placement](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).

Run `swift scripts/validate-privacy.swift --source <repository>` for format/reason/resource-membership
validation, then `--products <LittleSaver.app>` against each built Simulator/device application.
CI retains its pinned Xcode/macOS/simulator policy and runs tests, Debug analyze, both unsigned
Release builds and actual bundle checks. These checks do not prove signed-archive acceptance,
physical passcode/keyboard/Widget UI behavior, live CloudKit synchronization, or hosted CI execution.
The existing Home content cover is not a claim that every separately presented modal has been
manually verified for app-switcher privacy; do not dismiss unsaved editors to simulate protection.
