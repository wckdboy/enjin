import Foundation

public enum PictureKind: String, Codable, Sendable {
    /// A real photo, painting, map or diagram (Wikipedia/Commons, credited).
    case photo
    /// Made on the device (Image Playground) for ideas that have no real picture.
    case illustration
}

/// Makes an illustration for a phrase, on the device. Nil when unavailable.
public protocol ImageGenerator: Sendable {
    func generate(_ prompt: String) async -> FoundImage?
}

/// Gives every imported picture the same look (the "Enjin print" shader).
public protocol ImageStylizer: Sendable {
    func stylize(_ image: FoundImage) async -> FoundImage
}

/// Where a card's picture comes from: facts get real photos first, stubs and
/// the kid's own ideas get illustrations first; each falls back to the other.
/// Everything passes through the stylizer so the canvas looks like one book.
public struct PicturePipeline: Sendable {
    public var photos: ImageFinder?
    public var illustrations: ImageGenerator?
    public var stylizer: ImageStylizer?

    public init(photos: ImageFinder?, illustrations: ImageGenerator? = nil, stylizer: ImageStylizer? = nil) {
        self.photos = photos
        self.illustrations = illustrations
        self.stylizer = stylizer
    }

    public var isEmpty: Bool { photos == nil && illustrations == nil }

    public static func preferredKind(for card: StoredCard) -> PictureKind {
        if let asked = card.imagePrefer { return asked }
        return card.state == .stub || card.createdBy == .kid || card.type == .note ? .illustration : .photo
    }

    public func picture(for query: String, prefer: PictureKind, excluding: Set<String>) async -> (FoundImage, PictureKind)? {
        for kind in prefer == .photo ? [PictureKind.photo, .illustration] : [.illustration, .photo] {
            let found: FoundImage? = switch kind {
            case .photo: try? await photos?.find(query, excluding: excluding)
            case .illustration: await illustrations?.generate(query)
            }
            guard let found else { continue }
            return (await stylizer?.stylize(found) ?? found, kind)
        }
        return nil
    }
}
