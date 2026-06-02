# Toolbox

macOS local toolbox skeleton for:

- 打开链接
- 批量下载
- 图片指定重命名
- 图片拼接

Current status:

- Xcode project skeleton created
- SwiftUI layout created
- Left and right panes are resizable
- Right side top and bottom panes are resizable
- Both right panes have their own maximize button
- Buttons are renamed to `开始` and `停止`
- `开始` is set as the default action
- Terminal area is a placeholder, not a full PTY terminal yet

Open with Xcode:

1. Open `Toolbox/Toolbox.xcodeproj`
2. If Xcode is installed but command line tools are still active, switch later with:
   `sudo xcode-select -s /Applications/Xcode.app`

Next implementation step:

- Replace `TerminalPaneView` with a real PTY-backed terminal view
- Bundle the existing `.command` scripts into the app resources
- Write text input to a temporary `links.txt`
- Start and stop scripts from `PTYTerminalService`
