import SwiftUI

struct WeeklyCheckPane: View {
    @Binding var files: [URL]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("周检制表")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            WeeklyCheckDropZoneView(files: $files)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }
}

struct WeeklyCheckDropZoneView: View {
    @Binding var files: [URL]
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                .background(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
            
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.largeTitle)
                    .foregroundColor(isHovering ? .accentColor : .secondary)
                
                if !files.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(files.prefix(3), id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if files.count > 3 {
                            Text("等共 \(files.count) 个文件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("每日任务分配表（AI、答题卡） 拖到这里")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .onDrop(of: [.fileURL], isTargeted: $isHovering) { providers in
            var newFiles: [URL] = []
            let group = DispatchGroup()
            
            for provider in providers {
                group.enter()
                provider.loadObject(ofClass: URL.self) { url, _ in
                    DispatchQueue.main.async {
                        defer { group.leave() }
                        guard let url = url else { return }
                        var isDir: ObjCBool = false
                        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return }
                        let ext = url.pathExtension.lowercased()
                        guard ext == "xlsx" || ext == "xls" else { return }
                        newFiles.append(url)
                    }
                }
            }
            
            group.notify(queue: .main) {
                guard !newFiles.isEmpty else { return }
                var seen = Set(self.files.map { $0.path })
                var merged = self.files
                for url in newFiles where !seen.contains(url.path) {
                    seen.insert(url.path)
                    merged.append(url)
                }
                self.files = merged
            }
            return true
        }
    }
}
