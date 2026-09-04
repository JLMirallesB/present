import SwiftUI
import Combine
import UniformTypeIdentifiers

@main
struct PresentApp: App {
    @State private var state: PresentationState
    @State private var presentationController = PresentationWindowController()
    @State private var server: RemoteServer

    init() {
        let s = PresentationState()
        let srv = RemoteServer()
        srv.start(state: s)
        _state = State(initialValue: s)
        _server = State(initialValue: srv)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(state: state, server: server)
                .onReceive(NotificationCenter.default.publisher(for: .remotePlay)) { _ in
                    if !state.isPresenting {
                        presentationController.open(state: state)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .remoteStop)) { _ in
                    if state.isPresenting {
                        presentationController.close(state: state)
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Open...") {
                    FileDialogHelper.open(state: state)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save") {
                    FileDialogHelper.save(state: state)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(state.slides.isEmpty)

                Button("Save As...") {
                    FileDialogHelper.saveAs(state: state)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state.slides.isEmpty)
            }

            CommandMenu("View") {
                Button("Zoom In") {
                    state.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    state.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    state.zoomReset()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("Presentation") {
                Button("Play") {
                    presentationController.open(state: state)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(state.slides.isEmpty)

                if PresentationWindowController.availableScreens.count > 1 {
                    Menu("Display") {
                        ForEach(Array(PresentationWindowController.availableScreens.enumerated()), id: \.offset) { index, screen in
                            Button {
                                state.preferredScreenIndex = index
                            } label: {
                                let current = state.preferredScreenIndex ?? PresentationWindowController.availableScreens.firstIndex(where: { $0 == NSScreen.main }) ?? 0
                                Text("\(index + 1). \(screen.localizedName)" + (index == current ? " ✓" : ""))
                            }
                        }
                    }
                }

                Divider()

                Button("Remote Control...") {
                    NotificationCenter.default.post(name: .showRemoteInfo, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

enum FileDialogHelper {
    @MainActor
    static func open(state: PresentationState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Open a presentation list"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !state.loadFromFile(url) {
            presentError("Could not open \(url.lastPathComponent)",
                         detail: "The file is empty, or not a presentation list.")
        }
    }

    /// Writes straight back to the file the list came from. With no such file
    /// yet — a list built in the app — it falls through to Save As.
    @MainActor
    static func save(state: PresentationState) {
        guard let url = state.currentFileURL else {
            saveAs(state: state)
            return
        }
        guard !state.fileIsStale || shouldOverwriteChangedFile(state: state, url: url) else { return }
        if !state.saveToFile(url) {
            presentError("Could not save \(url.lastPathComponent)",
                         detail: "The file could not be written. Try Save As.")
        }
    }

    @MainActor
    static func saveAs(state: PresentationState) {
        let panel = NSSavePanel()
        // JSON first: it is the lossless one, so it is the default.
        panel.allowedContentTypes = [.json, .plainText]
        panel.nameFieldStringValue = (state.currentSet?.name ?? "presentation") + ".json"
        panel.message = "JSON keeps display names. Plain text is interchangeable with other forks of Present."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !state.saveToFile(url) {
            presentError("Could not save \(url.lastPathComponent)",
                         detail: "The file could not be written.")
        }
    }

    /// Somebody else has written to the file since we last read it. Saving now
    /// would throw their work away without a word, so ask first. The watcher
    /// handles this in the ordinary case; this is the backstop for when it did
    /// not — the list had unsaved edits, or the change landed mid-presentation.
    @MainActor
    private static func shouldOverwriteChangedFile(state: PresentationState, url: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(url.lastPathComponent) has changed on disk"
        alert.informativeText = "Something else has written to this file since you opened it. "
            + "Saving replaces what is there now; reloading discards the changes you have made here."
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            state.reloadFromFile()
            return false
        default:
            return false
        }
    }

    @MainActor
    private static func presentError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
