import SwiftUI
import AppKit

private let largeTextContainerHeight: CGFloat = 10_000_000
private let largeTextContainerWidth: CGFloat = 10_000_000

struct PlainTextEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let isEditable: Bool
    var trimTrailingBlankLinesOnPaste: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = PlainTextNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.trimTrailingBlankLinesOnPaste = trimTrailingBlankLinesOnPaste
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
        applyLeftAlignment(to: textView)
        
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PlainTextNSTextView else { return }

        if textView.string != text {
            textView.string = text
            applyLeftAlignment(to: textView)
        }
        textView.trimTrailingBlankLinesOnPaste = trimTrailingBlankLinesOnPaste

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

    private func applyLeftAlignment(to textView: NSTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        textView.defaultParagraphStyle = paragraph
        textView.alignment = .left
        textView.typingAttributes[.paragraphStyle] = paragraph
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        if fullRange.length > 0 {
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
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
        scrollView.hasHorizontalScroller = false
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
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = NSFont.userFixedPitchFont(ofSize: 13)
        textView.textColor = NSColor(calibratedRed: 0.63, green: 0.95, blue: 0.66, alpha: 1.0)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(calibratedRed: 0.70, green: 0.95, blue: 1.0, alpha: 1.0)
        ]
        textView.renderedSourceText = outputText
        textView.textStorage?.setAttributedString(attributedTerminalText(outputText))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 12
        textView.textContainerInset = NSSize(width: 0, height: 12)
        
        textView.textContainer?.containerSize = NSSize(
            width: largeTextContainerWidth,
            height: largeTextContainerHeight
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        textView.defaultParagraphStyle = paragraph
        textView.alignment = .left
        textView.typingAttributes[.paragraphStyle] = paragraph
        return textView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TerminalNSTextView else { return }
        if textView.renderedSourceText != outputText {
            textView.renderedSourceText = outputText
            textView.textStorage?.setAttributedString(attributedTerminalText(outputText))
            DispatchQueue.main.async {
                textView.scrollToEndOfDocument(nil)
                let length = (textView.string as NSString).length
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

    private func attributedTerminalText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let baseColor = NSColor(calibratedRed: 0.63, green: 0.95, blue: 0.66, alpha: 1.0)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.userFixedPitchFont(ofSize: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: baseColor,
                .paragraphStyle: paragraph
            ]
        )

        let nsText = text as NSString
        var links: [(range: NSRange, label: String, url: URL)] = []
        let patterns: [(String, Int)] = [
            (#"(^|[\s：:,，])((?:(?:Download|Downloads|Desktop)(?:/[^\n,，]*)?)|(?:doc/[^\n,，]+))"#, 2),
            (#"(file://[^\s,，]+)"#, 1)
        ]
        for (pattern, captureIndex) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let rawRange = match.range(at: captureIndex)
                guard rawRange.location != NSNotFound, rawRange.length > 0 else { continue }
                let rawLabel = nsText.substring(with: rawRange)
                let leadingWhitespace = rawLabel.prefix { $0.isWhitespace }.count
                let trailingWhitespace = rawLabel.reversed().prefix { $0.isWhitespace }.count
                let length = rawRange.length - leadingWhitespace - trailingWhitespace
                guard length > 0 else { continue }
                let linkRange = NSRange(location: rawRange.location + leadingWhitespace, length: length)
                let label = nsText.substring(with: linkRange)
                if let url = fileURL(forTerminalPath: label) {
                    links.append((linkRange, label, url))
                }
            }
        }

        let linkColor = NSColor(calibratedRed: 0.70, green: 0.95, blue: 1.0, alpha: 1.0)
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: linkColor
        ]
        for link in links.sorted(by: { $0.range.location > $1.range.location }) {
            let icon = linkIcon(label: link.label, url: link.url, color: linkColor)
            let iconLength = icon.length
            attributed.insert(icon, at: link.range.location)
            let iconRange = NSRange(location: link.range.location, length: iconLength)
            let shiftedLinkRange = NSRange(location: link.range.location + iconLength, length: link.range.length)
            attributed.addAttributes(linkAttributes.merging([.link: link.url]) { current, _ in current }, range: iconRange)
            attributed.addAttributes(linkAttributes.merging([.link: link.url]) { current, _ in current }, range: shiftedLinkRange)
        }
        return attributed
    }

    private func linkIcon(label: String, url: URL, color: NSColor) -> NSAttributedString {
        let symbolName = linkLooksLikeFolder(label: label, url: url) ? "folder.fill" : "doc.fill"
        let result = NSMutableAttributedString()
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let configured = image.withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) ?? image
            let attachment = NSTextAttachment()
            attachment.image = tintedImage(configured, color: color)
            attachment.bounds = NSRect(x: 0, y: -2, width: 12, height: 12)
            result.append(NSAttributedString(attachment: attachment))
        } else {
            result.append(NSAttributedString(string: "■", attributes: [.foregroundColor: color]))
        }
        result.append(NSAttributedString(string: " ", attributes: [.foregroundColor: color]))
        return result
    }

    private func linkLooksLikeFolder(label: String, url: URL) -> Bool {
        if label == "Download" || label == "Download/" || label == "Downloads" || label == "Downloads/" {
            return true
        }
        if label == "Desktop" || label == "Desktop/" {
            return true
        }
        if label.hasSuffix("/") {
            return true
        }
        return url.pathExtension.isEmpty
    }

    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let copy = NSImage(size: image.size)
        copy.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        rect.fill(using: .sourceAtop)
        copy.unlockFocus()
        copy.isTemplate = false
        return copy
    }

    private func fileURL(forTerminalPath label: String) -> URL? {
        if label.hasPrefix("file://") {
            return URL(string: label)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        if label == "Download" || label == "Download/" {
            return home.appendingPathComponent("Downloads", isDirectory: true)
        }
        if label.hasPrefix("Download/") {
            let rest = String(label.dropFirst("Download/".count))
            return home.appendingPathComponent("Downloads").appendingPathComponent(rest)
        }
        if label == "Downloads" || label == "Downloads/" {
            return home.appendingPathComponent("Downloads", isDirectory: true)
        }
        if label.hasPrefix("Downloads/") {
            let rest = String(label.dropFirst("Downloads/".count))
            return home.appendingPathComponent("Downloads").appendingPathComponent(rest)
        }
        if label == "Desktop" || label == "Desktop/" {
            return home.appendingPathComponent("Desktop", isDirectory: true)
        }
        if label.hasPrefix("Desktop/") {
            let rest = String(label.dropFirst("Desktop/".count))
            return home.appendingPathComponent("Desktop").appendingPathComponent(rest)
        }
        if label.hasPrefix("doc/") {
            let rest = String(label.dropFirst("doc/".count))
            return home.appendingPathComponent("Desktop").appendingPathComponent("doc").appendingPathComponent(rest)
        }
        return nil
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
    var trimTrailingBlankLinesOnPaste = false
    override var acceptsFirstResponder: Bool { true }

    override func paste(_ sender: Any?) {
        guard trimTrailingBlankLinesOnPaste,
              let pasted = NSPasteboard.general.string(forType: .string)
        else {
            super.paste(sender)
            return
        }
        insertText(pasted.trimmingTrailingBlankLines(), replacementRange: selectedRange())
    }
}

private extension String {
    func trimmingTrailingBlankLines() -> String {
        var lines = components(separatedBy: .newlines)
        while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}

final class TerminalNSTextView: NSTextView {
    var inputHandler: ((String) -> Void)?
    var renderedSourceText = ""
    private var linkTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let linkTrackingArea {
            removeTrackingArea(linkTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        linkTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if linkURL(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

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

    private func linkURL(at point: NSPoint) -> URL? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage,
              textStorage.length > 0
        else {
            return nil
        }

        var containerPoint = point
        let origin = textContainerOrigin
        containerPoint.x -= origin.x
        containerPoint.y -= origin.y

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        if glyphRange.length == 0 {
            return nil
        }
        let usedRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).insetBy(dx: -3, dy: -3)
        guard usedRect.contains(containerPoint) else {
            return nil
        }

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else {
            return nil
        }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) as? URL
    }
}
