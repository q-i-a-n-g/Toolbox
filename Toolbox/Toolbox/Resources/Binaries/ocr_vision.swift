import Foundation
import Vision
import AppKit

if CommandLine.arguments.count < 2 {
    fputs("usage: ocr_vision.swift <image_path>\n", stderr)
    exit(2)
}

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
guard let img = NSImage(contentsOf: url) else {
    fputs("failed to load image\n", stderr)
    exit(1)
}

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let cgImage = rep.cgImage else {
    fputs("failed to get cgimage\n", stderr)
    exit(1)
}

func recognizeLines(in image: CGImage) throws -> [String] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false
    req.recognitionLanguages = ["zh-Hans", "en-US"]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([req])
    let obs = req.results ?? []
    return obs.compactMap { $0.topCandidates(1).first?.string }
}

let maxSliceHeight = 600
let sliceOverlap = 80
do {
    if cgImage.height <= maxSliceHeight {
        for line in try recognizeLines(in: cgImage) {
            print(line)
        }
    } else {
        var y = 0
        while y < cgImage.height {
            let height = min(maxSliceHeight, cgImage.height - y)
            let rect = CGRect(x: 0, y: y, width: cgImage.width, height: height)
            if let slice = cgImage.cropping(to: rect) {
                for line in try recognizeLines(in: slice) {
                    print(line)
                }
            }
            if y + height >= cgImage.height {
                break
            }
            y += maxSliceHeight - sliceOverlap
        }
    }
} catch {
    fputs("vision error: \(error)\n", stderr)
    exit(1)
}
