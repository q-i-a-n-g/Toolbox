import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DailyAssignSettings {
    var allocationMethod: String = "page"
    var aiMaxPages: Int = 200
    var cardMaxPages: Int = 300
    var allocationMode: String = "linked"
}

struct DailyAssignPane: View {
    @Binding var files: [URL]
    @Binding var settings: DailyAssignSettings

    var body: some View {
        VStack(spacing: 10) {
            DailyAssignDropZoneView(files: $files)
                .frame(height: 120)

            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $settings.allocationMethod) {
                        Text("按页分配").tag("page")
                        Text("按标签分配").tag("tag")
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI最多可分配页数")
                                .foregroundColor(.white.opacity(0.9))
                            TextField("200", value: $settings.aiMaxPages, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .frame(width: 54)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("答题卡最多可分配页数")
                                .foregroundColor(.white.opacity(0.9))
                            TextField("300", value: $settings.cardMaxPages, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .frame(width: 54)
                        }
                    }

                    Picker("", selection: $settings.allocationMode) {
                        Text("AI+答题卡一起分配").tag("linked")
                        Text("AI、答题卡独立分配").tag("independent")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(10)
                .font(.system(size: 12))
                .frame(maxWidth: 420)
                Spacer()
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct DailyAssignDropZoneView: View {
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

                if files.isEmpty {
                    Text("报名截图 + 今日任务表 拖到这里")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
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
        let group = DispatchGroup()
        var newFiles: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let url else { return }
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return }
                    newFiles.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            appendFiles(newFiles)
        }
    }

    private func appendFiles(_ urls: [URL]) {
        let allowedImageExt = Set(["png", "jpg", "jpeg", "webp", "heic"])
        let allowedExcelExt = Set(["xlsx", "xls"])

        let filtered = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return allowedImageExt.contains(ext) || allowedExcelExt.contains(ext)
        }

        guard !filtered.isEmpty else { return }

        var seen = Set(files.map(\.path))
        var merged = files
        for url in filtered where !seen.contains(url.path) {
            seen.insert(url.path)
            merged.append(url)
        }
        files = merged
    }
}
