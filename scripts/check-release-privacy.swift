#!/usr/bin/env swift
import Foundation

// Scans every regular file of the final app for paths of this machine and for key files. Only
// file names and the kind of issue are reported, never contents.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/check-release-privacy.swift /path/to/Halodeck.app\n", stderr)
    exit(1)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
    fputs("Privacy check failed: app directory is missing.\n", stderr)
    exit(1)
}
// Build-machine toolchain paths (an Xcode rpath, say) count too: Sparkle 2.10.1 contains none.
let needles = ["/Users/", "/home/", "/private/var/folders/", "/var/folders/",
               "/Applications/Xcode", "/Library/Developer/",
               FileManager.default.homeDirectoryForCurrentUser.path + "/"].map { Data($0.utf8) }
var scanned = 0
var issues: [String] = []
for case let file as URL in enumerator {
    guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
    scanned += 1
    let name = file.lastPathComponent
    if name == ".env" || name.hasPrefix(".env.") || ["p8", "p12", "mobileprovision"].contains(file.pathExtension) {
        issues.append("private configuration or key file: \(name)")
    }
    guard let data = try? Data(contentsOf: file) else { issues.append("unreadable: \(name)"); continue }
    if needles.contains(where: { data.range(of: $0) != nil }) { issues.append("local path in: \(name)") }
}
guard scanned > 0, issues.isEmpty else {
    for issue in issues { fputs("Privacy check failed: \(issue)\n", stderr) }
    if scanned == 0 { fputs("Privacy check failed: app directory is empty.\n", stderr) }
    exit(1)
}
print("PRIVACY_CHECK_PASSED: \(scanned) app files")
