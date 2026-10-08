import Foundation

// Sken vstopnic brez povezave (backend issue #86). Vsi klici gredo skozi send(); klub je IZRECEN (`clubId` -> glava X-Outly-Club),
// ker globalni IzbraniKlub MyClubsView.load pobrise in bi zadnje posiljanje vrste slo brez glave (pregled M7).
// Poti (vse vloge v klubu, tudi vratar):
//   GET  /business/scan-key                   -> javni kljuc Ed25519 za preverjanje kod v2
//   GET  /business/events/:id/scan-list       -> vstopnice dogodka + prenesene serial-e (ETag/304 uredi URLSession sam)
//   POST /business/tickets/scan-batch         -> skeni, opravljeni brez povezave (vedno 200; rezultat za vsak element)

extension APIClient {

    func fetchScanKey(token: String, clubId: Int? = nil) async throws -> ScanKey {
        let data = try await send(path: "business/scan-key", method: "GET", token: token, clubId: clubId)
        return try decode(ScanKey.self, from: data)
    }

    /// Surov odgovor: SkenSeja ga zgosti (nespremenjen seznam se ne dekodira znova) in dekodira izven glavne niti.
    /// `sveze`: mimo predpomnilnika (brez If-None-Match, torej 200 s svezim `generated_at`); privzeto ETag/304.
    func fetchScanListData(token: String, eventId: Int, clubId: Int? = nil, sveze: Bool = false) async throws -> Data {
        try await send(path: "business/events/\(eventId)/scan-list", method: "GET", token: token, clubId: clubId,
                       cachePolicy: sveze ? .reloadIgnoringLocalCacheData : nil)
    }

    /// GET /business/events za izrecen klub (fetchMyBusinessEvents vzame globalni IzbraniKlub).
    func fetchBusinessEvents(token: String, clubId: Int?) async throws -> [APIEvent] {
        let data = try await send(path: "business/events", method: "GET", token: token, clubId: clubId)
        return try decode([APIEvent].self, from: data)
    }

    private struct ScanBatchOdgovor: Decodable {
        let results: [ScanBatchResult]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            results = (try? c.decodeIfPresent([ScanBatchResult].self, forKey: .results)) ?? []
        }
        enum CodingKeys: String, CodingKey { case results }
    }

    /// POST /business/tickets/scan-batch (najvec 500). `device_id` je UUID, ustvarjen enkrat na namestitev;
    /// `client_scan_id` je nov UUID za vsak sken (idempotentnost: ponovitev paketa je neskodljiva).
    func sendScanBatch(token: String, scans: [SkenVnos], deviceId: String, clubId: Int?) async throws -> [ScanBatchResult] {
        let elementi: [[String: Any]] = scans.map {
            [
                "client_scan_id": $0.clientScanId,
                "qr": $0.qr,
                "scanned_at": SkenCas.niz($0.scannedAt),
                "device_id": deviceId,
            ]
        }
        let data = try await send(path: "business/tickets/scan-batch", method: "POST", token: token, json: ["scans": elementi], clubId: clubId)
        return try decode(ScanBatchOdgovor.self, from: data).results
    }
}

/// Zivi odjemalec za SkenSeja. Locen od APIClient, da ga testi zamenjajo.
struct SkenApiZivi: SkenApi {
    func dogodki(token: String, klubId: Int?) async throws -> [SkenDogodek] {
        try await APIClient.shared.fetchBusinessEvents(token: token, clubId: klubId).map { SkenDogodek($0) }
    }

    func kljuc(token: String, klubId: Int?) async throws -> ScanKey {
        try await APIClient.shared.fetchScanKey(token: token, clubId: klubId)
    }

    func seznam(token: String, klubId: Int?, dogodekId: Int, sveze: Bool) async throws -> Data {
        try await APIClient.shared.fetchScanListData(token: token, eventId: dogodekId, clubId: klubId, sveze: sveze)
    }

    func paket(token: String, klubId: Int?, vnosi: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult] {
        try await APIClient.shared.sendScanBatch(token: token, scans: vnosi, deviceId: deviceId, clubId: klubId)
    }

    func spletniSken(token: String, klubId: Int?, qr: String, rok: Double) async throws -> ScanResult {
        try await APIClient.shared.scanTicket(token: token, qr: qr, clubId: klubId, timeout: rok)
    }
}
