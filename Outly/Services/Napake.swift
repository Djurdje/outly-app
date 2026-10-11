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
//   - beforeSend / beforeBreadcrumb odstranita uporabnika, zahtevek (glave, piskotke, query) in
//     omrezne sledi z URL-ji s query nizom (lahko vsebujejo zetone).
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
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false

            // Nepotrebni viri dogodkov: backend ze javlja svoje 5xx (poraba mesecne kvote 5.000 napak),
            // "app hang" bi pri zatikanju drsenja hitro pojedel kvoto.
            options.enableCaptureFailedRequests = false
            options.enableAppHangTracking = false

            // Release health (seje) ostane: steje samo seje in zrusitve, brez osebnih podatkov.
            options.enableAutoSessionTracking = true
            options.maxBreadcrumbs = 50

            options.beforeSend = Napake.ocistiDogodek
            options.beforeBreadcrumb = Napake.ocistiSled
        }
    }

    /// Klice se na poljubni niti, zato `nonisolated` (projekt ima privzeto izolacijo MainActor).
    private nonisolated static func ocistiDogodek(_ dogodek: Sentry.Event) -> Sentry.Event? {
        dogodek.user = nil
        dogodek.request = nil
        if let sledi = dogodek.breadcrumbs {
            dogodek.breadcrumbs = sledi.filter { !jeObcutljivaSled($0) }
        }
        return dogodek
    }

    private nonisolated static func ocistiSled(_ sled: Sentry.Breadcrumb) -> Sentry.Breadcrumb? {
        jeObcutljivaSled(sled) ? nil : sled
    }

    /// Omrezna sled (http/xhr), katere URL ima query ali fragment: lahko nosi zetone, zato jo zavrzemo.
    private nonisolated static func jeObcutljivaSled(_ sled: Sentry.Breadcrumb) -> Bool {
        let vrsta = (sled.type ?? "").lowercased()
        let kategorija = sled.category.lowercased()
        guard vrsta == "http" || kategorija == "http" || kategorija == "xhr" else { return false }
        let podatki = sled.data ?? [:]
        if podatki["http.query"] != nil || podatki["http.fragment"] != nil { return true }
        for kljuc in ["url", "http.url"] {
            if let url = podatki[kljuc] as? String, url.contains("?") || url.contains("#") { return true }
        }
        return false
    }
}
