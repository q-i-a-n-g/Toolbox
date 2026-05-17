import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WeeklyCheckPane: View {
    @Binding var files: [URL]

    var body: some View {
        VStack(spacing: 0) {
            WeeklyCheckDropZoneView(files: $files)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
    }
}

struct WeeklyCheckDropZoneView: View {
    @Binding var files: [URL]
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                .background(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)

            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(isHovering ? .accentColor : .secondary)
                    .onTapGesture { appendFromPasteboard() }

                if !files.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(files.prefix(4), id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if files.count > 4 {
                            Text("等共 \(files.count) 个文件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("已分配的线上任务表，复制一份，拖到这里...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
            appendFromProviders(providers)
            return true
        }
        .onPasteCommand(of: [UTType.fileURL]) { providers in
            appendFromProviders(providers)
        }
    }

    private func appendFromPasteboard() {
        let classes: [AnyClass] = [NSURL.self]
        if let urls = NSPasteboard.general.readObjects(forClasses: classes, options: nil) as? [URL] {
            appendFiles(urls)
        }
    }

    private func appendFromProviders(_ providers: [NSItemProvider]) {
        var newFiles: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let url else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "xlsx" || ext == "xls" else { return }
                    newFiles.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            appendFiles(newFiles)
        }
    }

    private func appendFiles(_ newFiles: [URL]) {
        guard !newFiles.isEmpty else { return }
        var seen = Set(files.map(\.path))
        var merged = files
        for url in newFiles where !seen.contains(url.path) {
            seen.insert(url.path)
            merged.append(url)
        }
        files = merged
    }
}
