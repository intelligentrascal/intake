// axdrive — drive ONE macOS process by PID through the Accessibility API.
//
// Why not `osascript … System Events`: System Events re-resolves a process
// reference by *name*, and the verification build and the captain's installed
// app are both named "Intake". A System Events click aimed at the verification
// PID can land on the installed app. Everything here is bound to the PID.
//
// Built by scripts/build.sh into $VERIFY_ROOT/bin/axdrive. Usage: axdrive <pid> <command> [args]
//   windows                      list AX windows: title | frame | CGWindowID (empty while the Mac is locked)
//   cgwindows [all]              on-screen WindowServer windows of the pid: id | title | frame (works while locked; "all" adds hidden ones)
//   tree [maxDepth]              dump the AX tree of every window (role, title, description, value)
//   extra-items                  list the menu bar extra (status item) menu items
//   extra-press <title>          press a menu item of the menu bar extra by exact title
//   menu-press <menu> <item>     press a main-menu item, e.g. menu-press Intake "Settings…"
//   press <title-or-label>       press the first button/menu item/row whose title or description matches exactly
//   wait-window <title> [secs]   wait until a window with this exact title exists (exit 1 on timeout)
//   wait-text <text> [secs]      wait until any AX element's title/value/description contains text
//   value-of <label>             print the AXValue of the first text field whose title/description/placeholder matches
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func fail(_ msg: String, _ code: Int32 = 2) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else {
    fail("usage: axdrive <pid> <windows|tree|extra-items|extra-press|menu-press|press|wait-window|wait-text|value-of> [args]")
}
guard AXIsProcessTrusted() else {
    fail("axdrive: Accessibility permission missing for the process running this command (System Settings > Privacy & Security > Accessibility).", 3)
}
guard kill(pid, 0) == 0 else { fail("axdrive: pid \(pid) is not running", 4) }
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 5)

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
    return v
}
func str(_ el: AXUIElement, _ name: String) -> String {
    guard let v = attr(el, name) else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}
func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}
func label(_ el: AXUIElement) -> String {
    let t = str(el, kAXTitleAttribute)
    return t.isEmpty ? str(el, kAXDescriptionAttribute) : t
}
func frame(_ el: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    if let pv = attr(el, kAXPositionAttribute) { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
    if let sv = attr(el, kAXSizeAttribute) { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}
/// AXWindows can come back short (e.g. only the zero-size bridge window) while
/// the Mac is locked; the app element's children carry every AXWindow, so merge both.
func windows() -> [AXUIElement] {
    var out = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    for c in children(app) where str(c, kAXRoleAttribute) == "AXWindow" && !out.contains(where: { CFEqual($0, c) }) {
        out.append(c)
    }
    // While the console is locked, AXWindows returns stub elements whose role is
    // AXApplication. Those are not windows; drop them so callers see "no windows".
    return out.filter { str($0, kAXRoleAttribute) == "AXWindow" }
}
func walk(_ el: AXUIElement, depth: Int = 0, max: Int = 40, _ visit: (AXUIElement, Int) -> Bool) -> Bool {
    if visit(el, depth) { return true }
    guard depth < max else { return false }
    for c in children(el) where walk(c, depth: depth + 1, max: max, visit) { return true }
    return false
}
func press(_ el: AXUIElement) {
    let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
    if r != .success { fail("axdrive: AXPress failed (\(r.rawValue))", 5) }
}
/// Normal-layer WindowServer windows of the pid. `onscreenOnly` drops windows
/// that exist but are hidden (e.g. the Activity window SwiftUI creates and
/// hides at launch).
func cgWindowIDs(onscreenOnly: Bool = false) -> [(Int, String, CGRect)] {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
              (info[kCGWindowLayer as String] as? Int) == 0,
              !onscreenOnly || (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              let id = info[kCGWindowNumber as String] as? Int else { return nil }
        let b = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        return (id, info[kCGWindowName as String] as? String ?? "", rect)
    }
}
func extra() -> AXUIElement {
    guard let bar = attr(app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
        fail("axdrive: pid \(pid) has no menu bar extra (Show in menu bar off?)", 6)
    }
    guard let item = children(bar as! AXUIElement).first else { fail("axdrive: empty extras menu bar", 6) }
    return item
}
func menuItems(of item: AXUIElement) -> [AXUIElement] {
    guard let menu = children(item).first else { return [] }
    return children(menu)
}
func waitUntil(_ secs: Double, _ cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(secs)
    repeat {
        if cond() { return true }
        usleep(250_000)
    } while Date() < end
    return false
}

let cmd = args[2]
let rest = Array(args.dropFirst(3))
switch cmd {
case "windows":
    let ids = cgWindowIDs()
    for w in windows() {
        let f = frame(w)
        let match = ids.first { abs($0.2.origin.x - f.origin.x) < 2 && abs($0.2.origin.y - f.origin.y) < 2 && abs($0.2.width - f.width) < 2 }
        print("\(str(w, kAXTitleAttribute)) | \(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height)) | cgwindow=\(match.map { String($0.0) } ?? "?")")
    }
case "cgwindows":
    // Only windows the user can see; pass "all" to include hidden ones.
    for (id, name, r) in cgWindowIDs(onscreenOnly: rest.first != "all") {
        print("\(id) | \(name) | \(Int(r.origin.x)),\(Int(r.origin.y)) \(Int(r.width))x\(Int(r.height))")
    }
case "tree":
    let maxDepth = Int(rest.first ?? "") ?? 25
    for w in windows() {
        _ = walk(w, max: maxDepth) { el, d in
            let role = str(el, kAXRoleAttribute)
            let parts = [("title", str(el, kAXTitleAttribute)), ("desc", str(el, kAXDescriptionAttribute)),
                         ("value", str(el, kAXValueAttribute)), ("id", str(el, kAXIdentifierAttribute))]
                .filter { !$0.1.isEmpty }.map { "\($0.0)=\"\($0.1.prefix(160))\"" }.joined(separator: " ")
            print(String(repeating: "  ", count: d) + role + (parts.isEmpty ? "" : " " + parts))
            return false
        }
    }
case "extra-items":
    let item = extra()
    print("status item: \(label(item))")
    for m in menuItems(of: item) {
        let enabled = (attr(m, kAXEnabledAttribute) as? Bool) ?? false
        print("  [\(str(m, kAXTitleAttribute))]\(enabled ? "" : " (disabled)")")
    }
case "extra-press":
    guard let title = rest.first else { fail("extra-press <title>") }
    let item = extra()
    guard let m = menuItems(of: item).first(where: { str($0, kAXTitleAttribute) == title }) else {
        fail("axdrive: no menu bar extra item titled \"\(title)\"", 7)
    }
    press(m)
    print("pressed extra item: \(title)")
case "menu-press":
    guard rest.count == 2 else { fail("menu-press <menu> <item>") }
    guard let bar = attr(app, kAXMenuBarAttribute) else { fail("axdrive: no main menu bar", 6) }
    guard let top = children(bar as! AXUIElement).first(where: { str($0, kAXTitleAttribute) == rest[0] }) else {
        fail("axdrive: no main menu \"\(rest[0])\"", 7)
    }
    guard let m = menuItems(of: top).first(where: { str($0, kAXTitleAttribute) == rest[1] }) else {
        fail("axdrive: no item \"\(rest[1])\" in menu \"\(rest[0])\"", 7)
    }
    press(m)
    print("pressed menu: \(rest[0]) > \(rest[1])")
case "press":
    guard let target = rest.first else { fail("press <title-or-label>") }
    var found: AXUIElement?
    for w in windows() {
        if walk(w, { el, _ in
            let role = str(el, kAXRoleAttribute)
            guard ["AXButton", "AXMenuItem", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXRow", "AXCell", "AXDisclosureTriangle"].contains(role) else { return false }
            if str(el, kAXTitleAttribute) == target || str(el, kAXDescriptionAttribute) == target { found = el; return true }
            return false
        }) { break }
    }
    guard let el = found else { fail("axdrive: nothing pressable labelled \"\(target)\"", 7) }
    press(el)
    print("pressed: \(target)")
case "wait-window":
    guard let title = rest.first else { fail("wait-window <title> [secs]") }
    let secs = Double(rest.dropFirst().first ?? "") ?? 10
    if waitUntil(secs, { windows().contains { str($0, kAXTitleAttribute) == title } }) { print("window present: \(title)") }
    else { fail("axdrive: timed out waiting for window \"\(title)\"", 1) }
case "wait-text":
    guard let text = rest.first else { fail("wait-text <text> [secs]") }
    let secs = Double(rest.dropFirst().first ?? "") ?? 10
    let ok = waitUntil(secs) {
        windows().contains { w in walk(w) { el, _ in
            [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].contains { str(el, $0).contains(text) }
        } }
    }
    if ok { print("text present: \(text)") } else { fail("axdrive: timed out waiting for text \"\(text)\"", 1) }
case "value-of":
    guard let target = rest.first else { fail("value-of <label>") }
    var found: AXUIElement?
    for w in windows() {
        if walk(w, { el, _ in
            guard str(el, kAXRoleAttribute) == "AXTextField" else { return false }
            if [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute].contains(where: { str(el, $0) == target }) { found = el; return true }
            return false
        }) { break }
    }
    guard let el = found else { fail("axdrive: no text field labelled \"\(target)\"", 7) }
    print("value=\"\(str(el, kAXValueAttribute))\" placeholder=\"\(str(el, kAXPlaceholderValueAttribute))\" enabled=\((attr(el, kAXEnabledAttribute) as? Bool) ?? false)")
default:
    fail("axdrive: unknown command \(cmd)")
}
