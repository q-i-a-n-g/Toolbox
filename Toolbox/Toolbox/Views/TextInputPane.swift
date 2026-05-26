import SwiftUI

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

            Button(action: onToggleZoom) {
                Image(systemName: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help(isZoomed ? "恢复分栏" : "放大到最大")
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
                Text("批量打开链接")
                    .font(.system(size: 13, weight: .semibold))

                Text("设置每批打开的链接数量，以及是否先过滤重复链接。")
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

struct DailyAssignConfigPane: View {
    @Binding var names: [String]
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("校准名单")
                    .font(.system(size: 13, weight: .semibold))

                Text("名单中没有的人不会分配任务。可删除、编辑或新增姓名。")
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
                .frame(minHeight: 110, maxHeight: 170)
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
            .configBlock()

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension View {
    func configBlock() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
            )
    }
}
