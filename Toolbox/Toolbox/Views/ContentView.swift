import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RootViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { viewModel.toggleSidebarVisibility() }) {
                    Image(systemName: viewModel.isSidebarVisible ? "sidebar.left" : "sidebar.right")
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                Spacer()

                if viewModel.selectedTool.id == "daily-assign" || viewModel.selectedTool.id == "weekly-check" {
                    Button(action: viewModel.toggleHelp) {
                        Text(viewModel.helpButtonTitle)
                            .foregroundColor(viewModel.helpButtonTitle == "关闭" ? .accentColor : .white.opacity(0.9))
                    }
                    .buttonStyle(.borderless)
                }
                if viewModel.selectedTool.id == "daily-assign" {
                    Button(action: viewModel.handleConfigButton) {
                        Text(viewModel.configButtonTitle)
                            .foregroundColor(viewModel.configButtonTitle == "保存" ? .accentColor : .white.opacity(0.9))
                    }
                    .buttonStyle(.borderless)
                }
            }

            HSplitView {
                if viewModel.isSidebarVisible {
                    SidebarView(
                        tools: viewModel.visibleTools,
                        allTools: viewModel.tools,
                        selectedID: viewModel.selectedTool.id,
                        onSelect: { viewModel.select($0) },
                        onMove: { viewModel.moveVisibleTools(from: $0, to: $1) },
                        isToolHidden: { viewModel.isToolHidden($0) },
                        onToggleToolVisibility: { viewModel.toggleToolVisibility($0) }
                    )
                    .frame(minWidth: 96, idealWidth: 132, maxWidth: 168)
                    .background(Color(red: 0.145, green: 0.149, blue: 0.153))
                    .overlay(Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1), alignment: .trailing)
                }

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
                        if viewModel.shouldShowTextPane {
                            VSplitView {
                                textPane
                                terminalPane(showEditorControls: false)
                            }
                        } else {
                            VSplitView {
                                WeeklyCheckPane(files: $viewModel.weeklyCheckFiles)
                                terminalPane(showEditorControls: false)
                            }
                        }
                    } else if viewModel.selectedTool.id == "daily-assign" {
                        if viewModel.shouldShowTextPane {
                            VSplitView {
                                textPane
                                terminalPane(showEditorControls: false)
                            }
                        } else if viewModel.dailyAssignStage == .confirming && viewModel.isDailyAssignConfirmPaneZoomed {
                            DailyAssignPane(
                                files: $viewModel.dailyAssignFiles,
                                settings: $viewModel.dailyAssignSettings,
                                stage: $viewModel.dailyAssignStage,
                                rows: $viewModel.dailyAssignRows,
                                names: viewModel.dailyAssignNames,
                                canConfirm: viewModel.dailyAssignCanConfirm,
                                isZoomed: viewModel.isDailyAssignConfirmPaneZoomed,
                                onToggleZoom: viewModel.toggleDailyAssignConfirmPaneZoom,
                                onAdd: viewModel.addDailyAssignRow,
                                onReset: viewModel.resetDailyAssignRowsToOCR,
                                onRemove: viewModel.removeDailyAssignRow
                            )
                        } else {
                            VSplitView {
                                DailyAssignPane(
                                    files: $viewModel.dailyAssignFiles,
                                    settings: $viewModel.dailyAssignSettings,
                                    stage: $viewModel.dailyAssignStage,
                                    rows: $viewModel.dailyAssignRows,
                                    names: viewModel.dailyAssignNames,
                                    canConfirm: viewModel.dailyAssignCanConfirm,
                                    isZoomed: viewModel.isDailyAssignConfirmPaneZoomed,
                                    onToggleZoom: viewModel.toggleDailyAssignConfirmPaneZoom,
                                    onAdd: viewModel.addDailyAssignRow,
                                    onReset: viewModel.resetDailyAssignRowsToOCR,
                                    onRemove: viewModel.removeDailyAssignRow
                                )
                                .frame(
                                    minHeight: viewModel.dailyAssignStage == .confirming ? 300 : 220,
                                    idealHeight: viewModel.dailyAssignStage == .confirming ? 400 : 260
                                )
                                terminalPane(showEditorControls: false)
                                    .frame(
                                        minHeight: 84,
                                        idealHeight: viewModel.dailyAssignStage == .confirming ? 200 : 180
                                    )
                            }
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
                .overlay(alignment: .bottomTrailing) {
                    Button(action: { viewModel.clearAllToolInputs() }) {
                        Image("金银花1")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 82)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .padding(.bottom, 138)
                }
            }
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
            showHelpButton: viewModel.selectedTool.id != "weekly-check" && viewModel.selectedTool.id != "daily-assign",
            showConfigButton: viewModel.selectedTool.id != "download-images" && viewModel.selectedTool.id != "weekly-check" && viewModel.selectedTool.id != "daily-assign",
            helpButtonTitle: viewModel.helpButtonTitle,
            configButtonTitle: viewModel.configButtonTitle,
            isZoomed: viewModel.zoomTarget == .text,
            onHelp: viewModel.toggleHelp,
            onConfig: viewModel.handleConfigButton,
            onToggleZoom: { viewModel.toggleZoom(for: .text) }
        )
    }

    private func terminalPane(showEditorControls: Bool) -> some View {
        let toolID = viewModel.selectedTool.id
        let showHelp = toolID != "stitch-images" && toolID != "daily-assign" && toolID != "weekly-check"
        let showConfig = toolID != "stitch-images" && toolID != "download-images" && toolID != "daily-assign" && toolID != "weekly-check"
        let canStart: Bool = {
            if toolID == "daily-assign" {
                if viewModel.dailyAssignStage == .confirming { return viewModel.dailyAssignCanConfirm }
                return !viewModel.dailyAssignFiles.isEmpty
            }
            if toolID == "weekly-check" { return !viewModel.weeklyCheckFiles.isEmpty }
            return true
        }()
        return TerminalPaneView(
            outputText: viewModel.terminalText,
            isRunning: viewModel.isRunning,
            isZoomed: viewModel.zoomTarget == .terminal,
            showEditorControls: showEditorControls,
            showHelpButton: showHelp,
            showConfigButton: showConfig,
            helpButtonTitle: viewModel.helpButtonTitle,
            configButtonTitle: viewModel.configButtonTitle,
            isFocused: $viewModel.isTerminalFocused,
            onTerminalInput: viewModel.sendTerminalInput,
            onHelp: viewModel.toggleHelp,
            onConfig: viewModel.handleConfigButton,
            onToggleZoom: { viewModel.toggleZoom(for: .terminal) },
            onStart: viewModel.startSelectedTool,
            onStop: viewModel.stopSelectedTool,
            canStart: canStart,
            startButtonTitle: toolID == "daily-assign" ? viewModel.dailyAssignStartButtonTitle : "开始"
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: RootViewModel())
    }
}
