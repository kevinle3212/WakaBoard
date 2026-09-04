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
        #if os(macOS)
        // A sensible opening size, and a window that cannot be dragged smaller than
        // its content needs — without this the split view clips the detail pane.
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentSize)
        #endif
        // A menu bar and hardware keyboard shortcuts exist on the Mac, on iPad, and
        // in the Vision Pro's shared space. A watch and a television have neither, and
        // `commands` is not available there at all.
        #if os(macOS) || os(iOS) || os(visionOS)
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
        #endif
    }
}
