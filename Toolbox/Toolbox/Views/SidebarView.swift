import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let tools: [ScriptTool]
    let allTools: [ScriptTool]
    let selectedID: String
    let onSelect: (ScriptTool) -> Void
    let onMove: (_ source: Int, _ destination: Int) -> Void
    let isToolHidden: (String) -> Bool
    let onToggleToolVisibility: (String) -> Void

    @State private var draggingID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("工具箱")
                .font(.title3.bold())
                .padding(.leading, 10)
                .foregroundColor(Color.white.opacity(0.92))

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                        toolRow(tool)
                            .onDrag {
                                draggingID = tool.id
                                return NSItemProvider(object: tool.id as NSString)
                            }
                            .onDrop(of: [UTType.plainText], delegate: SidebarDropDelegate(
                                targetIndex: index,
                                targetID: tool.id,
                                draggingID: $draggingID,
                                currentTools: tools,
                                onMove: onMove
                            ))
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: selectedID)
            }
            .contextMenu {
                ForEach(allTools) { tool in
                    Button {
                        onToggleToolVisibility(tool.id)
                    } label: {
                        Text(menuTitle(title: tool.title, shown: !isToolHidden(tool.id)))
                    }
                }
            }
        }
    }

    private func toolRow(_ tool: ScriptTool) -> some View {
        HStack(spacing: 8) {
            Text(tool.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: 132, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selectedID == tool.id ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selectedID == tool.id ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.14), lineWidth: 1)
        )
        .padding(.horizontal, 4)
        .contextMenu {
            ForEach(allTools) { menuTool in
                Button {
                    onToggleToolVisibility(menuTool.id)
                } label: {
                    Text(menuTitle(title: menuTool.title, shown: !isToolHidden(menuTool.id)))
                }
            }
        }
        .onTapGesture {
            onSelect(tool)
        }
    }

    private func menuTitle(title: String, shown: Bool) -> String {
        shown ? "✓  \(title)" : "    \(title)"
    }
}

private struct SidebarDropDelegate: DropDelegate {
    let targetIndex: Int
    let targetID: String
    @Binding var draggingID: String?
    let currentTools: [ScriptTool]
    let onMove: (_ source: Int, _ destination: Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        guard
            let draggingID,
            draggingID != targetID,
            let from = currentTools.firstIndex(where: { $0.id == draggingID }),
            let to = currentTools.firstIndex(where: { $0.id == targetID })
        else { return }

        let destination = to > from ? to + 1 : to
        onMove(from, destination)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
