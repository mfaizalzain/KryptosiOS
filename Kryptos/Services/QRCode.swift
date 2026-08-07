import CoreImage.CIFilterBuiltins
import UIKit

enum QRCode {
    private static let cache = NSCache<NSString, UIImage>()

    static func makeImage(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let cacheKey = string as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard
            let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
            let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }
        
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
