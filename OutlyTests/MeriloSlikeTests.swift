import XCTest
import UIKit
@testable import Outly

/// Zrusitev build 303 (Home -> dogodek -> Search): posnetek za ozadje zavihka je imel merilo 0.25;
/// SwiftUI ob razresevanju `Image(uiImage:)` poklice `-[UIImage imageAsset]`, CoreUI merilo hrani kot
/// celo stevilo (0.25 -> 0) in vrze 'scale must be > 0'. Pomozne funkcije morajo vrniti nil ali sliko
/// z merilom >= 1 in velikostjo > 0 — brez okna, brez omrezja.
@MainActor
final class MeriloSlikeTests: XCTestCase {

    /// 40 x 80 pt pri merilu 1 (40 x 80 pikslov), brez okna.
    private func ostra() -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 80), format: f).image { k in
            UIColor.red.setFill()
            k.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        }
    }

    func testCetrtinskoMeriloNiVarnoZaPrikaz() throws {
        let cg = try XCTUnwrap(ostra().cgImage)
        let cetrt = UIImage(cgImage: cg, scale: 0.25, orientation: .up)
        XCTAssertFalse(cetrt.jeVarnaZaPrikaz)
        XCTAssertTrue(ostra().jeVarnaZaPrikaz)
        XCTAssertFalse(UIImage().jeVarnaZaPrikaz)
    }

    func testZaPrikazDaIstimPikslomMeriloEna() throws {
        let cg = try XCTUnwrap(ostra().cgImage)
        let cetrt = UIImage(cgImage: cg, scale: 0.25, orientation: .up)
        let varna = try XCTUnwrap(OzadnjaZameglitev.zaPrikaz(cetrt))
        XCTAssertEqual(varna.scale, 1)
        XCTAssertEqual(varna.cgImage?.width, 40)
        XCTAssertEqual(varna.cgImage?.height, 80)
        XCTAssertTrue(varna.jeVarnaZaPrikaz)
        // Klic, ki je v build 303 zrusil aplikacijo (sklad: -[UIImage imageAsset]).
        XCTAssertNotNil(varna.imageAsset)
    }

    func testZaPrikazVeljavnoSlikoVrneNespremenjeno() throws {
        let s = ostra()
        let varna = try XCTUnwrap(OzadnjaZameglitev.zaPrikaz(s))
        XCTAssertTrue(varna === s)
    }

    func testZaPrikazPraznaSlikaVrneNil() {
        XCTAssertNil(OzadnjaZameglitev.zaPrikaz(UIImage()))
    }

    func testPomanjsajZNicelnimVhodomVrneNil() {
        XCTAssertNil(OzadnjaZameglitev.pomanjsaj(UIImage(), naMerilo: 0.25))
        XCTAssertNil(OzadnjaZameglitev.pomanjsaj(ostra(), naMerilo: 0))
        XCTAssertNil(OzadnjaZameglitev.pomanjsaj(ostra(), naMerilo: -1))
    }

    /// Ista veriga kot odpriIzHome: pomanjsaj (0.25) -> zamegli -> zaPrikaz.
    func testVerigaOzadjaVrneVarnoSliko() throws {
        let majhen = try XCTUnwrap(OzadnjaZameglitev.pomanjsaj(ostra(), naMerilo: 0.25))
        XCTAssertEqual(majhen.scale, 0.25)
        XCTAssertEqual(majhen.cgImage?.width, 10)
        XCTAssertEqual(majhen.cgImage?.height, 20)
        let zamegljen = OzadnjaZameglitev.zamegli(majhen) ?? majhen
        let varna = try XCTUnwrap(OzadnjaZameglitev.zaPrikaz(zamegljen))
        XCTAssertTrue(varna.jeVarnaZaPrikaz)
        XCTAssertGreaterThanOrEqual(varna.scale, 1)
        XCTAssertNotNil(varna.imageAsset)
    }
}
