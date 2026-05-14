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

let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = false
req.recognitionLanguages = ["zh-Hans", "en-US"]

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([req])
    let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
    for o in obs {
        if let c = o.topCandidates(1).first {
            print(c.string)
        }
    }
} catch {
    fputs("vision error: \(error)\n", stderr)
    exit(1)
}
