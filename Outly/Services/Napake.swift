//
//  Napake.swift
//  Outly
//
//  Porocanje zrusitev in napak (Sentry Cocoa, brezplacni paket; backend#87).
//
//  Pravila (glej tudi PrivacyInfo.xcprivacy in politiko zasebnosti):
//   - Samo Release na pravi napravi: v Debug gradnji in na simulatorju se SDK NE zazene.
//   - Brez osebnih podatkov: brez sendDefaultPii, brez posnetkov zaslona, brez hierarhije pogledov,
//     brez Session Replay, brez profiliranja, brez tracinga (tracesSampleRate = 0).
//   - beforeSend / beforeBreadcrumb odstranita uporabnika (SDK mu sicer sam doda `user.id` = oznaka namestitve),
//     zahtevek (glave, piskotke, query), stalno oznako naprave `contexts.app.device_app_hash` in VSE omrezne
//     sledi (http/xhr; pot v URL-ju lahko nosi identifikator, npr. zeton APNs v DELETE /me/devices/:zeton).
//     Sentry Cocoa 9.30.1: SDK doda `device_app_hash` (SHA-1 iz identifierForVendor, modela naprave in bundle ID)
//     v kontekst `app` ob vsakem dogodku, tudi ob zrusitvi (kontekst se prenese prek scope observerja).
//   - Kodo prevajamo v vseh konfiguracijah (Debug CI jo prevede tudi), ZAGON pa odloca `vklopljeno`.
//

import Foundation
import Sentry

enum Napake {
    /// DSN je javen po zasnovi (samo oddaja dogodkov); projekt `outly-ios` v organizaciji `outly-hd` (DE).
    private static let dsn = "https://bab5affc3888452bc872bb1c0ace8d0a@o4512176179773440.ingest.de.sentry.io/4512238489305168"

    /// Pravi zagon samo v Release na napravi.
    private static let vklopljeno: Bool = {
        #if DEBUG || targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }()

    /// Poklici enkrat, cim prej ob zagonu (OutlyApp.init).
    static func zazeni() {
        guard vklopljeno else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = "production"
            // releaseName ostane privzet: "<bundle id>@<CFBundleShortVersionString>+<CFBundleVersion>".

            // Zasebnost.
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // Brez performance/tracinga. Ugasnemo tudi samodejno sledenje, ki bi brez vzorcenja samo
            // obremenjevalo glavno nit (swizzling pogledov, datotek, omrezja).
            options.tracesSampleRate = 0
            options.enableAutoPerformanceTracing = false
            options.enableUserInteractionTracing = false
            options.enableNetworkTracking = false
            // Omrezne sledi imajo LOCEN vklop (privzeto true) in delujejo tudi ob izklopljenem sledenju omrezja.
            options.enableNetworkBreadcrumbs = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false

            // Nepotrebni viri dogodkov: backend ze javlja svoje 5xx (poraba mesecne kvote 5.000 napak),
            // "app hang" bi pri zatikanju drsenja hitro pojedel kvoto.
            options.enableCaptureFailedRequests = false
            options.enableAppHangTracking = false

            // Release health (seje) IZKLOPLJEN: seja nosi nakljucno oznako namestitve (`did`), ki bi s tem sla v
            // Sentry (pravnik 11. 10. 2026, srednje, nepreverjeno). Zrusitve in napake se posiljajo naprej.
            // POZOR: izklop sej NE odpravi lokalne datoteke z oznako namestitve (UUID `INSTALLATION` v predpomnilniku):
            // SDK jo zapise ob zagonu (SentryClient.m, cacheIDAsync) ne glede na seje. Na streznik ne gre: seje so
            // izklopljene, `user.id` pa v beforeSend odstranimo. Vklop sej sele po pravnem pregledu in dopolnitvi
            // politike zasebnosti.
            options.enableAutoSessionTracking = false
            options.maxBreadcrumbs = 50

            options.beforeSend = Napake.ocistiDogodek
            options.beforeBreadcrumb = Napake.ocistiSled
        }
    }

    /// Klice se na poljubni niti, zato `nonisolated` (projekt ima privzeto izolacijo MainActor).
    private nonisolated static func ocistiDogodek(_ dogodek: Sentry.Event) -> Sentry.Event? {
        dogodek.user = nil
        dogodek.request = nil
        dogodek.context = ocistiKontekst(dogodek.context)
        if let sledi = dogodek.breadcrumbs {
            dogodek.breadcrumbs = sledi.filter { !jeOmreznaSled(vrsta: $0.type, kategorija: $0.category) }
        }
        return dogodek
    }

    private nonisolated static func ocistiSled(_ sled: Sentry.Breadcrumb) -> Sentry.Breadcrumb? {
        jeOmreznaSled(vrsta: sled.type, kategorija: sled.category) ? nil : sled
    }

    /// Iz konteksta dogodka odstrani stalno oznako naprave: `app.device_app_hash` (SDK 9.30.1 ga doda ob vsakem
    /// dogodku, tudi zrusitvi). Ostalo (model, OS, razlicica aplikacije) ostane. Brez Sentry tipov, zato preizkusljivo.
    nonisolated static func ocistiKontekst(_ kontekst: [String: [String: Any]]?) -> [String: [String: Any]]? {
        guard var kontekst else { return nil }
        if var app = kontekst["app"] {
            app.removeValue(forKey: "device_app_hash")
            kontekst["app"] = app
        }
        return kontekst
    }

    /// Omrezna sled (http/xhr): zavrzemo jo v celoti. Pot v URL-ju lahko nosi identifikator (npr. zeton APNs pri
    /// DELETE /me/devices/:zeton), metoda in status pa za analizo zrusitve ne odtehtata tveganja.
    nonisolated static func jeOmreznaSled(vrsta: String?, kategorija: String) -> Bool {
        let tip = (vrsta ?? "").lowercased()
        let kat = kategorija.lowercased()
        return tip == "http" || kat == "http" || kat == "xhr"
    }
}
