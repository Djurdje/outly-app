import XCTest
import Foundation
import UIKit
@testable import Outly

/// Geometrija izreza bannerja dogodka in izhodne velikosti (outly-backend#400): velik 4:5 -> 1080 x 1350,
/// majhen 3:4 -> 1080 x 1440, manjse slike se ne povecujejo, v izrezu ni praznega roba.
final class BannerIzrezTests: XCTestCase {

    private let eps: CGFloat = 0.001

    // MARK: - Izhodna velikost

    func testIzhodVelikStaTocno1080x1350() {
        let o = BannerIzrez.izhodnaVelikost(izrezSirina: 1600, vrsta: .velik)
        XCTAssertEqual(o.sirina, 1080)
        XCTAssertEqual(o.visina, 1350)
    }

    func testIzhodMajhenJeTocno1080x1440() {
        let o = BannerIzrez.izhodnaVelikost(izrezSirina: 1500, vrsta: .majhen)
        XCTAssertEqual(o.sirina, 1080)
        XCTAssertEqual(o.visina, 1440)
    }

    func testManjseSlikeSeNePovecujejo() {
        // Slika 300 x 200: izrez majhen 3:4 je 150 x 200 -> izhod 150 x 200 (ne 1080).
        let izrez = IzrezStanje().izrez(slika: CGSize(width: 300, height: 200), razmerje: VrstaBannerja.majhen.razmerje)
        XCTAssertEqual(izrez.width, 150, accuracy: eps)
        XCTAssertEqual(izrez.height, 200, accuracy: eps)
        let o = BannerIzrez.izhodnaVelikost(izrezSirina: izrez.width, vrsta: .majhen)
        XCTAssertEqual(o.sirina, 150)
        XCTAssertEqual(o.visina, 200)

        // Velik 4:5 iz 300 x 200: izrez 160 x 200 -> 160 x 200.
        let v = IzrezStanje().izrez(slika: CGSize(width: 300, height: 200), razmerje: VrstaBannerja.velik.razmerje)
        let ov = BannerIzrez.izhodnaVelikost(izrezSirina: v.width, vrsta: .velik)
        XCTAssertEqual(ov.sirina, 160)
        XCTAssertEqual(ov.visina, 200)
    }

    func testIzhodRazmerjeJeVednoNatancno() {
        for sirina in stride(from: 1, through: 3000, by: 37) {
            let v = BannerIzrez.izhodnaVelikost(izrezSirina: CGFloat(sirina), vrsta: .velik)
            XCTAssertEqual(v.sirina * 5, v.visina * 4, "4:5 pri \(sirina)")
            XCTAssertLessThanOrEqual(v.sirina, 1080)
            let m = BannerIzrez.izhodnaVelikost(izrezSirina: CGFloat(sirina), vrsta: .majhen)
            XCTAssertEqual(m.sirina * 4, m.visina * 3, "3:4 pri \(sirina)")
            XCTAssertLessThanOrEqual(m.sirina, 1080)
        }
    }

    // MARK: - Izrez

    func testPrivzetiIzrezJeSredina() {
        let r = IzrezStanje().izrez(slika: CGSize(width: 2000, height: 2000), razmerje: VrstaBannerja.velik.razmerje)
        XCTAssertEqual(r.width, 1600, accuracy: eps)
        XCTAssertEqual(r.height, 2000, accuracy: eps)
        XCTAssertEqual(r.midX, 1000, accuracy: eps)
        XCTAssertEqual(r.midY, 1000, accuracy: eps)
    }

    func testZeloVisokaSlika1000x5000() {
        // 4:5: sirina 1000, visina 1250, sredina po visini.
        let r = IzrezStanje().izrez(slika: CGSize(width: 1000, height: 5000), razmerje: VrstaBannerja.velik.razmerje)
        XCTAssertEqual(r.width, 1000, accuracy: eps)
        XCTAssertEqual(r.height, 1250, accuracy: eps)
        XCTAssertEqual(r.midY, 2500, accuracy: eps)
        XCTAssertGreaterThanOrEqual(r.minY, 0)
        XCTAssertLessThanOrEqual(r.maxY, 5000 + eps)
    }

    func testPanorama3072x600() {
        // 3:4: visina 600, sirina 450.
        let r = IzrezStanje().izrez(slika: CGSize(width: 3072, height: 600), razmerje: VrstaBannerja.majhen.razmerje)
        XCTAssertEqual(r.width, 450, accuracy: eps)
        XCTAssertEqual(r.height, 600, accuracy: eps)
        XCTAssertEqual(r.midX, 1536, accuracy: eps)
    }

    func testRobniOdmikNiPraznegaRoba() {
        let slika = CGSize(width: 4000, height: 2000)
        let razmerje = VrstaBannerja.majhen.razmerje
        for odmik in [CGSize(width: 99, height: 99), CGSize(width: -99, height: -99), CGSize(width: 99, height: -99)] {
            for zoom in [1, 1.5, 4] as [CGFloat] {
                var s = IzrezStanje()
                s.zoom = zoom
                s.odmik = odmik
                let r = s.izrez(slika: slika, razmerje: razmerje)
                XCTAssertGreaterThanOrEqual(r.minX, -eps)
                XCTAssertGreaterThanOrEqual(r.minY, -eps)
                XCTAssertLessThanOrEqual(r.maxX, slika.width + eps)
                XCTAssertLessThanOrEqual(r.maxY, slika.height + eps)
                // Razmerje izreza ostane natancno.
                XCTAssertEqual(r.width / r.height, razmerje, accuracy: 0.0001)
            }
        }
        var levo = IzrezStanje(); levo.odmik = CGSize(width: 99, height: 0)
        XCTAssertEqual(levo.izrez(slika: slika, razmerje: razmerje).minX, 0, accuracy: eps)
        var desno = IzrezStanje(); desno.odmik = CGSize(width: -99, height: 0)
        XCTAssertEqual(desno.izrez(slika: slika, razmerje: razmerje).maxX, 4000, accuracy: eps)
    }

    func testNajvecjaPovecavaJe4InNajmanjsa1() {
        var s = IzrezStanje()
        s.zoom = 99
        XCTAssertEqual(s.omejen(slika: CGSize(width: 2000, height: 2000), razmerje: 0.8).zoom, IzrezStanje.najvecZoom)
        s.zoom = 0.2
        XCTAssertEqual(s.omejen(slika: CGSize(width: 2000, height: 2000), razmerje: 0.8).zoom, 1)
        // Pri najvecji povecavi je izrez stirikrat ozji.
        var z = IzrezStanje(); z.zoom = 4
        let r = z.izrez(slika: CGSize(width: 2000, height: 2000), razmerje: VrstaBannerja.velik.razmerje)
        XCTAssertEqual(r.width, 400, accuracy: eps)
        XCTAssertEqual(r.height, 500, accuracy: eps)
    }

    func testNeveljavnaSlikaNePadeIn() {
        let r = IzrezStanje().izrez(slika: .zero, razmerje: 0.8)
        XCTAssertEqual(r.size, .zero)
        XCTAssertEqual(IzrezStanje().omejen(slika: .zero, razmerje: 0.8), IzrezStanje())
    }

    // MARK: - Meja dekodiranja

    func testMejaDekodiranja() {
        // Navadna fotografija 4000 x 3000: krajsa stranica 2160 bi dala 2880 -> spodnja meja 3072, a ne vec od izvirnika.
        XCTAssertEqual(BannerIzrez.mejaDekodiranja(sirina: 4000, visina: 3000), 3072)
        // Visoka 1000 x 5000: izvirnik je manjsi od 3072? ne, 5000 > 3072; potrebno 10800 -> zgoraj 6144, nikoli vec od izvirnika.
        XCTAssertEqual(BannerIzrez.mejaDekodiranja(sirina: 1000, visina: 5000), 5000)
        // Velika podolgovata 3000 x 12000: potrebno 8640 -> 6144.
        XCTAssertEqual(BannerIzrez.mejaDekodiranja(sirina: 3000, visina: 12000), 6144)
        // Podolgovata 2400 x 4800: potrebno 4320, izvirnik 4800 -> 4320.
        XCTAssertEqual(BannerIzrez.mejaDekodiranja(sirina: 2400, visina: 4800), 4320)
        // Majhna 300 x 200: brez povecevanja.
        XCTAssertEqual(BannerIzrez.mejaDekodiranja(sirina: 300, visina: 200), 300)
        // Neveljavno: privzeto.
        XCTAssertEqual(BannerIzrez.mejaDekodiranja(sirina: 0, visina: 0), 3072)
    }
}

/// Meja dekodiranja iz glave datoteke (ImageIO vrne NSNumber). UIKit za izdelavo PNG -> glavna nit.
@MainActor
final class MejaDekodiranjaPodatkiTests: XCTestCase {
    func testMajhenPng1x2Px() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let slika = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 2), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 2))
        }
        let png = try XCTUnwrap(slika.pngData())
        // Daljsa stranica 2 px, brez povecevanja.
        XCTAssertEqual(BannerIzrez.mejaDekodiranja(podatki: png), 2)
    }

    func testNeberljivPodatkiDajoPrivzeto() {
        XCTAssertEqual(BannerIzrez.mejaDekodiranja(podatki: Data([0, 1, 2, 3])), 3072)
    }
}

/// Dekodiranje `poster_card_url` (star backend polja ne vrne -> "", pravilo 2) in izbira slike za majhne prikaze.
@MainActor
final class PosterCardUrlDecodingTests: XCTestCase {

    private func event(_ dodatno: String) throws -> APIEvent {
        let json = """
        {"id": 1, "club_id": 2, "title": "T", "poster_url": "https://example.com/velik.jpg",
         "start_at": "2026-10-31T22:00:00.000Z"\(dodatno)}
        """
        return try JSONDecoder().decode(APIEvent.self, from: Data(json.utf8))
    }

    func testBrezPolja_posterCardUrlJePrazenInSmallJeVelik() throws {
        let e = try event("")
        XCTAssertEqual(e.posterCardUrl, "")
        XCTAssertEqual(e.posterSmallUrl, e.posterUrl)
        XCTAssertEqual(e.posterSmallUrl, "https://example.com/velik.jpg")
    }

    func testPrazenNizJeKotManjkajoce() throws {
        let e = try event(", \"poster_card_url\": \"\"")
        XCTAssertEqual(e.posterSmallUrl, "https://example.com/velik.jpg")
    }

    func testSPoljem_smallJeCard() throws {
        let e = try event(", \"poster_card_url\": \"https://example.com/kartica.jpg\"")
        XCTAssertEqual(e.posterCardUrl, "https://example.com/kartica.jpg")
        XCTAssertEqual(e.posterSmallUrl, e.posterCardUrl)
        XCTAssertEqual(e.posterUrl, "https://example.com/velik.jpg")
    }

    func testVstopnicaInGuestListaTudiBrezPolja() throws {
        let t = try JSONDecoder().decode(APITicket.self, from: Data(#"{"id": 5, "poster_url": "https://example.com/v.jpg"}"#.utf8))
        XCTAssertEqual(t.posterSmallUrl, "https://example.com/v.jpg")
        let g = try JSONDecoder().decode(GuestListEvent.self, from: Data(#"{"id": 5, "poster_url": "https://example.com/v.jpg", "poster_card_url": "https://example.com/k.jpg"}"#.utf8))
        XCTAssertEqual(g.posterSmallUrl, "https://example.com/k.jpg")
    }
}
