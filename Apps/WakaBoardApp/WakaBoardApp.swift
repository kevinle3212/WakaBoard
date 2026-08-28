import SwiftUI
import WakaUI

@main struct WakaBoardApp: App {
    var body: some Scene { WindowGroup { WakaShellView() }.commands { CommandGroup(after: .textEditing) { Divider(); Button("Refresh Analytics") {}.keyboardShortcut("r", modifiers: [.command]) } } }
}
