import SwiftUI

struct FileRenamerPane: View {
    @Binding var state: RenamerState
    @Binding var isFocused: Bool
    let onFolderDrop: (URL) -> Void
    let onStart: () -> Void
    let onUndo: () -> Void
    let onParamChange: () -> Void

    @FocusState private var prefixFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Drop Area
            DropZoneView(folderURL: state.folderURL, onDrop: onFolderDrop)
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
    let onDrop: (URL) -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                .background(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
            
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.largeTitle)
                    .foregroundColor(isHovering ? .accentColor : .secondary)
                
                if let url = folderURL {
                    Text(url.lastPathComponent)
                        .font(.headline)
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("把 目标文件夹 拖到这里")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
            providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        DispatchQueue.main.async {
                            onDrop(url)
                        }
                    }
                }
            }
            return true
        }
    }
}
