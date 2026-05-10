import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RootViewModel

    var body: some View {
        HSplitView {
            SidebarView(
                tools: viewModel.tools,
                selectedID: viewModel.selectedTool.id,
                onSelect: { viewModel.select($0) }
            )
            .frame(minWidth: 84, idealWidth: 108, maxWidth: 132)
            .background(Color(red: 0.145, green: 0.149, blue: 0.153))
            .overlay(Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1), alignment: .trailing)

            Group {
                if viewModel.selectedTool.id == "file-renamer" {
                    FileRenamerPane(
                        state: $viewModel.renamerState,
                        isFocused: $viewModel.isRenamerFocused,
                        onFolderDrop: { viewModel.updateRenamerFolder($0) },
                        onStart: { viewModel.executeRename() },
                        onUndo: { viewModel.undoRename() },
                        onParamChange: { viewModel.refreshRenamerPreview() }
                    )
                } else if viewModel.selectedTool.id == "weekly-check" {
                    VSplitView {
                        WeeklyCheckPane(files: $viewModel.weeklyCheckFiles)
                        terminalPane(showEditorControls: false)
                    }
                } else if viewModel.zoomTarget == .text && viewModel.shouldShowTextPane {
                    textPane
                } else if viewModel.zoomTarget == .terminal || !viewModel.shouldShowTextPane {
                    terminalPane(showEditorControls: !viewModel.shouldShowTextPane)
                } else {
                    VSplitView {
                        textPane
                        terminalPane(showEditorControls: false)
                    }
                }
            }
            .frame(minWidth: 360)
            .background(Color(red: 0.118, green: 0.118, blue: 0.118))
        }
        .padding(14)
        .background(Color(red: 0.118, green: 0.118, blue: 0.118))
    }

    private var textPane: some View {
        TextInputPane(
            title: viewModel.editorTitle,
            text: Binding(
                get: { viewModel.editorText },
                set: { viewModel.updateEditorText($0) }
            ),
            isFocused: $viewModel.isEditorFocused,
            isEditable: viewModel.isEditorEditable,
            helpButtonTitle: viewModel.helpButtonTitle,
            configButtonTitle: viewModel.configButtonTitle,
            isZoomed: viewModel.zoomTarget == .text,
            onHelp: viewModel.toggleHelp,
            onConfig: viewModel.handleConfigButton,
            onToggleZoom: { viewModel.toggleZoom(for: .text) }
        )
    }

    private func terminalPane(showEditorControls: Bool) -> some View {
        TerminalPaneView(
            outputText: viewModel.terminalText,
            isRunning: viewModel.isRunning,
            isZoomed: viewModel.zoomTarget == .terminal,
            showEditorControls: showEditorControls,
            helpButtonTitle: viewModel.helpButtonTitle,
            configButtonTitle: viewModel.configButtonTitle,
            isFocused: $viewModel.isTerminalFocused,
            onTerminalInput: viewModel.sendTerminalInput,
            onHelp: viewModel.toggleHelp,
            onConfig: viewModel.handleConfigButton,
            onToggleZoom: { viewModel.toggleZoom(for: .terminal) },
            onStart: viewModel.startSelectedTool,
            onStop: viewModel.stopSelectedTool
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: RootViewModel())
    }
}
