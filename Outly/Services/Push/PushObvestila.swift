import Foundation
import UIKit
import UserNotifications
import os

/// Potisna obvestila (APNs): dovoljenje, zeton naprave, registracija in odjava na strezniku (outly-backend#183, #184).
///
/// Pravila:
/// - Dovoljenje se NE vprasa ob zagonu, ampak ob prvem smiselnem trenutku (`predlagajDovoljenje()`): po nakupu vstopnice ali
///   mize, po prvem Follow kluba, po sprejemu vabila v ekipo kluba. Sistemski poziv iOS pokaze samo enkrat (`notDetermined`);
///   ob zavrnitvi ne vsiljujemo nicesar.
/// - Ce je dovoljenje ze odobreno, se ob zagonu / vrnitvi v ospredje / prijavi BREZ vprasanja poklice
///   `registerForRemoteNotifications()`; iOS vrne zeton v `OutlyAppDelegate`, ta ga preda tu.
/// - Zeton se na strezniku registrira samo, ce je uporabnik prijavljen in se je zeton spremenil ALI je zadnja uspesna registracija
///   starejsa od 24 h ALI je prijavljen drug uporabnik kot zadnjic (`PushOdlocitev.jeTreba`). Stanje (zeton, uporabnik, cas)
///   je v UserDefaults.
/// - Napake registracije in odjave se SAMO zapisejo v dnevnik (nikoli opozorilo uporabniku). Klici gredo prek `APIClient.send()`.
/// - Ob odjavi `SessionStore` pred brisanjem seje pocaka na `odjaviNapravo` (najvec ~3 s), da pushi prejsnjega uporabnika
///   ne gredo na napravo, dokler novi uporabnik ne registrira zetona.
/// - Samo produkcijski APNs: zeton iz Xcode Debug (sandbox) backend zavrne (`BadDeviceToken`) in ga oznaci kot neveljavnega.
@MainActor
final class PushObvestila {
    static let deljen = PushObvestila()
    private init() {}

    /// Seja (nastavi jo `SessionStore.init`). Sibka referenca: SessionStore zivi, dokler zivi aplikacija.
    weak var seja: SessionStore?

    /// Zadnji zeton, ki ga je APNs dal v tem procesu (heks, male crke). nil, dokler ga iOS ni vrnil.
    private(set) var zeton: String?

    private var posiljanjeTece = false
    private var vprasanjeTece = false

    private static let kljucStanja = "push.registracija.v1"
    private let dnevnik = Logger(subsystem: "si.outly.app", category: "push")

    // MARK: - Stanje registracije (UserDefaults)

    /// Je na tej napravi ze zabelezena uspesna registracija zetona (in jo je treba ob odjavi preklicati).
    var imaRegistracijo: Bool { preberiStanje() != nil }

    func preberiStanje() -> PushRegistracija? {
        guard let podatki = UserDefaults.standard.data(forKey: Self.kljucStanja) else { return nil }
        return try? JSONDecoder().decode(PushRegistracija.self, from: podatki)
    }

    private func shraniStanje(_ stanje: PushRegistracija) {
        guard let podatki = try? JSONEncoder().encode(stanje) else { return }
        UserDefaults.standard.set(podatki, forKey: Self.kljucStanja)
    }

    /// Ob odjavi / zavrnjeni seji: naslednji uporabnik (ali ista oseba po ponovni prijavi) se registrira znova.
    func pocistiStanje() {
        UserDefaults.standard.removeObject(forKey: Self.kljucStanja)
    }

    // MARK: - Dovoljenje in registracija pri APNs

    /// Ob zagonu, vrnitvi v ospredje in po prijavi: ce je dovoljenje ze odobreno, naj iOS (znova) vrne zeton. Brez vprasanja.
    func osvezi() {
        guard seja?.isLoggedIn == true else { return }
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if PushObvestila.jeOdobreno(status) { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Prvi smiseln trenutek (uspesen nakup, prvi Follow, sprejem vabila v ekipo): ce uporabnik se ni odlocil, pokazi sistemski
    /// poziv (z zamikom, da je uspeh na zaslonu se viden). Ze odobreno -> samo registracija; zavrnjeno -> nic.
    func predlagajDovoljenje() {
        guard !vprasanjeTece, seja?.isLoggedIn == true else { return }
        vprasanjeTece = true
        Task {
            defer { self.vprasanjeTece = false }
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            if PushObvestila.jeOdobreno(status) {
                UIApplication.shared.registerForRemoteNotifications()
                return
            }
            guard status == .notDetermined else { return }   // .denied: nic ne vsiljujemo
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard self.seja?.isLoggedIn == true else { return }
            let odobreno = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if odobreno { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    private static func jeOdobreno(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: - Povratni klici iz OutlyAppDelegate

    /// iOS je vrnil zeton naprave.
    func pridobljenZeton(_ podatki: Data) {
        zeton = PushOdlocitev.hex(podatki)
        uskladi()
    }

    /// iOS zetona ni dal (npr. simulator, ni omrezja). Samo dnevnik.
    func registracijaNeuspela(_ napaka: Error) {
        dnevnik.error("APNs: registracija naprave ni uspela: \(napaka.localizedDescription, privacy: .public)")
    }

    // MARK: - Registracija na strezniku

    /// Poslje zeton na strezniku, ce je uporabnik prijavljen (z znanim id) in je po `PushOdlocitev` to treba.
    /// Klice se ob novem zetonu in ob spremembi uporabnika (prijava, GET /me).
    func uskladi() {
        guard let seja, seja.isLoggedIn, let uporabnikId = seja.me?.id, let zeton, !posiljanjeTece else { return }
        guard PushOdlocitev.jeTreba(zeton: zeton, uporabnikId: uporabnikId, zadnja: preberiStanje(), zdaj: Date()) else { return }
        let jwt = seja.token
        posiljanjeTece = true
        Task {
            defer { self.posiljanjeTece = false }
            do {
                try await APIClient.shared.registerDevice(token: jwt, deviceToken: zeton)
                // Odjavljen med klicem: stanja ne zapisemo (ob naslednji prijavi se registrira znova).
                guard self.seja?.token == jwt else { return }
                self.shraniStanje(PushRegistracija(zeton: zeton, uporabnikId: uporabnikId, cas: Date()))
            } catch {
                self.dnevnik.error("POST /me/devices ni uspel: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Odjava

    /// DELETE /me/devices/:zeton z zetonom seje `token` (ki se VELJA: klic tece pred brisanjem seje). Rok ~3 s (cas zahtevka),
    /// napaka se samo zapise. Lokalno stanje registracije se pobrise vedno.
    func odjaviNapravo(token: String) async {
        guard let stanje = preberiStanje() else { return }
        do {
            try await APIClient.shared.deleteDevice(token: token, deviceToken: stanje.zeton, timeout: 3)
        } catch {
            dnevnik.error("DELETE /me/devices ni uspel: \(error.localizedDescription, privacy: .public)")
        }
        pocistiStanje()
    }
}
