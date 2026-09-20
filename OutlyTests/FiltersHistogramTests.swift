import XCTest
import Foundation
@testable import Outly

/// Filtri (20. 9.): histogram steje dejanske vrednosti po intervalih (brez dogodkov = 0),
/// razdalja je razpon od-do, "Use my preferences" ob izklopu vrne privzete vrednosti.
final class FiltersHistogramTests: XCTestCase {

    func testHistogramStejeVrednostiPoIntervalih() {
        // 0...100 v 10 intervalov po 10: 5 -> [0], 15 -> [1], 100 -> zadnji, 150 -> se ne steje.
        let counts = Histogram.prestej([5, 7, 15, 100, 150, -1], range: 0...100, bins: 10)
        XCTAssertEqual(counts.count, 10)
        XCTAssertEqual(counts[0], 2)
        XCTAssertEqual(counts[1], 1)
        XCTAssertEqual(counts[9], 1)
        XCTAssertEqual(counts.reduce(0, +), 4)
    }

    func testHistogramBrezVrednostiJeBrezStolpcev() {
        XCTAssertEqual(Histogram.prestej([], range: 0...100, bins: 4), [0, 0, 0, 0])
        XCTAssertEqual(Histogram.prestej([1, 2], range: 0...100, bins: 0), [])
    }

    func testPrivzetiFiltriNisoAktivniInRazdaljaJeRazpon() throws {
        XCTAssertFalse(EventFilters.privzeti.jeAktiven)
        var f = EventFilters.privzeti
        f.minDistanceKm = 5
        f.maxDistanceKm = 30
        XCTAssertTrue(f.jeAktiven)

        // Dekodiranje APIClub je obrambno (manjkajoci kljuci dobijo privzete vrednosti).
        let club = try JSONDecoder().decode(APIClub.self, from: Data(#"{"id": 1, "city": "Ljubljana"}"#.utf8))
        XCTAssertFalse(f.ustreza(club, razdaljaKm: 2))
        XCTAssertTrue(f.ustreza(club, razdaljaKm: 10))
        XCTAssertFalse(f.ustreza(club, razdaljaKm: 40))
        // Neznana razdalja ne izloci.
        XCTAssertTrue(f.ustreza(club, razdaljaKm: nil))
    }
}
