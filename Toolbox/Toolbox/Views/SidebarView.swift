import SwiftUI

struct SidebarView: View {
    let tools: [ScriptTool]
    let selectedID: String
    let onSelect: (ScriptTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("工具箱")
                .font(.title3.bold())
                .padding(.leading, 6)
                .foregroundColor(Color.white.opacity(0.92))

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tools) { tool in
                        HStack {
                            Text(tool.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
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
                        .onTapGesture {
                            onSelect(tool)
                        }
                    }
                }
            }
        }
    }
}
