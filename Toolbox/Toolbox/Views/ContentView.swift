import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: RootViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
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
                    .frame(width: 148)
                    .background(Color(red: 0.145, green: 0.149, blue: 0.153))
                    .overlay(Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1), alignment: .trailing)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Group {
                    if viewModel.editorMode == .help || viewModel.editorMode == .config {
                        textPane
                    } else if viewModel.selectedTool.id == "file-renamer" {
                        FileRenamerPane(
                            state: $viewModel.renamerState,
                            isFocused: $viewModel.isRenamerFocused,
                            onTargetDrop: { viewModel.updateRenamerTargets($0) },
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
                                    .frame(minHeight: 120, idealHeight: 170)
                                terminalPane(showEditorControls: false)
                                    .frame(minHeight: 220, idealHeight: 340)
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
                                    minHeight: viewModel.dailyAssignStage == .confirming ? 360 : 220,
                                    idealHeight: viewModel.dailyAssignStage == .confirming ? 460 : 260
                                )
                                terminalPane(showEditorControls: false)
                                    .frame(
                                        minHeight: 84,
                                        idealHeight: viewModel.dailyAssignStage == .confirming ? 190 : 180
                                    )
                            }
                        }
                    } else if viewModel.selectedTool.id == "stitch-images" {
                        VStack(spacing: 10) {
                            StitchImagesPane(
                                state: $viewModel.stitchImagesState,
                                onFolderDrop: viewModel.updateStitchImagesFolder
                            )
                            .frame(height: 270)
                            terminalPane(showEditorControls: false)
                                .frame(maxHeight: .infinity)
                        }
                    } else if viewModel.zoomTarget == .text && viewModel.shouldShowTextPane {
                        textPane
                    } else if viewModel.zoomTarget == .terminal || !viewModel.shouldShowTextPane {
                        terminalPane(showEditorControls: !viewModel.shouldShowTextPane)
                    } else {
                        VSplitView {
                            textPane
                                .frame(minHeight: 120, idealHeight: 170)
                            terminalPane(showEditorControls: false)
                                .frame(minHeight: 220, idealHeight: 340)
                        }
                    }
                }
                .frame(minWidth: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            topToolButtons
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 10)
                .padding(.top, 0)
        }
        .padding(14)
        .background(Color(red: 0.118, green: 0.118, blue: 0.118))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refocusTerminalAfterActivationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            viewModel.refocusTerminalAfterActivationIfNeeded()
        }
    }

    @ViewBuilder
    private var topToolButtons: some View {
        if viewModel.selectedTool.id == "daily-assign" || viewModel.selectedTool.id == "weekly-check" {
            HStack(spacing: 8) {
                Button(action: viewModel.toggleHelp) {
                    Text(viewModel.helpButtonTitle)
                        .foregroundColor(viewModel.helpButtonTitle == "关闭" ? .accentColor : .white.opacity(0.9))
                }
                .buttonStyle(.borderless)

                if viewModel.selectedTool.id == "daily-assign" {
                    Button(action: viewModel.handleConfigButton) {
                        Text(viewModel.configButtonTitle)
                            .foregroundColor(viewModel.configButtonTitle == "保存" ? .accentColor : .white.opacity(0.9))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var textPane: some View {
        Group {
            if viewModel.editorMode == .config && viewModel.selectedTool.id == "open-links" {
                OpenLinksConfigPane(
                    batchSize: $viewModel.openLinksConfig.batchSize,
                    dedupeLinks: $viewModel.openLinksConfig.dedupeLinks,
                    helpButtonTitle: viewModel.helpButtonTitle,
                    configButtonTitle: viewModel.configButtonTitle,
                    onHelp: viewModel.toggleHelp,
                    onConfig: viewModel.handleConfigButton
                )
            } else if viewModel.editorMode == .config && viewModel.selectedTool.id == "daily-assign" {
                DailyAssignConfigPane(names: $viewModel.dailyAssignConfigNames)
            } else if viewModel.editorMode == .help && (viewModel.selectedTool.id == "open-links" || viewModel.selectedTool.id == "download-images") {
                CopyableHelpPane(
                    title: viewModel.editorTitle,
                    text: viewModel.editorText,
                    helpButtonTitle: viewModel.helpButtonTitle,
                    isZoomed: viewModel.zoomTarget == .text,
                    onHelp: viewModel.toggleHelp,
                    onToggleZoom: { viewModel.toggleZoom(for: .text) }
                )
            } else {
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
                    trimTrailingBlankLinesOnPaste: viewModel.selectedTool.id == "open-links" || viewModel.selectedTool.id == "download-images",
                    onHelp: viewModel.toggleHelp,
                    onConfig: viewModel.handleConfigButton,
                    onToggleZoom: { viewModel.toggleZoom(for: .text) }
                )
            }
        }
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
            if toolID == "stitch-images" { return viewModel.stitchImagesState.folderURL != nil }
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
