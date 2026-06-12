import SwiftUI
import AppKit

@main
struct ToolboxApp: App {
    @StateObject private var viewModel = RootViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                .background(WindowConfigurator(viewModel: viewModel))
                .frame(minWidth: 420, minHeight: 280)
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    private static let defaultSize = NSSize(width: 1152, height: 768)
    @ObservedObject var viewModel: RootViewModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.setContentSize(Self.defaultSize)
            let frame = NSRect(origin: window.frame.origin, size: Self.defaultSize)
            window.setFrame(frame, display: true)
            window.center()
            context.coordinator.installDoubleClickZoomHandler(for: window)
            context.coordinator.installSidebarButton(for: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateSidebarButton()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var viewModel: RootViewModel?
        private var didInstall = false
        private var monitor: Any?
        private weak var window: NSWindow?
        private weak var sidebarButton: NSButton?

        init(viewModel: RootViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func installDoubleClickZoomHandler(for window: NSWindow) {
            guard !didInstall else { return }
            didInstall = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak window] event in
                guard event.clickCount == 2, let window else { return event }
                let location = window.mouseLocationOutsideOfEventStream
                if location.y >= window.frame.height - 48 {
                    window.performZoom(nil)
                }
                return event
            }
        }

        func installSidebarButton(for window: NSWindow) {
            self.window = window
            guard sidebarButton == nil,
                  let titlebarView = window.standardWindowButton(.closeButton)?.superview else { return }

            let button = NSButton()
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.target = self
            button.action = #selector(toggleSidebar)
            button.toolTip = "显示/隐藏侧边栏"
            button.imagePosition = .imageOnly
            button.contentTintColor = NSColor.white.withAlphaComponent(0.9)
            titlebarView.addSubview(button)
            sidebarButton = button
            updateSidebarButton()
        }

        func updateSidebarButton() {
            guard let button = sidebarButton,
                  let window,
                  let titlebarView = window.standardWindowButton(.closeButton)?.superview else { return }

            let imageName = viewModel?.isSidebarVisible == true ? "sidebar.left" : "sidebar.right"
            button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)

            let y: CGFloat
            if let zoomButton = window.standardWindowButton(.zoomButton) {
                y = zoomButton.frame.midY - 8
            } else {
                y = max(4, (titlebarView.bounds.height - 16) / 2)
            }
            button.frame = NSRect(x: 142, y: y, width: 18, height: 18)
        }

        @objc private func toggleSidebar() {
            viewModel?.toggleSidebarVisibility()
            updateSidebarButton()
        }
    }
}
