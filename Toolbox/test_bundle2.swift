import Foundation
let bundlePath = "/Users/liu/Desktop/Toolbox.app"
guard let bundle = Bundle(path: bundlePath) else {
    print("Failed to load bundle")
    exit(1)
}
let url = bundle.url(forResource: "打开链接.command", withExtension: nil, subdirectory: "Scripts")
print("URL: \(String(describing: url))")
