import Foundation
import CryptoKit

// Sken brez povezave (backend issue #86, 1. 10. 2026): razclenjevanje in preverjanje kod QR.
//
// Koda v2: "o2." + base64url(JSON) + "." + base64url(podpis Ed25519, 64 B).
// Podpisano je UTF-8 besedilo vsega pred zadnjo piko ("o2.<b64>"). JSON: { v: 2, t: serial, e: event_id, i: ustvarjena, k: kid }.
// Koda v1 (stara): base64url(JSON) + "." + HMAC; JSON { v: 1, t: serial, e: event_id, i: ustvarjena }. Podpisa (HMAC) telefon NE more
// preveriti (skrivnost je samo na strezniku), telo pa lahko prebere: ni berljivo ali ni v==1 -> neveljavna koda.
// Nic od tega ne vrze izjeme: koda je vhod neznane osebe na vratih.

/// Telo kode (podpisano pri v2, nepreverljivo pri v1).
struct SkenTelo: Equatable {
    /// Serial vstopnice (UUID, male crke), kot ga hrani streznik.
    let serial: String
    let eventId: Int
    /// Id kljuca, s katerim je podpisana koda v2; pri v1 nil.
    let kid: String?
}

/// Razclenjena koda. Podpis pri `.v2` je razclenjen, NI se preverjen: poklici `SkenPodpis.preveri`.
enum SkenKoda: Equatable {
    case v2(telo: SkenTelo, sporocilo: String, podpis: Data)
    /// Telo je berljivo (v == 1, serial je UUID), pristnosti telefon ne more preveriti.
    case v1(telo: SkenTelo)
    case neznano

    static let najvecZnakov = 1024   // enako kot streznik (QR_NAJVEC_ZNAKOV)

    static func razcleni(_ qr: String) -> SkenKoda {
        let koda = qr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !koda.isEmpty, koda.count <= najvecZnakov else { return .neznano }
        let deli = koda.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if deli.count == 3 && deli[0] == "o2" {
            guard let podpis = Data(base64URL: deli[2]), podpis.count == 64,
                  let telo = Self.telo(deli[1], verzija: 2)
            else { return .neznano }
            return .v2(telo: telo, sporocilo: "o2.\(deli[1])", podpis: podpis)
        }
        if deli.count == 2, Self.jeBase64URL(deli[1]), let telo = Self.telo(deli[0], verzija: 1) {
            return .v1(telo: telo)
        }
        return .neznano
    }

    /// Telo iz base64url(JSON); `verzija` mora ustrezati polju `v`.
    private static func telo(_ b64: String, verzija: Int) -> SkenTelo? {
        guard let surovo = Data(base64URL: b64),
              let obj = (try? JSONSerialization.jsonObject(with: surovo)) as? [String: Any],
              (obj["v"] as? Int) == verzija,
              let t = obj["t"] as? String, let uuid = UUID(uuidString: t),
              let e = Self.celo(obj["e"])
        else { return nil }
        return SkenTelo(serial: uuid.uuidString.lowercased(), eventId: e, kid: obj["k"] as? String)
    }

    private static func jeBase64URL(_ s: String) -> Bool {
        !s.isEmpty && s.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }

    /// `e` je navadno stevilo; pg BIGINT bi lahko prisel kot niz (CLAUDE.md, pravilo 2), zato sprejmemo oboje.
    private static func celo(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let s = v as? String { return Int(s) }
        return nil
    }
}

enum SkenPodpis {
    /// Preveri podpis Ed25519 z javnim kljucem (32 B surovo, iz GET /business/scan-key).
    static func preveri(sporocilo: String, podpis: Data, javniKljuc: Data) -> Bool {
        guard podpis.count == 64, javniKljuc.count == 32,
              let kljuc = try? Curve25519.Signing.PublicKey(rawRepresentation: javniKljuc)
        else { return false }
        return kljuc.isValidSignature(podpis, for: Data(sporocilo.utf8))
    }
}

extension Data {
    /// base64url brez polnila (RFC 4648 §5). nil, ce niz ni veljaven base64url.
    init?(base64URL niz: String) {
        guard niz.range(of: "^[A-Za-z0-9_-]*$", options: .regularExpression) != nil else { return nil }
        var b = niz.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        switch b.count % 4 {
        case 1: return nil
        case 2: b += "=="
        case 3: b += "="
        default: break
        }
        self.init(base64Encoded: b)
    }
}
