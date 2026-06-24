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

struct RecognizedLine {
    let text: String
    let box: CGRect
}

func recognizeLines(in image: CGImage) throws -> [RecognizedLine] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false
    req.recognitionLanguages = ["zh-Hans", "en-US"]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([req])
    let obs = req.results ?? []
    return obs.compactMap { observation in
        guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return RecognizedLine(text: text, box: observation.boundingBox)
    }
}

do {
    let sorted = try recognizeLines(in: cgImage).sorted { lhs, rhs in
        if abs(lhs.box.midY - rhs.box.midY) > 0.012 {
            return lhs.box.midY > rhs.box.midY
        }
        return lhs.box.minX < rhs.box.minX
    }

    var lastText = ""
    var lastBox = CGRect.null
    for line in sorted {
        if line.text == lastText,
           abs(line.box.midY - lastBox.midY) < 0.01,
           abs(line.box.minX - lastBox.minX) < 0.04 {
            continue
        }
        print(line.text)
        lastText = line.text
        lastBox = line.box
    }
} catch {
    fputs("vision error: \(error)\n", stderr)
    exit(1)
}
