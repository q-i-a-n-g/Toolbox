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
    let onHelp: () -> Void
    let onConfig: () -> Void
    let onToggleZoom: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            PlainTextEditorView(text: $text, isFocused: $isFocused, isEditable: isEditable)
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
