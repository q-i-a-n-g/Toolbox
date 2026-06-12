import SwiftUI

struct TerminalPaneView: View {
    let outputText: String
    let isRunning: Bool
    let isZoomed: Bool
    let showEditorControls: Bool
    let showHelpButton: Bool
    let showConfigButton: Bool
    let helpButtonTitle: String
    let configButtonTitle: String
    @Binding var isFocused: Bool
    let onTerminalInput: (String) -> Void
    let onHelp: () -> Void
    let onConfig: () -> Void
    let onToggleZoom: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let canStart: Bool
    let startButtonTitle: String



    var body: some View {
        VStack(spacing: 0) {
            header

            TerminalTextView(outputText: outputText, isFocused: $isFocused, onInput: onTerminalInput)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.098, green: 0.098, blue: 0.098))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )

            HStack {
                Button("停止", action: onStop)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .disabled(!isRunning)
                    .controlSize(.large)
                    .frame(minWidth: 110)

                Button(startButtonTitle, action: onStart)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || !canStart)
                    .controlSize(.large)
                    .frame(minWidth: 110)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .frame(minHeight: 80)
    }

    private var header: some View {
        HStack {
            Text("终端")
                .font(.headline)

            Spacer()

            if showEditorControls {
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
            }

        }
        .padding(.bottom, 10)
    }
}
