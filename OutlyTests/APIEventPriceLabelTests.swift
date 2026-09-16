import XCTest
import Foundation
@testable import Outly

/// `APIEvent.priceLabel` in `.badgeText`: cena `nil` NI "Free" (zunanja prodaja/na vratih),
/// "FREE" se pokaze samo pri ceni 0 -- in samo na znacki (badgeText), priceLabel takrat
/// se vedno izpise formatirano ceno "0.00" (glej komentar v kodi in preveri spodaj).
final class APIEventPriceLabelTests: XCTestCase {

    /// `time_status` nadzoruje `isPast` neposredno (glej APIEvent.isPast), zato lahko teste
    /// pisemo brez odvisnosti od trenutnega datuma: "coming_soon" = ni pretekel, "popular" = pretekel.
    private func makeEvent(
        priceCents: Int? = nil,
        currency: String? = nil,
        ticketUrl: String? = nil,
        availability: String? = nil,
        capacity: Int? = nil,
        soldCount: Int = 0,
        timeStatus: String = "coming_soon"
    ) throws -> APIEvent {
        let priceJSON = priceCents.map { "\($0)" } ?? "null"
        let currencyJSON = currency.map { "\"\($0)\"" } ?? "null"
        let urlJSON = ticketUrl.map { "\"\($0)\"" } ?? "null"
        let availJSON = availability.map { "\"\($0)\"" } ?? "null"
        let capJSON = capacity.map { "\($0)" } ?? "null"
        let json = """
        {
            "id": 1,
            "club_id": 1,
            "title": "T",
            "description": "",
            "poster_url": "",
            "start_at": "2026-01-01T00:00:00.000Z",
            "end_at": null,
            "min_age": 18,
            "genres": [],
            "status": "published",
            "time_status": "\(timeStatus)",
            "ticket_price_cents": \(priceJSON),
            "currency": \(currencyJSON),
            "ticket_url": \(urlJSON),
            "capacity": \(capJSON),
            "sold_count": \(soldCount),
            "availability": \(availJSON)
        }
        """
        return try JSONDecoder().decode(APIEvent.self, from: Data(json.utf8))
    }

    // MARK: - priceLabel

    func testPriceLabelSoldOutShowsDash() throws {
        let e = try makeEvent(priceCents: 1600, availability: "sold_out")
        XCTAssertEqual(e.priceLabel, "—")
    }

    /// Centi -> "€16.00" (displayPrice uporablja String(format: "%.2f"), pika kot locilo,
    /// simbol brez presledka -- NE Denar.evri, ki je za prikaz zneskov drugje v aplikaciji).
    func testPriceLabelFormatsCentsAsEuros() throws {
        let e = try makeEvent(priceCents: 1600, currency: "EUR")
        XCTAssertEqual(e.priceLabel, "€16.00")
    }

    func testPriceLabelUsesCurrencySymbol() throws {
        let usd = try makeEvent(priceCents: 500, currency: "USD")
        XCTAssertEqual(usd.priceLabel, "$5.00")
        let gbp = try makeEvent(priceCents: 500, currency: "GBP")
        XCTAssertEqual(gbp.priceLabel, "£5.00")
        let unknown = try makeEvent(priceCents: 500, currency: "CHF")
        XCTAssertEqual(unknown.priceLabel, "CHF 5.00")
    }

    /// Manjkajoca "currency" -> privzeto EUR.
    func testPriceLabelDefaultsCurrencyToEUR() throws {
        let e = try makeEvent(priceCents: 1000, currency: nil)
        XCTAssertEqual(e.priceLabel, "€10.00")
    }

    /// KLJUCNO (CLAUDE.md #9): cena 0 NI izpisana kot "Free" v priceLabel -- izpise se
    /// formatirana cena "0.00". Beseda "Free"/"FREE" se pojavi samo v badgeText (glej spodaj).
    func testPriceLabelZeroCentsIsNotTheWordFree() throws {
        let e = try makeEvent(priceCents: 0, currency: "EUR")
        XCTAssertEqual(e.priceLabel, "€0.00")
        XCTAssertNotEqual(e.priceLabel, "Free")
    }

    /// Cena nil, brez zunanje povezave -> "At the door" (na vratih), NE "Free".
    func testPriceLabelNilPriceWithoutTicketUrlIsAtTheDoor() throws {
        let e = try makeEvent(priceCents: nil, ticketUrl: nil)
        XCTAssertEqual(e.priceLabel, "At the door")
    }

    /// Cena nil z zunanjo povezavo -> "Tickets" (prodaja zunaj Outlyja).
    func testPriceLabelNilPriceWithTicketUrlIsTickets() throws {
        let e = try makeEvent(priceCents: nil, ticketUrl: "https://tickets.example.com/x")
        XCTAssertEqual(e.priceLabel, "Tickets")
    }

    // MARK: - badgeText

    func testBadgeTextHiddenForPastEvents() throws {
        let e = try makeEvent(priceCents: 0, timeStatus: "popular")
        XCTAssertNil(e.badgeText)
    }

    func testBadgeTextSoldOut() throws {
        let e = try makeEvent(availability: "sold_out", timeStatus: "coming_soon")
        XCTAssertEqual(e.badgeText, "SOLD OUT")
    }

    func testBadgeTextLastOneWhenOneTicketLeft() throws {
        let e = try makeEvent(availability: "few_left", capacity: 10, soldCount: 9, timeStatus: "coming_soon")
        XCTAssertEqual(e.ticketsLeft, 1)
        XCTAssertEqual(e.badgeText, "LAST ONE")
    }

    /// Interpolirana lokalizacija ("\(n) LEFT") je odvisna od locale/tabele niti v testnem
    /// gostitelju -- preverimo vsebino namesto natancnega zapisa, da test ni krhek.
    func testBadgeTextShowsCountWhenFewLeft() throws {
        let e = try makeEvent(availability: "few_left", capacity: 10, soldCount: 7, timeStatus: "coming_soon")
        XCTAssertEqual(e.ticketsLeft, 3)
        let badge = try XCTUnwrap(e.badgeText)
        XCTAssertTrue(badge.contains("3"), "Pricakovano stevilo 3 v znacki, dobil: \(badge)")
        XCTAssertTrue(badge.contains("LEFT"), "Pricakovano besedo LEFT v znacki, dobil: \(badge)")
    }

    /// Cena 0 -> znacka "FREE" (za razliko od priceLabel, ki izpise "€0.00").
    func testBadgeTextFreeOnlyAtExactlyZero() throws {
        let free = try makeEvent(priceCents: 0, timeStatus: "coming_soon")
        XCTAssertEqual(free.badgeText, "FREE")

        let nilPrice = try makeEvent(priceCents: nil, ticketUrl: nil, timeStatus: "coming_soon")
        XCTAssertNotEqual(nilPrice.badgeText, "FREE")

        let paid = try makeEvent(priceCents: 1600, timeStatus: "coming_soon")
        XCTAssertNotEqual(paid.badgeText, "FREE")
    }

    func testBadgeTextNilForExternalTicketLink() throws {
        let e = try makeEvent(priceCents: nil, ticketUrl: "https://tickets.example.com", timeStatus: "coming_soon")
        XCTAssertNil(e.badgeText)
    }

    func testBadgeTextNilForNormallyPricedUpcomingEvent() throws {
        let e = try makeEvent(priceCents: 1600, timeStatus: "coming_soon")
        XCTAssertNil(e.badgeText)
    }
}
