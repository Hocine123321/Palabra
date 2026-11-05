import UIKit

/// Small generated images for the effects (no assets to audition).
enum SoftSprites {
    /// A round soft-edged blob: `color` at the centre fading to clear.
    static func radial(_ color: UIColor, size: Int = 128, falloff: CGFloat = 1) -> UIImage {
        let side = CGFloat(size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let steps = 12
            var colors: [CGColor] = []
            var locations: [CGFloat] = []
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                colors.append(UIColor(red: r, green: g, blue: b, alpha: a * pow(1 - t, falloff * 2)).cgColor)
                locations.append(t)
            }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            let c = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: side / 2, options: [])
        }
    }
}
