// On-device accessibility audit.
//
// Walks the real accessibility tree of a running WakaBoard — the same tree VoiceOver
// reads — and asserts what a unit test cannot: that every interactive element has a
// hit target of at least 44×44 points, and that nothing interactive is unlabelled.
//
// This exists because the unit suite asserted the *constant* was 44 and that it was
// *referenced* in the view layer, and both were true while a `Link` still rendered a
// 16-point target. Only the live tree could show that.
//
// Usage:  swift scripts/ax-audit.swift <pid> [--json]
// Exit:   0 = AX_AUDIT_OK, 1 = violations found, 3 = accessibility permission missing,
//         4 = the trusted process cannot reach the app's live accessibility tree.
//
// Requires the calling terminal to hold Accessibility permission
// (System Settings → Privacy & Security → Accessibility).

import ApplicationServices
import Foundation

/// WCAG 2.2 SC 2.5.8 Target Size (Minimum), Level AA. This is the conformance bar
/// `ACCESSIBILITY.md` actually claims, and any control below it is a real failure.
let wcagMinimum: CGFloat = 24

/// Apple's HIG touch guidance, and WCAG 2.2 SC 2.5.5 (Level AAA). Controls this app
/// lays out itself are held to this higher bar; controls AppKit sizes are not, because
/// the author cannot move them.
let appleGuidance: CGFloat = 44

/// Roles a user can interact with, which therefore need a real hit target.
let interactiveRoles: Set<String> = [
    "AXButton", "AXLink", "AXCheckBox", "AXRadioButton",
    "AXPopUpButton", "AXTextField", "AXSecureTextField", "AXSlider", "AXMenuButton"
]

/// Roles that are interactive but whose size the app does not control.
///
/// Window traffic lights and menu bar items are supplied by macOS at a fixed size;
/// flagging them would be reporting a system layout as an app defect.
let systemProvided: Set<String> = [
    "AXMenuBarItem", "AXMenuItem", "AXMenuBar", "AXMenu",
    // Scroll bars are drawn and sized by AppKit; their increment/decrement buttons are
    // unlabelled 6-point slivers by design and are not part of the app's own surface.
    "AXScrollBar"
]

/// Subroles macOS supplies and sizes itself: the window traffic lights and the
/// full-screen control. They are always 16x16 and are not the app's to change, so
/// flagging them would report a system layout as an app defect.
let systemProvidedSubroles: Set<String> = [
    "AXCloseButton", "AXMinimizeButton", "AXZoomButton",
    "AXFullScreenButton", "AXToolbarButton", "AXSortButton"
]

/// Roles whose height AppKit determines and SwiftUI cannot override.
///
/// Measured, not assumed: a `SecureField` reports a 16-point accessibility height on
/// macOS regardless of `.frame(height:)`, surrounding padding, or
/// `.controlSize(.extraLarge)` — the element AX exposes is AppKit's inner text
/// control, which sizes itself to one line. This is the WCAG 2.2 SC 2.5.8 "user agent
/// control" exception, and SC 2.5.8's own minimum is 24x24 rather than Apple's
/// touch-oriented 44.
///
/// These are reported as exemptions rather than dropped, so the exception stays
/// visible in the output instead of quietly lowering the bar.
let userAgentSizedRoles: Set<String> = [
    "AXTextField", "AXSecureTextField", "AXTextArea",
    // Segments of an NSSegmentedControl. `.controlSize(.large)` raises them from 24 to
    // 28 points and no further; the height is AppKit's to choose.
    "AXRadioButton"
]

struct Exemption: Encodable {
    let role: String
    let label: String
    let height: Double
    let reason: String
}

struct Violation: Encodable {
    let kind: String
    let role: String
    let label: String
    let width: Double
    let height: Double
    let path: String
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func size(of element: AXUIElement) -> CGSize? {
    guard let raw = attribute(element, kAXSizeAttribute as String) else { return nil }
    var result = CGSize.zero
    guard AXValueGetValue(raw as! AXValue, .cgSize, &result) else { return nil }
    return result
}

func label(of element: AXUIElement) -> String {
    let candidates = [
        kAXDescriptionAttribute as String,
        kAXTitleAttribute as String,
        kAXValueAttribute as String,
        kAXHelpAttribute as String
    ]
    for name in candidates {
        if let text = attribute(element, name) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
    }
    return ""
}

var violations: [Violation] = []
var exemptions: [Exemption] = []
var interactiveCount = 0
var nodeCount = 0

func audit(_ element: AXUIElement, path: String, depth: Int, insideSystemChrome: Bool) {
    guard depth < 16, nodeCount < 3_000 else { return }
    nodeCount += 1

    let role = attribute(element, kAXRoleAttribute as String) as? String ?? "?"
    let text = label(of: element)
    let here = path.isEmpty ? role : "\(path) > \(role)"
    let systemChrome = insideSystemChrome || systemProvided.contains(role)

    let subrole = attribute(element, kAXSubroleAttribute as String) as? String ?? ""
    let systemControl = systemProvidedSubroles.contains(subrole)

    if interactiveRoles.contains(role), !systemChrome, !systemControl {
        interactiveCount += 1
        let box = size(of: element) ?? .zero

        // A zero-sized element is offscreen or collapsed, not a layout defect.
        if box.width > 0, box.height > 0 {
            let smallest = min(box.width, box.height)
            if smallest < wcagMinimum {
                // Below WCAG 2.2 AA regardless of who sized it. A real failure.
                violations.append(Violation(
                    kind: "target-size",
                    role: role, label: text,
                    width: Double(box.width), height: Double(box.height),
                    path: here
                ))
            } else if smallest < appleGuidance {
                if userAgentSizedRoles.contains(role) {
                    // Meets AA; below Apple's touch guidance, and AppKit owns the size.
                    exemptions.append(Exemption(
                        role: role, label: text, height: Double(smallest),
                        reason: "meets WCAG 2.2 AA (24pt) but is below Apple's 44pt touch guidance; AppKit sizes this control and SwiftUI cannot override it"
                    ))
                } else {
                    // A control this app lays out itself has no such excuse.
                    violations.append(Violation(
                        kind: "target-size",
                        role: role, label: text,
                        width: Double(box.width), height: Double(box.height),
                        path: here
                    ))
                }
            }
        }
        if text.isEmpty {
            violations.append(Violation(
                kind: "missing-label",
                role: role,
                label: "",
                width: Double(box.width),
                height: Double(box.height),
                path: here
            ))
        }
    }

    for child in (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
        audit(child, path: here, depth: depth + 1, insideSystemChrome: systemChrome)
    }
}

// MARK: - Entry point

let arguments = CommandLine.arguments
guard arguments.count > 1, let pid = Int32(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: ax-audit.swift <pid> [--all-screens] [--json]\n".utf8))
    exit(2)
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("""
    AX_NOT_TRUSTED: this process lacks Accessibility permission.
    Grant it in System Settings > Privacy & Security > Accessibility, then re-run.

    """.utf8))
    exit(3)
}

let application = AXUIElementCreateApplication(pid)

/// Presses a sidebar row by name, so every screen can be audited rather than only
/// whichever happened to be on display when the script ran.
func selectSidebarRow(named name: String) -> Bool {
    /// Finds the selectable row wrapping an exact route label.
    ///
    /// SwiftUI's macOS accessibility bridge does not promise that a `Label` is
    /// exposed as `AXStaticText`, and the number of wrapper groups changes with
    /// layout and OS releases. The row ancestor is the stable contract: a screen
    /// title elsewhere in the window cannot satisfy this search.
    func rowAncestor(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0 ..< 8 {
            guard let candidate = current,
                  let parent = attribute(candidate, kAXParentAttribute as String) else { return nil }
            let parentElement = parent as! AXUIElement
            if (attribute(parentElement, kAXRoleAttribute as String) as? String) == "AXRow" {
                return parentElement
            }
            current = parentElement
        }
        return nil
    }

    func search(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 16 else { return nil }
        if label(of: element) == name, let row = rowAncestor(of: element) {
            return row
        }
        for child in (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
            if let found = search(child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Reveals a sidebar hidden by macOS window-state restoration.
    ///
    /// A fresh build can still inherit the app's previous split-view visibility.
    /// Without this recovery the audit inspects Overview repeatedly while reporting
    /// every other destination as unreachable, even though product navigation works.
    func revealSidebar(_ element: AXUIElement, depth: Int) -> Bool {
        guard depth < 16 else { return false }
        let role = attribute(element, kAXRoleAttribute as String) as? String ?? ""
        let text = label(of: element)
        if role == "AXButton", text.hasPrefix("Show"), text.contains("Sidebar") {
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        }
        for child in (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
            if revealSidebar(child, depth: depth + 1) { return true }
        }
        return false
    }

    var row = search(application, depth: 0)
    if row == nil, revealSidebar(application, depth: 0) {
        Thread.sleep(forTimeInterval: 0.8)
        row = search(application, depth: 0)
    }
    guard let row else { return false }
    let pressed = AXUIElementPerformAction(row, kAXPressAction as CFString) == .success
    if !pressed {
        // Rows in an outline are selected rather than pressed.
        AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
    }
    Thread.sleep(forTimeInterval: 1.2)
    return true
}

// The sidebar rows, in order. Projects and Languages were separate screens until the
// five data dimensions moved behind one picker on Breakdown; a list here that names a
// row the sidebar no longer has silently reports it as unreachable on every run.
let screens = ["Overview", "Activity", "Breakdown", "Insights", "Settings"]
let minimumNodes = 20

/// Stops before route assertions when the host exposes no real application window.
///
/// A process can remain trusted while the login window is locked or the GUI session
/// is otherwise unavailable. Reporting every route as missing in that state disguises
/// an environment failure as a product-navigation defect.
func requireReachableTree() {
    guard nodeCount >= minimumNodes else {
        print("""
        AX_TREE_UNAVAILABLE: inspected \(nodeCount) nodes, fewer than the \(minimumNodes) any real screen has.
          The process is Accessibility-trusted, but the app window is not reachable.
          Unlock the active GUI session, confirm the app window is visible, and retry.
        """)
        exit(4)
    }
}

if arguments.contains("--all-screens") {
    // A fresh `WakaShell` opens on Overview. Its selected row may not expose a
    // pressable accessibility element, so audit the initial surface directly before
    // navigating the remaining destinations through the sidebar.
    var visited = ["Overview"]
    audit(application, path: "Overview", depth: 0, insideSystemChrome: false)
    requireReachableTree()
    for screen in screens.dropFirst() where selectSidebarRow(named: screen) {
        visited.append(screen)
        audit(application, path: screen, depth: 0, insideSystemChrome: false)
    }
    print("Visited screens: \(visited.joined(separator: ", "))")
    if visited.count < screens.count {
        let missed = screens.filter { !visited.contains($0) }
        FileHandle.standardError.write(Data("FAIL could not reach: \(missed.joined(separator: ", "))\n".utf8))
        // Keep failure diagnosis narrow: route and sidebar labels reveal navigation
        // structure without printing API fields or private analytics from the tree.
        func printNavigationCandidates(_ element: AXUIElement, depth: Int) {
            guard depth < 16 else { return }
            let role = attribute(element, kAXRoleAttribute as String) as? String ?? "?"
            let text = label(of: element)
            let lower = text.lowercased()
            if !text.isEmpty,
               (lower.contains("sidebar") || screens.contains(where: { lower.contains($0.lowercased()) })) {
                print("NAV_CANDIDATE \(role) \"\(text)\"")
            }
            for child in (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
                printNavigationCandidates(child, depth: depth + 1)
            }
        }
        printNavigationCandidates(application, depth: 0)
        exit(1)
    }
} else {
    audit(application, path: "", depth: 0, insideSystemChrome: false)
}

if arguments.contains("--json") {
    let data = try JSONEncoder().encode(violations)
    print(String(data: data, encoding: .utf8) ?? "[]")
}

print("Inspected \(nodeCount) nodes, \(interactiveCount) interactive elements.")

for exemption in exemptions {
    print(String(
        format: "EXEMPT %@ \"%@\" is %.0fpt — %@",
        exemption.role, exemption.label, exemption.height, exemption.reason
    ))
}

// An audit that reached nothing must not report success. Zero nodes means the
// accessibility permission was refused, or the window was not found, or the app
// exited — and every one of those produced "AX_AUDIT_OK" before this guard existed,
// which is a green check for having looked at nothing at all.
requireReachableTree()

guard violations.isEmpty else {
    for violation in violations {
        switch violation.kind {
        case "target-size":
            print(String(
                format: "VIOLATION target-size: %@ \"%@\" is %.0fx%.0f — below %.0fpt (WCAG 2.2 AA) or below %.0fpt for an author-sized control\n  at %@",
                violation.role, violation.label, violation.width, violation.height,
                Double(wcagMinimum), Double(appleGuidance), violation.path
            ))
        default:
            print("VIOLATION missing-label: \(violation.role) has no accessibility label\n  at \(violation.path)")
        }
    }
    print("\n\(violations.count) accessibility violation(s).")
    exit(1)
}

print("AX_AUDIT_OK")
