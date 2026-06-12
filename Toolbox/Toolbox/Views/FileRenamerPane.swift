import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileRenamerPane: View {
    @Binding var state: RenamerState
    @Binding var isFocused: Bool
    let onTargetDrop: ([URL]) -> Void
    let onStart: () -> Void
    let onUndo: () -> Void
    let onParamChange: () -> Void

    @FocusState private var prefixFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Drop Area
            DropZoneView(folderURL: state.folderURL, fileURLs: state.selectedFileURLs, onDrop: onTargetDrop)
                .frame(height: 120)

            // Example Label
            HStack {
                Text("· 前缀 IMG + 编号 001 = IMG001")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            // Parameters
            HStack(spacing: 12) {
                paramField(label: "前缀：", text: $state.prefix, placeholder: "可留空")
                
                paramIntField(label: "起始编号：", value: $state.startNumber)
                
                paramIntField(label: "步长：", value: $state.step)
                
                paramField(label: "编号长度：", text: $state.padding, placeholder: "可留空")
            }

            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("预览：")
                    .font(.headline)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.previewItems.prefix(15)) { item in
                            HStack {
                                Text(item.oldName)
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(item.newName)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                            }
                            .font(.system(.body, design: .monospaced))
                        }
                        
                        if state.previewItems.count > 15 {
                            Text("......")
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }

            Spacer()

            // Buttons
            HStack(spacing: 24) {
                Spacer()
                
                Button("撤销", action: onUndo)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(state.history == nil)

                Button("开始", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.previewItems.isEmpty)
                
                Spacer()
            }
        }
        .padding(16)
        .onChange(of: state.prefix) { _ in onParamChange() }
        .onChange(of: state.startNumber) { _ in onParamChange() }
        .onChange(of: state.step) { _ in onParamChange() }
        .onChange(of: state.padding) { _ in onParamChange() }
        .onChange(of: isFocused) { newValue in
            if newValue {
                prefixFocused = true
                isFocused = false
            }
        }
    }

    private func paramField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .focused($prefixFocused)
        }
    }

    private func paramIntField(label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label)
            TextField("", value: value, formatter: NumberFormatter())
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
        }
    }
}

struct DropZoneView: View {
    let folderURL: URL?
    let fileURLs: [URL]
    let onDrop: ([URL]) -> Void
    @State private var isHovering = false
    @State private var hasPasteableTargets = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                .background(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
            
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(isHovering ? .accentColor : .secondary)
                
                if let url = folderURL {
                    Text(url.lastPathComponent)
                        .font(.headline)
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if !fileURLs.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(fileURLs.prefix(3), id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if fileURLs.count > 3 {
                            Text("等共 \(fileURLs.count) 个文件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text(hasPasteableTargets ? "点这里，可粘贴..." : "文件/文件夹 拖到这里...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { appendFromPasteboard() }
        .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
            appendFromProviders(providers)
            return true
        }
        .onPasteCommand(of: [UTType.fileURL]) { providers in
            appendFromProviders(providers)
        }
        .onAppear(perform: refreshPasteAvailability)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPasteAvailability()
        }
    }

    private func appendFromPasteboard() {
        let classes: [AnyClass] = [NSURL.self]
        guard let urls = NSPasteboard.general.readObjects(forClasses: classes, options: nil) as? [URL] else { return }
        let valid = validTargetURLs(urls)
        guard !valid.isEmpty else {
            refreshPasteAvailability()
            return
        }
        onDrop(valid)
        refreshPasteAvailability()
    }

    private func appendFromProviders(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var loaded: [(Int, URL)] = []

        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let url else { return }
                    loaded.append((index, url))
                }
            }
        }

        group.notify(queue: .main) {
            let urls = loaded.sorted { $0.0 < $1.0 }.map(\.1)
            let valid = validTargetURLs(urls)
            if !valid.isEmpty {
                onDrop(valid)
            }
        }
    }

    private func refreshPasteAvailability() {
        let classes: [AnyClass] = [NSURL.self]
        let urls = NSPasteboard.general.readObjects(forClasses: classes, options: nil) as? [URL] ?? []
        hasPasteableTargets = !validTargetURLs(urls).isEmpty
    }

    private func validTargetURLs(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var folders: [URL] = []
        var files: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                folders.append(url)
            } else {
                files.append(url)
            }
        }

        if folders.count == 1 && files.isEmpty {
            return folders
        }
        if folders.isEmpty && !files.isEmpty {
            return files
        }
        return []
    }
}
