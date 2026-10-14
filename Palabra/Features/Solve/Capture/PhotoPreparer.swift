import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks a camera photo before it is sent anywhere: a 12 MP photo is several MB, a 1600 px JPEG is a few hundred KB
/// and reads just as well. Applies the EXIF rotation, so the picture goes out upright.
enum PhotoPreparer {
    static let maxPixelSize = 1600
    static let jpegQuality = 0.8

    static func prepare(_ data: Data) -> AIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else { return nil }
        return AIImage(data: output as Data, mimeType: "image/jpeg")
    }
}
