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
                            fixedTopTerminalSplitPane(
                                topHeight: commonTopPaneHeight,
                                minTop: 148
                            ) {
                                WeeklyCheckPane(files: $viewModel.weeklyCheckFiles)
                            } bottom: {
                                terminalPane(showEditorControls: false)
                            }
                        }
                    } else if viewModel.selectedTool.id == "daily-assign" {
                        if viewModel.shouldShowTextPane {
                            VSplitView {
                                textPane
                                terminalPane(showEditorControls: false)
                            }
                        } else if viewModel.dailyAssignStage == .confirming {
                            dailyAssignConfirmSplitPane
                        } else {
                            fixedTopTerminalSplitPane(
                                topHeight: commonTopPaneHeight,
                                minTop: 220
                            ) {
                                DailyAssignPane(
                                    files: $viewModel.dailyAssignFiles,
                                    settings: $viewModel.dailyAssignSettings,
                                    stage: $viewModel.dailyAssignStage,
                                    rows: $viewModel.dailyAssignRows,
                                    names: viewModel.dailyAssignNames,
                                    canConfirm: viewModel.dailyAssignCanConfirm,
                                    confirmIssue: viewModel.dailyAssignConfirmIssue,
                                    isZoomed: viewModel.isDailyAssignConfirmPaneZoomed,
                                    onToggleZoom: { withPaneZoomAnimation(viewModel.toggleDailyAssignConfirmPaneZoom) },
                                    onAdd: viewModel.addDailyAssignRow,
                                    onReset: viewModel.resetDailyAssignRowsToOCR,
                                    onRemove: viewModel.removeDailyAssignRow
                                )
                            } bottom: {
                                terminalPane(showEditorControls: false)
                            }
                        }
                    } else if viewModel.selectedTool.id == "stitch-images" {
                        fixedTopTerminalSplitPane(
                            topHeight: commonTopPaneHeight,
                            minTop: 220
                        ) {
                            StitchImagesPane(
                                state: $viewModel.stitchImagesState,
                                onFolderDrop: viewModel.updateStitchImagesFolder
                            )
                        } bottom: {
                            terminalPane(showEditorControls: false)
                        }
                    } else if viewModel.shouldShowTextPane {
                        zoomableTextTerminalSplitPane
                    } else {
                        terminalPane(showEditorControls: true)
                    }
                }
                .frame(minWidth: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.118, green: 0.118, blue: 0.118))
                .overlay(alignment: .bottomTrailing) {
                    HoneysuckleClearButton(
                        isEnabled: honeysuckleClearEnabled,
                        disabledHelp: honeysuckleDisabledHelp
                    ) {
                        viewModel.clearAllToolInputs()
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 138)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08), value: viewModel.isSidebarVisible)

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

    private var commonTopPaneHeight: CGFloat {
        252
    }

    private var honeysuckleClearEnabled: Bool {
        !viewModel.isRunning && !(viewModel.selectedTool.id == "daily-assign" && viewModel.dailyAssignStage == .confirming)
    }

    private var honeysuckleDisabledHelp: String {
        if viewModel.selectedTool.id == "daily-assign" && viewModel.dailyAssignStage == .confirming {
            return ""
        }
        return "运行中不能清空"
    }

    private func withPaneZoomAnimation(_ action: () -> Void) {
        action()
    }

    private func fixedTopTerminalSplitPane<Top: View, Bottom: View>(
        topHeight: CGFloat? = nil,
        minTop: CGFloat = 140,
        minBottom: CGFloat = 180,
        @ViewBuilder top: @escaping () -> Top,
        @ViewBuilder bottom: @escaping () -> Bottom
    ) -> some View {
        GeometryReader { proxy in
            let availableHeight = max(proxy.size.height, 0)
            let topHeight = fixedTopHeight(
                availableHeight: availableHeight,
                preferredTop: topHeight ?? commonTopPaneHeight,
                minTop: minTop,
                minBottom: minBottom
            )
            let bottomHeight = max(0, availableHeight - topHeight)

            VStack(spacing: 0) {
                top()
                    .frame(height: topHeight)

                bottom()
                    .frame(height: bottomHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func fixedTopHeight(availableHeight: CGFloat, preferredTop: CGFloat, minTop: CGFloat, minBottom: CGFloat) -> CGFloat {
        guard availableHeight > 0 else { return 0 }
        let clampedMinTop = min(minTop, availableHeight)
        let clampedMinBottom = min(minBottom, max(0, availableHeight - clampedMinTop))
        let maxTop = max(clampedMinTop, availableHeight - clampedMinBottom)
        return min(max(preferredTop, clampedMinTop), maxTop)
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
                DailyAssignConfigPane(
                    names: $viewModel.dailyAssignConfigNames,
                    onRestoreDefaults: viewModel.restoreDefaultDailyAssignConfigNames
                )
            } else if viewModel.editorMode == .help && (viewModel.selectedTool.id == "open-links" || viewModel.selectedTool.id == "download-images") {
                CopyableHelpPane(
                    title: viewModel.editorTitle,
                    text: viewModel.editorText,
                    helpButtonTitle: viewModel.helpButtonTitle,
                    isZoomed: viewModel.zoomTarget == .text,
                    onHelp: viewModel.toggleHelp,
                    onToggleZoom: { withPaneZoomAnimation { viewModel.toggleZoom(for: .text) } }
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
                    placeholder: textInputPlaceholder,
                    isZoomed: viewModel.zoomTarget == .text,
                    trimTrailingBlankLinesOnPaste: viewModel.selectedTool.id == "open-links" || viewModel.selectedTool.id == "download-images",
                    onHelp: viewModel.toggleHelp,
                    onConfig: viewModel.handleConfigButton,
                    onToggleZoom: { withPaneZoomAnimation { viewModel.toggleZoom(for: .text) } }
                )
            }
        }
    }

    private var textInputPlaceholder: String {
        if viewModel.selectedTool.id == "open-links" || viewModel.selectedTool.id == "download-images" {
            return "粘贴 链接 到这里..."
        }
        return ""
    }

    private var zoomableTextTerminalSplitPane: some View {
        GeometryReader { proxy in
            let availableHeight = max(proxy.size.height, 0)
            let normalTopHeight = fixedTopHeight(
                availableHeight: availableHeight,
                preferredTop: commonTopPaneHeight,
                minTop: 140,
                minBottom: 180
            )
            let terminalZoomed = viewModel.zoomTarget == .terminal && viewModel.selectedTool.id == "open-links"
            let topHeight = viewModel.zoomTarget == .text ? availableHeight : (terminalZoomed ? 0 : normalTopHeight)
            let bottomHeight = max(0, availableHeight - topHeight)

            VStack(spacing: 0) {
                textPane
                    .frame(height: topHeight)
                    .clipped()
                    .allowsHitTesting(topHeight > 1)

                terminalPane(showEditorControls: false)
                    .frame(height: bottomHeight)
                    .clipped()
                    .allowsHitTesting(bottomHeight > 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.22), value: viewModel.zoomTarget)
        }
    }

    private var dailyAssignConfirmSplitPane: some View {
        GeometryReader { proxy in
            let availableHeight = max(proxy.size.height, 0)
            let actionBarHeight: CGFloat = 58
            let normalTopHeight = fixedTopHeight(
                availableHeight: availableHeight,
                preferredTop: commonTopPaneHeight,
                minTop: 220,
                minBottom: 180
            )
            let topHeight = viewModel.isDailyAssignConfirmPaneZoomed ? max(0, availableHeight - actionBarHeight) : normalTopHeight
            let bottomHeight = max(0, availableHeight - topHeight)

            VStack(spacing: 0) {
                dailyAssignConfirmPane
                    .frame(height: topHeight)
                    .clipped()

                Group {
                    if viewModel.isDailyAssignConfirmPaneZoomed {
                        dailyAssignConfirmActionBar
                    } else {
                        terminalPane(showEditorControls: false)
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .frame(height: bottomHeight)
                .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.22), value: viewModel.isDailyAssignConfirmPaneZoomed)
        }
    }

    private var dailyAssignConfirmPane: some View {
        DailyAssignPane(
            files: $viewModel.dailyAssignFiles,
            settings: $viewModel.dailyAssignSettings,
            stage: $viewModel.dailyAssignStage,
            rows: $viewModel.dailyAssignRows,
            names: viewModel.dailyAssignNames,
            canConfirm: viewModel.dailyAssignCanConfirm,
            confirmIssue: viewModel.dailyAssignConfirmIssue,
            isZoomed: viewModel.isDailyAssignConfirmPaneZoomed,
            onToggleZoom: { withPaneZoomAnimation(viewModel.toggleDailyAssignConfirmPaneZoom) },
            onAdd: viewModel.addDailyAssignRow,
            onReset: viewModel.resetDailyAssignRowsToOCR,
            onRemove: viewModel.removeDailyAssignRow
        )
    }

    private var dailyAssignConfirmActionBar: some View {
        TerminalActionButtons(
            isRunning: viewModel.isRunning,
            canStop: dailyAssignCanStop,
            canStart: viewModel.dailyAssignCanConfirm,
            startButtonTitle: viewModel.dailyAssignStartButtonTitle,
            onStart: viewModel.startSelectedTool,
            onStop: viewModel.stopSelectedTool
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 8)
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
            if toolID == "open-links" || toolID == "download-images" {
                return !viewModel.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }()
        let canStop: Bool = {
            if toolID == "daily-assign" { return dailyAssignCanStop }
            return viewModel.isRunning
        }()
        return TerminalPaneView(
            outputText: viewModel.terminalText,
            isRunning: viewModel.isRunning,
            isZoomed: viewModel.zoomTarget == .terminal && toolID == "open-links",
            showEditorControls: showEditorControls,
            showHelpButton: showHelp,
            showConfigButton: showConfig,
            showZoomButton: toolID == "open-links",
            helpButtonTitle: viewModel.helpButtonTitle,
            configButtonTitle: viewModel.configButtonTitle,
            isFocused: $viewModel.isTerminalFocused,
            onTerminalInput: viewModel.sendTerminalInput,
            onHelp: viewModel.toggleHelp,
            onConfig: viewModel.handleConfigButton,
            onToggleZoom: { withPaneZoomAnimation { viewModel.toggleZoom(for: .terminal) } },
            onStart: viewModel.startSelectedTool,
            onStop: viewModel.stopSelectedTool,
            canStop: canStop,
            canStart: canStart,
            startButtonTitle: toolID == "daily-assign" ? viewModel.dailyAssignStartButtonTitle : "开始"
        )
    }

    private var dailyAssignCanStop: Bool {
        viewModel.isRunning || viewModel.dailyAssignStage == .confirming
    }
}

private struct HoneysuckleClearButton: View {
    let isEnabled: Bool
    let disabledHelp: String
    let action: () -> Void

    @State private var isHovering = false
    @State private var showFeedback = false

    var body: some View {
        Button {
            guard isEnabled else {
                NSSound.beep()
                return
            }

            action()
            withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
                showFeedback = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.18)) {
                    showFeedback = false
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isHovering && isEnabled ? 0.08 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(isHovering && isEnabled ? 0.24 : 0), lineWidth: 1)
                    )
                    .frame(width: 110, height: 82)

                Image("金银花1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 82)

                if showFeedback {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.green)
                        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                        .padding(.top, -2)
                        .padding(.trailing, -2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(HoneysuckleButtonStyle(isEnabled: isEnabled))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .modifier(OptionalHelpModifier(text: isEnabled ? "清空当前工具内容" : disabledHelp))
        .accessibilityLabel("清空当前工具内容")
    }
}

private struct OptionalHelpModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        if text.isEmpty {
            content
        } else {
            content.help(text)
        }
    }
}

private struct HoneysuckleButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.92 : 1)
            .shadow(
                color: Color.black.opacity(configuration.isPressed && isEnabled ? 0.16 : 0.32),
                radius: configuration.isPressed && isEnabled ? 2 : 6,
                x: 0,
                y: configuration.isPressed && isEnabled ? 1 : 3
            )
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: RootViewModel())
    }
}
