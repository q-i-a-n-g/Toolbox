import SwiftUI
import AppKit

struct TextInputPane: View {
    let title: String
    @Binding var text: String
    @Binding var isFocused: Bool
    let isEditable: Bool
    let showHelpButton: Bool
    let showConfigButton: Bool
    let helpButtonTitle: String
    let configButtonTitle: String
    let isZoomed: Bool
    let trimTrailingBlankLinesOnPaste: Bool
    let onHelp: () -> Void
    let onConfig: () -> Void
    let onToggleZoom: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            PlainTextEditorView(
                text: $text,
                isFocused: $isFocused,
                isEditable: isEditable,
                trimTrailingBlankLinesOnPaste: trimTrailingBlankLinesOnPaste
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.118, green: 0.118, blue: 0.118))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .frame(minHeight: 110)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            if showHelpButton {
                Button(action: onHelp) {
                    Text(helpButtonTitle)
                        .fontWeight(helpButtonTitle == "关闭" ? .bold : .regular)
                        .foregroundColor(helpButtonTitle == "关闭" ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
            }

            if showConfigButton {
                Button(action: onConfig) {
                    Text(configButtonTitle)
                        .fontWeight(configButtonTitle == "保存" ? .bold : .regular)
                        .foregroundColor(configButtonTitle == "保存" ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
            }

            if isEditable {
                Button(action: onToggleZoom) {
                    Image(systemName: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(isZoomed ? "恢复分栏" : "放大到最大")
            }
        }
        .padding(.bottom, 10)
    }
}

struct OpenLinksConfigPane: View {
    @Binding var batchSize: Int
    @Binding var dedupeLinks: Bool
    let helpButtonTitle: String
    let configButtonTitle: String
    let onHelp: () -> Void
    let onConfig: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("配置")
                    .font(.headline)

                Spacer()

                Button(action: onHelp) {
                    Text(helpButtonTitle)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.borderless)

                Button(action: onConfig) {
                    Text(configButtonTitle)
                        .fontWeight(configButtonTitle == "保存" ? .bold : .regular)
                        .foregroundColor(configButtonTitle == "保存" ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("每次打开几个链接")
                    .font(.system(size: 13, weight: .semibold))

                Text("到达这个数量后暂停，按回车继续下一批。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("10", value: $batchSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .configBlock()

            VStack(alignment: .leading, spacing: 12) {
                Text("链接去重")
                    .font(.system(size: 13, weight: .semibold))

                Toggle("打开前先去掉重复链接", isOn: $dedupeLinks)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            .configBlock()

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CopyableHelpPane: View {
    let title: String
    let text: String
    let helpButtonTitle: String
    let isZoomed: Bool
    let onHelp: () -> Void
    let onToggleZoom: () -> Void

    private let copyMarker = "## 可直接复制到 文本框 测试："

    private var splitText: (intro: String, copyable: String) {
        guard let range = text.range(of: copyMarker) else {
            return (text, "")
        }
        return (String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), String(text[range.lowerBound...]))
    }

    private var copyableText: String {
        splitText.copyable.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var copyBodyText: String {
        copyableText
            .replacingOccurrences(of: copyMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !splitText.intro.isEmpty {
                        Text(splitText.intro)
                            .helpTextStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !copyableText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                Text(copyMarker)
                                    .helpTextStyle()
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button(action: copyHelpText) {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .help("复制测试内容")
                            }

                            Text(copyBodyText)
                                .helpTextStyle()
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.118, green: 0.118, blue: 0.118))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .frame(minHeight: 110)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            Button(action: onHelp) {
                Text(helpButtonTitle)
                    .fontWeight(helpButtonTitle == "关闭" ? .bold : .regular)
                    .foregroundColor(helpButtonTitle == "关闭" ? .accentColor : .primary)
            }
            .buttonStyle(.borderless)

        }
        .padding(.bottom, 10)
    }

    private func copyHelpText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copyBodyText, forType: .string)
    }
}

struct DailyAssignConfigPane: View {
    @Binding var names: [String]
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("校准名单")
                        .font(.system(size: 13, weight: .semibold))

                    Text("共 \(names.count) 人")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Spacer()
                }

                Text("注意：名单中没有的，不会给他分配任务。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(names.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField("姓名", text: Binding(
                                    get: { names[index] },
                                    set: { names[index] = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))

                                Button {
                                    names.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                                .help("删除")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(index.isMultiple(of: 2) ? Color.white.opacity(0.04) : Color.clear)
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: .infinity)
                .background(Color.black.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

                HStack(spacing: 8) {
                    TextField("新增姓名...", text: $newName)
                        .textFieldStyle(.roundedBorder)

                    Button("添加") {
                        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, !names.contains(value) else { return }
                        names.append(value)
                        newName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .configBlock(fillVerticalSpace: true)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension View {
    func helpTextStyle() -> some View {
        self
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.primary)
            .textSelection(.enabled)
    }

    func configBlock(fillVerticalSpace: Bool = false) -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: fillVerticalSpace ? .infinity : nil, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
            )
    }
}
