import Foundation
import CoreFoundation

// Validate source membership and the manifests actually copied into unsigned products.
let expected: [String: [String: [String]]] = [
    "LittleSaver": ["NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1", "1C8F.1"], "NSPrivacyAccessedAPICategoryActiveKeyboards": ["54BD.1"]],
    "LittleSaverWidget": ["NSPrivacyAccessedAPICategoryUserDefaults": ["1C8F.1"]],
    "LittleSaverCore": ["NSPrivacyAccessedAPICategoryUserDefaults": ["1C8F.1"]],
    "LittleSaverIntent": [:], "LittleSaverIntentUI": [:]
]

struct ValidationFailure: Error, CustomStringConvertible { let description: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ValidationFailure(description: message) }
}
func plist(_ url: URL) throws -> [String: Any] {
    guard let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else {
        throw ValidationFailure(description: "Invalid plist dictionary: \(url.path)")
    }
    return value
}
func validate(_ url: URL, target: String) throws {
    let value = try plist(url)
    try require(Set(value.keys) == Set(["NSPrivacyTracking", "NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"]), "Unexpected manifest keys: \(url.path)")
    guard let tracking = value["NSPrivacyTracking"] as? NSNumber else { throw ValidationFailure(description: "Missing tracking Bool") }
    try require(CFGetTypeID(tracking) == CFBooleanGetTypeID() && !tracking.boolValue, "Tracking must be false")
    try require((value["NSPrivacyTrackingDomains"] as? [String]) == [], "Unexpected tracking domains")
    try require((value["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true, "Unexpected collected-data declarations")
    guard let entries = value["NSPrivacyAccessedAPITypes"] as? [[String: Any]] else { throw ValidationFailure(description: "Missing API declarations") }
    var actual: [String: [String]] = [:]
    for entry in entries {
        try require(Set(entry.keys) == Set(["NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"]), "Invalid API declaration keys")
        guard let category = entry["NSPrivacyAccessedAPIType"] as? String, let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { throw ValidationFailure(description: "Invalid API declaration values") }
        try require(actual[category] == nil && !reasons.isEmpty && Set(reasons).count == reasons.count, "Duplicate or empty API declaration")
        actual[category] = reasons.sorted()
    }
    try require(actual == expected[target]?.mapValues { $0.sorted() }, "Incorrect reasons for \(target): \(actual)")
    print("PASS \(target): \(url.path)")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    try require(arguments.count == 2, "Usage: swift scripts/validate-privacy.swift --source <repository> | --products <LittleSaver.app>")
    let root = URL(fileURLWithPath: arguments[1])
    if arguments[0] == "--source" {
        let project = try plist(root.appendingPathComponent("app/LittleSaver.xcodeproj/project.pbxproj"))
        guard let objects = project["objects"] as? [String: [String: Any]] else { throw ValidationFailure(description: "Invalid Xcode objects") }
        for target in expected.keys.sorted() {
            let path = "\(target)/PrivacyInfo.xcprivacy"
            try validate(root.appendingPathComponent("app/" + path), target: target)
            let candidates = objects.values.filter { $0["isa"] as? String == "PBXNativeTarget" && $0["name"] as? String == target }
            try require(candidates.count == 1, "Missing or duplicate target \(target)")
            let phases = (candidates.first?["buildPhases"] as? [String] ?? []).compactMap { objects[$0] }.filter { $0["isa"] as? String == "PBXResourcesBuildPhase" }
            let files = phases.flatMap { $0["files"] as? [String] ?? [] }.compactMap { objects[$0]?["fileRef"] as? String }.compactMap { objects[$0] }
            try require(files.filter { $0["path"] as? String == path && $0["sourceTree"] as? String == "SOURCE_ROOT" }.count == 1, "Incorrect manifest resource membership for \(target)")
        }
    } else if arguments[0] == "--products" {
        let paths = ["LittleSaver": "", "LittleSaverWidget": "PlugIns/LittleSaverWidget.appex", "LittleSaverIntent": "PlugIns/LittleSaverIntent.appex", "LittleSaverIntentUI": "PlugIns/LittleSaverIntentUI.appex", "LittleSaverCore": "Frameworks/LittleSaverCore.framework"]
        for target in paths.keys.sorted() {
            let bundle = root.appendingPathComponent(paths[target]!)
            let info = try plist(bundle.appendingPathComponent("Info.plist"))
            guard let executable = info["CFBundleExecutable"] as? String else { throw ValidationFailure(description: "Missing executable for \(target)") }
            try require(FileManager.default.fileExists(atPath: bundle.appendingPathComponent(executable).path), "Missing executable product \(target)")
            try validate(bundle.appendingPathComponent("PrivacyInfo.xcprivacy"), target: target)
        }
    } else { throw ValidationFailure(description: "Unknown validation mode") }
} catch {
    FileHandle.standardError.write(Data("Privacy validation failed: \(error)\n".utf8))
    exit(1)
}
