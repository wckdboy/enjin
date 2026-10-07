import UIKit
import Vision

/// Reads what the explorer wrote with the Pencil: on-device handwriting recognition (Vision), free and
/// private. Drawings come back with little or no text; writing comes back as text Enjin can answer.
enum HandwritingReader {
    struct Reading {
        var text: String
        /// Mean confidence of the lines read (0...1).
        var confidence: Float
        /// Looks like writing (worth answering), not a drawing with a label or two.
        var isWriting: Bool { confidence >= 0.45 && (text.split(separator: " ").count >= 2 || text.count >= 8) }
    }

    static func read(_ png: Data) async -> Reading? {
        guard let cg = UIImage(data: png)?.cgImage else { return nil }
        return await withCheckedContinuation { done in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first }
                guard !lines.isEmpty else { return done.resume(returning: nil) }
                let text = lines.map(\.string).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                let confidence = lines.map(\.confidence).reduce(0, +) / Float(lines.count)
                done.resume(returning: text.isEmpty ? nil : Reading(text: text, confidence: confidence))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "da-DK"]
            do {
                try VNImageRequestHandler(cgImage: cg).perform([request])
            } catch {
                done.resume(returning: nil)
            }
        }
    }
}
