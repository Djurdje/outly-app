import Foundation

// Zetoni naprav za potisna obvestila (APNs; backend migracija 040, outly-backend#183).
//   POST   /me/devices { token, platform: "ios" }  -> 200 { ok: true }   (idempotentno; isti zeton na drugem racunu se prepise)
//   DELETE /me/devices/:token                      -> 204                (samo lastnikov zeton; tuj ali neobstojec = 204 brez ucinka)
// 400 { error: "invalid_token" | "invalid_platform" }; omejevalnik 60/h/IP (429) -> registriraj ob spremembi zetona ali najvec enkrat na dan.
// Napake teh klicev se uporabniku NE pokazejo (PushObvestila jih samo zapise v dnevnik).

extension APIClient {

    /// Registrira zeton naprave (APNs, hex z malimi crkami) za prijavljenega uporabnika.
    func registerDevice(token: String, deviceToken: String) async throws {
        _ = try await send(path: "me/devices", method: "POST", token: token,
                           json: ["token": deviceToken, "platform": "ios"])
    }

    /// Odjavi zeton naprave. Brez ponovitve ob 401: klic tece ob odjavi, osvezitev seje bi se tepla z brisanjem seje.
    func deleteDevice(token: String, deviceToken: String, timeout: TimeInterval? = nil) async throws {
        _ = try await send(path: "me/devices/\(deviceToken)", method: "DELETE", token: token,
                           retryOn401: false, timeout: timeout)
    }
}
