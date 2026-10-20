import XCTest
import UIKit
@testable import Outly

/// ZACASEN POSKUS (ne za merge): ali UIImage z merilom 0.25 ob -[UIImage imageAsset] zrusi
/// proces z 'scale must be > 0' (CoreUI). Ce se ta test zrusi, je vzrok potrjen.
final class MeriloSlikeTests: XCTestCase {

    private func ostra() -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 80), format: f).image { k in
            UIColor.red.setFill()
            k.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        }
    }

    func testPoskus1MeriloEnaImageAsset() {
        let s = ostra()
        NSLog("POSKUS1 scale=%f", s.scale)
        _ = s.imageAsset
        NSLog("POSKUS1 OK")
    }

    func testPoskus2MeriloCetrtineImageAsset() {
        let s = UIImage(cgImage: ostra().cgImage!, scale: 0.25, orientation: .up)
        NSLog("POSKUS2 scale=%f", s.scale)
        _ = s.imageAsset
        NSLog("POSKUS2 OK brez zrusitve")
    }
}
