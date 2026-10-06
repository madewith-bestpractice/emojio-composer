import CoreGraphics
// Prints the window number of the first on-screen, normal-layer window whose
// owner name contains the argument (case-insensitive).
let want = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].lowercased() : "emojio"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    let owner = (w[kCGWindowOwnerName as String] as? String ?? "").lowercased()
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    if owner.contains(want) && layer == 0, let n = w[kCGWindowNumber as String] as? Int {
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        print(n, b["Width"] ?? 0, b["Height"] ?? 0)
        break
    }
}
