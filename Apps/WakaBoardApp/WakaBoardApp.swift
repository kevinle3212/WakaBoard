import SwiftUI
import WakaCore
import WakaUI

/// The application entry point.
///
/// Owns the single ``WakaUIModel`` so the macOS menu command and the window's
/// views drive the same state. The generated version created its model inside the
/// view and left the menu's Refresh item wired to an empty closure.
@main
struct WakaBoardApp: App {
    @State private var model = WakaUIModel(environment: .live())

    var body: some Scene {
        WindowGroup {
            WakaShellView(model: model)
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Refresh Analytics") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isBusy)
            }
        }
    }
}
