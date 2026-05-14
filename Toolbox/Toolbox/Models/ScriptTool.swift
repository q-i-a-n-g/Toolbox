import Foundation

struct ScriptTool: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let scriptRelativePath: String
    let usesTextInput: Bool
    let defaultText: String
    let helpText: String?
    let helpFileName: String
    let configFileName: String

    static let bundledConfigFileName = "tool_config"

    static let fallbackTools: [ScriptTool] = [
        ScriptTool(
            id: "open-links",
            title: "批量打开链接",
            scriptRelativePath: "打开链接.command",
            usesTextInput: true,
            defaultText: "https://example.com/a\nhttps://example.com/b",
            helpText: "批量打开链接\n\n用法：\n1. 在上方输入多行链接内容。\n2. 点击“开始”。\n3. 每打开一批后，如需继续，在下方终端里按回车。\n",
            helpFileName: "open-links-help.txt",
            configFileName: "open-links.env"
        ),
        ScriptTool(
            id: "download-images",
            title: "图片批量下载",
            scriptRelativePath: "图片批量下载.command",
            usesTextInput: true,
            defaultText: "12 https://example.com/a.png\nhttps://example.com/b.png custom-name",
            helpText: "图片批量下载\n\n用法：\n1. 在上方输入原来 links.txt 的内容。\n2. 点击“开始”。\n3. 下载日志会在下方终端实时显示。\n",
            helpFileName: "download-images-help.txt",
            configFileName: "download-images.env"
        ),
        ScriptTool(
            id: "rename-images",
            title: "图片指定重命名",
            scriptRelativePath: "图片指定重命名.command",
            usesTextInput: true,
            defaultText: "001 a.png\n002 b.png",
            helpText: "图片指定重命名\n\n用法：\n1. 在上方输入映射内容。\n2. 点击“开始”。\n3. 按终端提示把目标文件夹路径粘贴到下方终端并回车。\n",
            helpFileName: "rename-images-help.txt",
            configFileName: "rename-images.env"
        ),
        ScriptTool(
            id: "stitch-images",
            title: "图片拼接",
            scriptRelativePath: "图片拼接.command",
            usesTextInput: false,
            defaultText: "",
            helpText: "图片拼接\n\n这个脚本主要依赖终端交互。\n点击“开始”后，按终端提示继续输入目录、模式或参数。\n",
            helpFileName: "stitch-images-help.txt",
            configFileName: "stitch-images.env"
        )
    ]

    static func loadConfiguredTools() -> [ScriptTool] {
        guard
            let url = Bundle.main.resourceURL?
                .appendingPathComponent("\(bundledConfigFileName).json"),
            let data = try? Data(contentsOf: url),
            let tools = try? JSONDecoder().decode([ScriptTool].self, from: data),
            !tools.isEmpty
        else {
            return fallbackTools
        }

        return tools
    }
}
