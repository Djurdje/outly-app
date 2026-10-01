import Foundation

// Sken vstopnic brez povezave (backend issue #86). Vsi klici gredo skozi send(); glavo X-Outly-Club doda send() iz IzbraniKlub.
// Poti (vse vloge v klubu, tudi vratar):
//   GET  /business/scan-key                   -> javni kljuc Ed25519 za preverjanje kod v2
//   GET  /business/events/:id/scan-list       -> vstopnice dogodka + prenesene serial-e (ETag/304 uredi URLSession sam)
//   POST /business/tickets/scan-batch         -> skeni, opravljeni brez povezave (vedno 200; rezultat za vsak element)

extension APIClient {

    func fetchScanKey(token: String) async throws -> ScanKey {
        let data = try await send(path: "business/scan-key", method: "GET", token: token)
        return try decode(ScanKey.self, from: data)
    }

    func fetchScanList(token: String, eventId: Int) async throws -> ScanList {
        let data = try await send(path: "business/events/\(eventId)/scan-list", method: "GET", token: token)
        return try decode(ScanList.self, from: data)
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
    func sendScanBatch(token: String, scans: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult] {
        let elementi: [[String: Any]] = scans.map {
            [
                "client_scan_id": $0.clientScanId,
                "qr": $0.qr,
                "scanned_at": SkenCas.niz($0.scannedAt),
                "device_id": deviceId,
            ]
        }
        let data = try await send(path: "business/tickets/scan-batch", method: "POST", token: token, json: ["scans": elementi])
        return try decode(ScanBatchOdgovor.self, from: data).results
    }
}

/// Zivi odjemalec za SkenSeja. Locen od APIClient, da ga testi zamenjajo.
struct SkenApiZivi: SkenApi {
    func dogodki(token: String) async throws -> [SkenDogodek] {
        try await APIClient.shared.fetchMyBusinessEvents(token: token).map { SkenDogodek($0) }
    }

    func kljuc(token: String) async throws -> ScanKey {
        try await APIClient.shared.fetchScanKey(token: token)
    }

    func seznam(token: String, dogodekId: Int) async throws -> ScanList {
        try await APIClient.shared.fetchScanList(token: token, eventId: dogodekId)
    }

    func paket(token: String, vnosi: [SkenVnos], deviceId: String) async throws -> [ScanBatchResult] {
        try await APIClient.shared.sendScanBatch(token: token, scans: vnosi, deviceId: deviceId)
    }

    func spletniSken(token: String, qr: String) async throws -> ScanResult {
        try await APIClient.shared.scanTicket(token: token, qr: qr)
    }
}
