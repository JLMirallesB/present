import SwiftUI
import AppKit

struct PresentationView: View {
    @Bindable var state: PresentationState

    var body: some View {
        ZStack {
            Color.black

            if let slide = state.currentSlide {
                WebView(
                    content: slide.content,
                    neighbours: state.neighbourContents,
                    pageZoom: state.zoomLevel
                )
                .opacity(state.isBlackedOut ? 0 : 1)
            } else {
                Text("No slides")
                    .foregroundStyle(.white)
                    .font(.largeTitle)
            }

            if !state.slides.isEmpty && !state.isBlackedOut {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(state.currentIndex + 1) / \(state.slides.count)")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5))
                            .foregroundStyle(.white.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(12)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class PresentationWindowController {
    private var window: NSWindow?
    private var monitor: Any?

    /// The screens the presentation can go on, in the order macOS reports them.
    static var availableScreens: [NSScreen] { NSScreen.screens }

    private static func screen(for state: PresentationState) -> NSScreen? {
        let screens = availableScreens
        if let index = state.preferredScreenIndex, screens.indices.contains(index) {
            return screens[index]
        }
        return NSScreen.main ?? screens.first
    }

    func open(state: PresentationState) {
        guard window == nil else { return }

        state.isBlackedOut = false
        let screen = Self.screen(for: state)
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = NSHostingView(rootView: PresentationView(state: state))
        window.level = .statusBar
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        // Place it on the chosen screen before going fullscreen, or macOS
        // fullscreens it wherever the window happened to be.
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)

        self.window = window

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let command = PresentationKeymap.command(
                for: event.keyCode, modifiers: event.modifierFlags
            ) else {
                return event
            }
            self?.perform(command, state: state)
            return nil
        }

        state.isPresenting = true
    }

    private func perform(_ command: PresentationCommand, state: PresentationState) {
        switch command {
        case .next:
            state.goToNext()
        case .previous:
            state.goToPrevious()
        case .first:
            state.currentIndex = 0
        case .last:
            state.currentIndex = max(0, state.slides.count - 1)
        case .exit:
            // Un-blank first: Escape on a blacked-out screen most likely means
            // "show the slide again", not "end the talk".
            if state.isBlackedOut {
                state.isBlackedOut = false
            } else {
                close(state: state)
            }
        case .zoomIn:
            state.zoomIn()
        case .zoomOut:
            state.zoomOut()
        case .zoomReset:
            state.zoomReset()
        case .toggleBlackout:
            state.isBlackedOut.toggle()
        }
    }

    func close(state: PresentationState) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        window?.close()
        window = nil
        state.isPresenting = false
        state.isBlackedOut = false
    }
}
