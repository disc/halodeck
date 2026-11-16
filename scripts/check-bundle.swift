#!/usr/bin/env swift
import Foundation

// Read-only check of a release bundle. It never launches Halodeck and never reads user settings.
func fail(_ message: String) -> Never {
    fputs("Bundle check failed: \(message)\n", stderr)
    exit(1)
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/check-bundle.swift /path/to/Halodeck.app\n", stderr)
    exit(1)
}
let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard let app = Bundle(url: appURL), let resources = app.resourceURL, let info = app.infoDictionary else {
    fail("app bundle is missing or unreadable")
}
func string(_ key: String) -> String? { info[key] as? String }

// Identity, version and Sparkle settings come from version.env next to the scripts.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
guard let env = try? String(contentsOf: root.appendingPathComponent("version.env"), encoding: .utf8) else {
    fail("version.env is missing")
}
var values: [String: String] = [:]
for line in env.split(separator: "\n") {
    let text = line.trimmingCharacters(in: .whitespaces)
    if text.isEmpty || text.hasPrefix("#") { continue }
    let parts = text.split(separator: "=", maxSplits: 1).map(String.init)
    if parts.count == 2 { values[parts[0]] = parts[1] }
}
func setting(_ key: String) -> String {
    guard let value = values[key], !value.isEmpty else { fail("version.env has no \(key)") }
    return value
}

require(app.bundleIdentifier == setting("BUNDLE_ID"), "unexpected bundle identifier")
require(string("CFBundleExecutable") == "Halodeck", "unexpected executable name")
require(info["LSUIElement"] as? Bool == true, "Halodeck must be a menu-bar app (LSUIElement)")
require(string("LSMinimumSystemVersion") == "14.0", "unexpected minimum macOS version")
require(string("CFBundleShortVersionString") == setting("MARKETING_VERSION"), "marketing version differs from version.env")
require(string("CFBundleVersion") == setting("BUILD_NUMBER"), "build number differs from version.env")

require(string("CFBundleIconFile") == "AppIcon", "unexpected app icon reference")
let icon = (try? Data(contentsOf: resources.appendingPathComponent("AppIcon.icns"))) ?? Data()
require(icon.count > 8 && icon.prefix(4) == Data("icns".utf8), "app icon is missing or invalid")

require(string("SUFeedURL") == setting("SPARKLE_FEED_URL"), "unexpected Sparkle feed URL")
require(string("SUPublicEDKey") == setting("SPARKLE_PUBLIC_KEY"), "unexpected Sparkle public key")
// The feed must carry the update key's signature, and an update is verified before it is extracted.
require(info["SURequireSignedFeed"] as? Bool == true, "SURequireSignedFeed must be true")
require(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true, "SUVerifyUpdateBeforeExtraction must be true")
require(info["SUAllowsAutomaticUpdates"] as? Bool == false, "SUAllowsAutomaticUpdates must be false")
require(info["SUEnableAutomaticChecks"] as? Bool == true, "SUEnableAutomaticChecks must be true")
let sparkle = appURL.appendingPathComponent("Contents/Frameworks/Sparkle.framework")
require(Bundle(url: sparkle)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "2.10.1",
        "Sparkle 2.10.1 framework is missing")
for helper in ["Versions/B/Autoupdate", "Versions/B/Updater.app"] {
    require(FileManager.default.fileExists(atPath: sparkle.appendingPathComponent(helper).path),
            "Sparkle helper \(helper) is missing")
}
require(!FileManager.default.fileExists(atPath: sparkle.appendingPathComponent("Versions/B/XPCServices").path),
        "Sparkle XPC services are bundled, but Halodeck is not sandboxed and must not ship them")
for notice in ["LICENSE", "THIRD_PARTY_NOTICES.md"] {
    require(FileManager.default.fileExists(atPath: resources.appendingPathComponent(notice).path), "\(notice) is missing")
}

func run(_ tool: String, _ arguments: [String]) -> (status: Int32, out: Data, err: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do { try process.run() } catch { fail("cannot run \(tool)") }
    // Small outputs: read stderr after stdout without risking a full pipe.
    let output = out.fileHandleForReading.readDataToEndOfFile()
    let errors = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return (process.terminationStatus, output, errors)
}

// Code signing: the hardened runtime on the app and Sparkle's helpers, and none of the entitlements
// that would weaken it. An ad-hoc signature (release.sh's dry run without a Developer ID identity,
// never notarized or published) has no hardened runtime to check.
let signedCode = [appURL, sparkle, sparkle.appendingPathComponent("Versions/B/Autoupdate"),
                  sparkle.appendingPathComponent("Versions/B/Updater.app")]
let forbiddenEntitlements = ["com.apple.security.get-task-allow",
                             "com.apple.security.cs.disable-library-validation",
                             "com.apple.security.cs.allow-dyld-environment-variables",
                             "com.apple.security.cs.allow-unsigned-executable-memory"]
let appSignature = run("/usr/bin/codesign", ["-d", "--verbose=2", appURL.path])
require(appSignature.status == 0, "the app is not signed")
let adHoc = appSignature.err.split(separator: "\n").contains { $0 == "Signature=adhoc" }
for code in signedCode {
    let name = code.lastPathComponent
    let details = code == appURL ? appSignature : run("/usr/bin/codesign", ["-d", "--verbose=2", code.path])
    require(details.status == 0, "\(name) is not signed")
    if !adHoc {
        // "CodeDirectory v=… flags=0x10000(runtime) …": 0x10000 is the hardened runtime.
        let flags = details.err.split(whereSeparator: { $0 == "\n" || $0 == " " })
            .first { $0.hasPrefix("flags=0x") }
            .flatMap { UInt32($0.dropFirst("flags=0x".count).prefix { $0.isHexDigit }, radix: 16) }
        require(flags.map { $0 & 0x10000 != 0 } == true, "\(name) is not signed with the hardened runtime")
    }
    let entitlements = run("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", code.path])
    require(entitlements.status == 0, "cannot read the entitlements of \(name)")
    if !entitlements.out.isEmpty {
        guard let plist = try? PropertyListSerialization.propertyList(from: entitlements.out, format: nil) as? [String: Any] else {
            fail("unreadable entitlements in \(name)")
        }
        for key in forbiddenEntitlements where plist[key] != nil {
            fail("\(name) has the entitlement \(key)")
        }
    }
}

// The executable may only search the bundle and the system for libraries, never a path of the
// build machine such as its Xcode toolchain.
let otool = run("/usr/bin/otool", ["-l", appURL.appendingPathComponent("Contents/MacOS/Halodeck").path])
require(otool.status == 0, "otool could not read the executable")
let loadCommands = String(decoding: otool.out, as: UTF8.self)
var rpaths: [String] = []
var command = ""
for line in loadCommands.split(separator: "\n") {
    let text = line.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("cmd ") { command = String(text.dropFirst(4)) }
    if command == "LC_RPATH", text.hasPrefix("path "), let end = text.range(of: " (offset ", options: .backwards) {
        rpaths.append(String(text[text.index(text.startIndex, offsetBy: 5)..<end.lowerBound]))
    }
}
require(rpaths.contains("@executable_path/../Frameworks"), "the executable cannot find Sparkle.framework")
for rpath in rpaths {
    let allowed = ["@executable_path", "@loader_path", "/usr/lib"].contains { rpath == $0 || rpath.hasPrefix($0 + "/") }
    require(allowed, "unexpected rpath outside the bundle and the system: \(rpath)")
}
print("BUNDLE_CHECK_PASSED: \(string("CFBundleShortVersionString") ?? "?") (\(string("CFBundleVersion") ?? "?"))"
      + (adHoc ? ", ad hoc: hardened runtime not checked" : ""))
