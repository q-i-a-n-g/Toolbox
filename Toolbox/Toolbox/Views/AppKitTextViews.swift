import SwiftUI
import AppKit

private let largeTextContainerHeight: CGFloat = 10_000_000
private let largeTextContainerWidth: CGFloat = 10_000_000

struct PlainTextEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = PlainTextNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        textView.allowsUndo = true
        textView.font = NSFont.userFixedPitchFont(ofSize: 13)
        textView.textColor = NSColor(calibratedWhite: 0.88, alpha: 1.0)
        textView.string = text
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 10
        textView.textContainerInset = NSSize(width: 0, height: 10)
        
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PlainTextNSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
            textView.isSelectable = true
        }

        if isFocused {
            DispatchQueue.main.async {
                if textView.window?.firstResponder != textView {
                    textView.window?.makeFirstResponder(textView)
                }
                isFocused = false
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

struct TerminalTextView: NSViewRepresentable {
    let outputText: String
    @Binding var isFocused: Bool
    let onInput: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = false
        scrollView.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)

        let textView = makeConfiguredTerminalTextView()
        textView.inputHandler = context.coordinator.handleInput
        textView.registerForDraggedTypes([.fileURL])
        scrollView.documentView = textView

        return scrollView
    }

    private func makeConfiguredTerminalTextView() -> TerminalNSTextView {
        let textView = TerminalNSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = NSFont.userFixedPitchFont(ofSize: 13)
        textView.textColor = NSColor(calibratedRed: 0.63, green: 0.95, blue: 0.66, alpha: 1.0)
        textView.string = outputText
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 12
        textView.textContainerInset = NSSize(width: 0, height: 12)
        
        textView.textContainer?.containerSize = NSSize(
            width: largeTextContainerWidth,
            height: largeTextContainerHeight
        )
        return textView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TerminalNSTextView else { return }
        if textView.string != outputText {
            textView.string = outputText
            DispatchQueue.main.async {
                textView.scrollToEndOfDocument(nil)
                let length = (outputText as NSString).length
                if length > 0 {
                    textView.scrollRangeToVisible(NSRange(location: length, length: 0))
                }
            }
        }

        if isFocused {
            DispatchQueue.main.async {
                if textView.window?.firstResponder != textView {
                    textView.window?.makeFirstResponder(textView)
                }
                isFocused = false
            }
        }
    }

    final class Coordinator: NSObject {
        var onInput: (String) -> Void
        init(onInput: @escaping (String) -> Void) {
            self.onInput = onInput
        }
        func handleInput(_ text: String) {
            onInput(text)
        }
    }
}

final class PlainTextNSTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
}

final class TerminalNSTextView: NSTextView {
    var inputHandler: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Enter
            inputHandler?("\n")
            return
        }
        if let chars = event.charactersIgnoringModifiers {
            inputHandler?(chars)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.types?.contains(.fileURL) == true {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.types?.contains(.fileURL) == true {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if pboard.types?.contains(.fileURL) == true {
            return true
        }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let paths = urls.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
            if !paths.isEmpty {
                inputHandler?(paths + " ")
                self.window?.makeFirstResponder(self)
                return true
            }
        }
        return super.performDragOperation(sender)
    }
}
