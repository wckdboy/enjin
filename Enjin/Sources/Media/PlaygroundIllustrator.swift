import EnjinKit
import Foundation
import ImageIO
import ImagePlayground
import os
import UniformTypeIdentifiers

/// On-device illustrations with Image Playground, for ideas and stubs that
/// have no real photo. Quietly returns nil where Image Playground isn't
/// available (no Apple Intelligence, simulator), so photos are used instead.
actor PlaygroundIllustrator: ImageGenerator {
    private var creator: ImageCreator?
    private var unavailable = false
    private let log = Logger(subsystem: "cc.wckd.enjin", category: "illustrate")

    func generate(_ prompt: String) async -> FoundImage? {
        guard !unavailable else { return nil }
        do {
            if creator == nil { creator = try await ImageCreator() }
            guard let creator else { return nil }
            let style = creator.availableStyles.contains(.illustration) ? ImagePlaygroundStyle.illustration : creator.availableStyles.first
            guard let style else { return nil }
            for try await created in creator.images(for: [.text(prompt)], style: style, limit: 1) {
                let out = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
                CGImageDestinationAddImage(dest, created.cgImage, nil)
                guard CGImageDestinationFinalize(dest) else { return nil }
                return FoundImage(data: out as Data, mimeType: "image/png", width: created.cgImage.width, height: created.cgImage.height,
                                  credit: "Illustration made on this iPad", sourceURL: "generated:\(UUID().uuidString)")
            }
            return nil
        } catch ImageCreator.Error.notSupported {
            unavailable = true
            log.info("Image Playground not supported here; using photos only")
            return nil
        } catch {
            log.error("illustration failed: \(error.localizedDescription)")
            return nil
        }
    }
}
