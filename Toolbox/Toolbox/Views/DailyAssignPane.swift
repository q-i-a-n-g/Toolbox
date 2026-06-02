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
    @Binding var stage: DailyAssignStage
    @Binding var rows: [DailyAssignSignupRow]
    let names: [String]
    let canConfirm: Bool
    let isZoomed: Bool
    let onToggleZoom: () -> Void
    let onAdd: () -> Void
    let onReset: () -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if stage == .confirming {
                confirmPane
            } else {
                setupPane
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var setupPane: some View {
        VStack(spacing: 10) {
            DailyAssignDropZoneView(files: $files)
                .frame(height: 120)

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .trailing, spacing: 16) {
                        Picker("", selection: $settings.allocationMethod) {
                            Text("按页分配").tag("page")
                            Text("按标签分配").tag("tag")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 300)

                        Picker("", selection: $settings.allocationMode) {
                            Text("AI+答题卡一起分配").tag("linked")
                            Text("AI、答题卡独立分配").tag("independent")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 300)
                    }

                    Spacer().frame(width: 20)
                    Divider().frame(height: 60).opacity(0.5)
                    Spacer().frame(width: 20)

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Text("AI最多可分配页数")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            TextField("200", value: $settings.aiMaxPages, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .frame(width: 56)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 240)

                        HStack(spacing: 12) {
                            Text("答题卡最多可分配页数")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            TextField("300", value: $settings.cardMaxPages, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .frame(width: 56)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 240)
                    }
                }
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private var confirmPane: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Text("报名结果确认")
                    .font(.headline)

                Text("识别到 \(rows.count) 人")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // let unmatchedCount = rows.filter { !$0.matched }.count
                // if unmatchedCount > 0 {
                //     Text("未匹配 \(unmatchedCount)")
                //         .font(.subheadline)
                //         .foregroundColor(.secondary)
                // }

                Spacer()

                Button("+ 添加报名人", action: onAdd)
                Button("重置为OCR", action: onReset)

                Button(action: onToggleZoom) {
                    Image(systemName: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(isZoomed ? "恢复分栏" : "铺满右侧")
            }
            .buttonStyle(.bordered)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach($rows) { $row in
                            HStack(spacing: 14) {
                                Picker("", selection: $row.name) {
                                    ForEach(names, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 180)

                                Picker("", selection: $row.count) {
                                    Text("2").tag(2)
                                    Text("3").tag(3)
                                    Text("5").tag(5)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 120)

                                Group {
                                    if row.isUserAdded {
                                        Text("新增")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                                    } else if row.name != row.originalName || row.count != row.originalCount {
                                        Text("已修改")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color.blue.opacity(0.16)))
                                    } else {
                                        Text("　")
                                            .font(.caption2)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .opacity(0)
                                    }
                                }
                                .frame(width: 62, alignment: .center)

                                Button("删除") { onRemove(row.id) }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.red.opacity(0.85))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(row.matched ? Color.white.opacity(0.03) : Color.orange.opacity(0.12))
                            )
                            .id(row.id)
                        }
                    }
                }
                .onChange(of: rows.count) { _ in
                    guard let last = rows.last, last.isUserAdded else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: isZoomed ? .infinity : 360)

            if !canConfirm {
                Text("请先完成有效名单确认后再点击下方“继续”")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
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
                    Text("报名截图 拖到这里...")
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

struct StitchImagesPane: View {
    @Binding var state: StitchImagesState
    let onFolderDrop: (URL) -> Void

    var body: some View {
        VStack(spacing: 12) {
            StitchFolderDropZone(folderURL: state.folderURL, onDrop: onFolderDrop)
                .frame(height: 128)

            HStack(spacing: 16) {
                stitchModeButton(title: "上下\n两两拼接", mode: "1", layout: .vertical(count: 2))
                stitchModeButton(title: "上下\n三三拼接", mode: "2", layout: .vertical(count: 3))
                stitchModeButton(title: "左右\n两两拼接", mode: "3", layout: .horizontal(count: 2))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stitchModeButton(title: String, mode: String, layout: StitchModeIcon.Layout) -> some View {
        let selected = state.mode == mode
        return Button {
            state.mode = mode
        } label: {
            VStack(spacing: 8) {
                StitchModeIcon(layout: layout)
                    .frame(width: 36, height: 30)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 112, height: 76)
            .foregroundColor(selected ? .accentColor : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(title.replacingOccurrences(of: "\n", with: ""))
    }
}

private struct StitchModeIcon: View {
    enum Layout {
        case vertical(count: Int)
        case horizontal(count: Int)
    }

    let layout: Layout

    var body: some View {
        switch layout {
        case .vertical(let count):
            VStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { _ in
                    segment
                }
            }
        case .horizontal(let count):
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { _ in
                    segment
                }
            }
        }
    }

    private var segment: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .stroke(lineWidth: 1.5)
    }
}

private struct StitchFolderDropZone: View {
    let folderURL: URL?
    let onDrop: (URL) -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                .background(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)

            VStack(spacing: 7) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(isHovering ? .accentColor : .secondary)
                    .onTapGesture { appendFromPasteboard() }

                if let url = folderURL {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("目标文件夹 拖到这里...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
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
        guard let urls = NSPasteboard.general.readObjects(forClasses: classes, options: nil) as? [URL] else { return }
        appendFirstFolder(urls)
    }

    private func appendFromProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    appendFirstFolder([url])
                }
            }
        }
    }

    private func appendFirstFolder(_ urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                onDrop(url)
                return
            }
        }
    }
}
