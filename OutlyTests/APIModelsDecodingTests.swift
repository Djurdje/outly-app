import XCTest
import Foundation
@testable import Outly

/// Dekodiranje modelov iz JSON-a, kot ga dejansko vraca backend: snake_case kljuci,
/// nova polja (bar_prices, gallery_urls, video_url, capacity, availability, time_status)
/// so lahko izpuscena (star backend) -- to ne sme podreti dekodiranja (CLAUDE.md pravilo #2).
final class APIModelsDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - APIEvent

    func testAPIEventDecodesAllFieldsFromBackendShape() throws {
        let json = """
        {
            "id": 42,
            "club_id": 7,
            "title": "Halloween Party",
            "description": "Strasljiv večer",
            "poster_url": "https://example.com/p.jpg",
            "start_at": "2026-10-31T22:00:00.000Z",
            "end_at": "2026-11-01T05:00:00.000Z",
            "min_age": 18,
            "genres": ["techno", "house"],
            "status": "published",
            "time_status": "coming_soon",
            "created_at": "2026-09-01T10:00:00.000Z",
            "ticket_price_cents": 1600,
            "currency": "EUR",
            "ticket_url": null,
            "capacity": 200,
            "sold_count": 150,
            "availability": "few_left"
        }
        """
        let e = try decode(APIEvent.self, json)
        XCTAssertEqual(e.id, 42)
        XCTAssertEqual(e.clubId, 7)
        XCTAssertEqual(e.title, "Halloween Party")
        XCTAssertEqual(e.genres, ["techno", "house"])
        XCTAssertEqual(e.timeStatus, "coming_soon")
        XCTAssertEqual(e.ticketPriceCents, 1600)
        XCTAssertEqual(e.currency, "EUR")
        XCTAssertNil(e.ticketUrl)
        XCTAssertEqual(e.capacity, 200)
        XCTAssertEqual(e.soldCount, 150)
        XCTAssertEqual(e.availability, "few_left")
    }

    /// Star backend (pred migracijo zaloge, publiko od septembra 2026): capacity, sold_count,
    /// availability, time_status, created_at manjkajo v celoti -- privzete vrednosti.
    func testAPIEventDecodesWithNewFieldsMissing() throws {
        let json = """
        {
            "id": 1,
            "club_id": 3,
            "title": "Stari dogodek",
            "description": "",
            "poster_url": "",
            "start_at": "2026-01-01T20:00:00.000Z",
            "end_at": null,
            "min_age": 18,
            "genres": [],
            "status": "published"
        }
        """
        let e = try decode(APIEvent.self, json)
        XCTAssertEqual(e.id, 1)
        XCTAssertNil(e.timeStatus)
        XCTAssertNil(e.createdAt)
        XCTAssertNil(e.ticketPriceCents)
        XCTAssertNil(e.currency)
        XCTAssertNil(e.ticketUrl)
        XCTAssertNil(e.capacity)
        XCTAssertEqual(e.soldCount, 0)
        XCTAssertNil(e.availability)
    }

    /// Samo "id" je edino polje brez decodeIfPresent -- vse ostalo mora imeti privzeto vrednost.
    func testAPIEventDecodesFromAlmostEmptyObject() throws {
        let e = try decode(APIEvent.self, #"{"id": 9}"#)
        XCTAssertEqual(e.id, 9)
        XCTAssertEqual(e.clubId, 0)
        XCTAssertEqual(e.title, "")
        XCTAssertEqual(e.minAge, 18)
        XCTAssertEqual(e.status, "published")
        XCTAssertEqual(e.genres, [])
    }

    /// GET /events?lite=true izpusti `description` (kljuc manjka, ne null): dekodiranje ne sme pasti.
    func testAPIEventDecodesLiteListWithoutDescription() throws {
        let json = """
        {
            "id": 11,
            "club_id": 2,
            "title": "Lahki seznam",
            "poster_url": "https://example.com/p.jpg",
            "start_at": "2026-10-31T22:00:00.000Z",
            "min_age": 18,
            "genres": ["techno"],
            "status": "published"
        }
        """
        let e = try decode(APIEvent.self, json)
        XCTAssertEqual(e.id, 11)
        XCTAssertEqual(e.title, "Lahki seznam")
        XCTAssertEqual(e.description, "")
    }

    // MARK: - APIClub (bar_prices, gallery_urls, video_url)

    func testAPIClubDecodesBarPricesAndGallery() throws {
        let json = """
        {
            "id": 5,
            "name": "Klub Noc",
            "logo_url": "https://x/logo.png",
            "banner_url": "https://x/banner.png",
            "description": "Najboljsi klub",
            "contact_email": "info@klub.si",
            "contact_phone": "+38640000000",
            "instagram": "@klubnoc",
            "website": "https://klub.si",
            "address": "Titova 1",
            "city": "Maribor",
            "country": "SI",
            "lat": 46.5547,
            "lng": 15.6459,
            "min_age": 18,
            "genres": ["house"],
            "created_at": "2026-01-01T00:00:00.000Z",
            "bar_prices": [
                {"name": "Pivo", "price_cents": 350, "category": "Pijaca"},
                {"name": "Voda", "price_cents": 200}
            ],
            "gallery_urls": ["https://x/1.jpg", "https://x/2.jpg", ""],
            "video_url": "https://x/video.mp4"
        }
        """
        let c = try decode(APIClub.self, json)
        XCTAssertEqual(c.id, 5)
        XCTAssertEqual(c.barPrices.count, 2)
        XCTAssertEqual(c.barPrices[0].name, "Pivo")
        XCTAssertEqual(c.barPrices[0].priceCents, 350)
        XCTAssertEqual(c.barPrices[0].category, "Pijaca")
        XCTAssertEqual(c.barPrices[1].category, nil)
        // Prazni niz v gallery_urls se izfiltrira.
        XCTAssertEqual(c.galleryUrls, ["https://x/1.jpg", "https://x/2.jpg"])
        XCTAssertEqual(c.videoUrl, "https://x/video.mp4")
        // Galerija ni prazna -> slideshowUrls uporabi galerijo, ne pasice.
        XCTAssertEqual(c.slideshowUrls, c.galleryUrls)
    }

    /// Klub pred migracijo 014/015: bar_prices, gallery_urls, video_url sploh ne obstajajo.
    func testAPIClubDecodesWithoutBarPricesOrGallery() throws {
        let json = """
        {
            "id": 6,
            "name": "Star klub",
            "banner_url": "https://x/banner.png"
        }
        """
        let c = try decode(APIClub.self, json)
        XCTAssertEqual(c.barPrices, [])
        XCTAssertEqual(c.galleryUrls, [])
        XCTAssertEqual(c.videoUrl, "")
        // Brez galerije -> slideshowUrls pade nazaj na pasico.
        XCTAssertEqual(c.slideshowUrls, ["https://x/banner.png"])
    }

    func testAPIClubSlideshowEmptyWhenNoBannerNoGallery() throws {
        let c = try decode(APIClub.self, #"{"id": 7}"#)
        XCTAssertEqual(c.slideshowUrls, [])
    }

    // MARK: - BarPriceItem

    func testBarPriceItemTrimsAndNilsEmptyCategory() throws {
        let item = try decode(BarPriceItem.self, #"{"name": "Gin Tonic", "price_cents": 700, "category": "   "}"#)
        XCTAssertEqual(item.name, "Gin Tonic")
        XCTAssertEqual(item.priceCents, 700)
        XCTAssertNil(item.category)
    }
}
