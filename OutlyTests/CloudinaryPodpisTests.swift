import XCTest
import Foundation
import AVFoundation
@testable import Outly

/// outly-backend#257: odjemalec poslje Cloudinaryju natanko podpisane parametre (iz odgovora backenda).
/// outly-app#106: prepoznava lokacijskih metapodatkov in vsebnika videa (brez pravega izvoza).
@MainActor
final class CloudinaryPodpisTests: XCTestCase {

    private func podpis(_ json: String) throws -> CloudinarySignature {
        try JSONDecoder().decode(CloudinarySignature.self, from: Data(json.utf8))
    }

    private let osnova = """
    "timestamp": 1757193600, "signature": "abc", "apiKey": "k", "cloudName": "c",
    "folder": "outly", "publicId": "outly/u42/1757193600-3f9a1c2b"
    """

    private func polja(_ p: CloudinarySignature) -> [String: String] {
        Dictionary(uniqueKeysWithValues: p.podpisaniParametri.map { ($0.ime, $0.vrednost) })
    }

    func testDanasnjiBackendPosljeTriPodpisaneParametre() throws {
        let p = try podpis("{\(osnova)}")
        XCTAssertEqual(polja(p), [
            "folder": "outly",
            "public_id": "outly/u42/1757193600-3f9a1c2b",
            "timestamp": "1757193600",
        ])
    }

    func testNovoPoljeBackendaSePoslje() throws {
        let p = try podpis("{\(osnova), \"allowedFormats\": [\"jpg\", \"png\"], \"resourceType\": \"video\", \"prazno\": null}")
        XCTAssertEqual(polja(p), [
            "folder": "outly",
            "public_id": "outly/u42/1757193600-3f9a1c2b",
            "timestamp": "1757193600",
            "allowed_formats": "jpg,png",
        ])
    }

    func testNepodpisanaPoljaNikoliMedParametri() throws {
        let p = try podpis("{\(osnova), \"api_key\": \"x\", \"cloud_name\": \"y\", \"resource_type\": \"image\"}")
        let imena = Set(p.podpisaniParametri.map { $0.ime })
        XCTAssertEqual(imena, ["folder", "public_id", "timestamp"])
    }

    func testNeznanaOblikaNePodreDekodiranja() throws {
        let p = try podpis("{\(osnova), \"x\": {\"y\": 1}}")
        XCTAssertEqual(p.podpisaniParametri.count, 3)
    }

    func testVSnake() {
        XCTAssertEqual(CloudinarySignature.vSnake("publicId"), "public_id")
        XCTAssertEqual(CloudinarySignature.vSnake("allowedFormats"), "allowed_formats")
        XCTAssertEqual(CloudinarySignature.vSnake("folder"), "folder")
    }

    func testLokacijskiKljuci() {
        XCTAssertTrue(VideoZaNalaganje.jeLokacijskiKljuc("mdta/com.apple.quicktime.location.ISO6709"))
        XCTAssertTrue(VideoZaNalaganje.jeLokacijskiKljuc("udta/\u{00A9}xyz"))
        XCTAssertFalse(VideoZaNalaganje.jeLokacijskiKljuc("mdta/com.apple.quicktime.make"))
    }

    func testSamoVideoInZvokStaDovoljeniSledi() {
        XCTAssertTrue(VideoZaNalaganje.jeVideoAliZvok(.video))
        XCTAssertTrue(VideoZaNalaganje.jeVideoAliZvok(.audio))
        XCTAssertFalse(VideoZaNalaganje.jeVideoAliZvok(.metadata))
    }

    func testVhodnaKoncnica() {
        let mov = Data([0, 0, 0, 20] + Array("ftypqt  ".utf8))
        let mp4 = Data([0, 0, 0, 20] + Array("ftypisom".utf8))
        XCTAssertEqual(VideoZaNalaganje.vhodnaKoncnica(mov), "mov")
        XCTAssertEqual(VideoZaNalaganje.vhodnaKoncnica(mp4), "mp4")
        XCTAssertEqual(VideoZaNalaganje.vhodnaKoncnica(Data([1, 2, 3])), "mov")
    }
}
