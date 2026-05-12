import SwiftUI
import AppKit

@main
struct ToolboxApp: App {
    @StateObject private var viewModel = RootViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                .background(WindowConfigurator())
                .frame(minWidth: 420, minHeight: 280)
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 720, height: 480))
            context.coordinator.installDoubleClickZoomHandler(for: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var didInstall = false
        private var monitor: Any?

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
    }
}
