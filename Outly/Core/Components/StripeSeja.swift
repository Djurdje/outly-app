import SwiftUI
import AuthenticationServices

/// Zahteva za odprtje Stripove placilne strani. `Identifiable`/`Equatable`, da je vsak nakup nova zahteva (`.onChange` sproži sejo).
struct StripeStran: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

/// Vodi `ASWebAuthenticationSession` s Stripovo gostovano stranjo (AuthenticationServices je sistemski framework, ne paket).
/// Kartica se vnasa na Stripovi strani, aplikacija je nikoli ne vidi (PCI DSS).
///
/// - Seja je v MOCNI referenci (`seja`): brez nje bi se takoj zaprla.
/// - Klic nazaj ima `[weak self]`: vodja drzi sejo, seja drzi klic, klic vodje ne drzi -> brez retain cycla.
/// - `prefersEphemeralWebBrowserSession = true`: brez sistemskega vprasanja »… wants to use … to sign in«. Posledica: seja ne deli
///   piskotkov in prijav s Safarijem (Stripe ne rabi prijave; Apple Pay in kartica delata na Stripovi strani).
/// - Shemo `outly` prestreze sistem sam; registracija URL sheme v Info.plist NI potrebna.
@MainActor
final class StripeSejaVodja: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var seja: ASWebAuthenticationSession?
    private var naKonec: ((StripePlacilo.SejaIzid) -> Void)?
    /// Oznaka trenutne seje: zakasnel klic nazaj preklicane (stare) seje se ne sme prikazati kot izid nove.
    private var oznaka = UUID()

    /// Zacne sejo. `naKonec` poklice natanko enkrat (uspeh, preklic, zaprtje ali napaka); ob novem `zacni` se stara seja
    /// preklice BREZ klica `naKonec`.
    func zacni(url: URL, naKonec: @escaping (StripePlacilo.SejaIzid) -> Void) {
        ustavi()
        self.naKonec = naKonec
        let moja = UUID()
        oznaka = moja
        let obdelava: @Sendable (URL?, Error?) -> Void = { [weak self] klic, napaka in
            Task { @MainActor in self?.konec(oznaka: moja, klic: klic, napaka: napaka) }
        }
        let nova = ASWebAuthenticationSession(url: url, callbackURLScheme: StripePlacilo.shemaVrnitve, completionHandler: obdelava)
        nova.prefersEphemeralWebBrowserSession = true
        nova.presentationContextProvider = self
        seja = nova
        if !nova.start() {
            seja = nil
            let klic = self.naKonec
            self.naKonec = nil
            klic?(.napaka)
        }
    }

    /// Preklice sejo, ce tece, brez klica `naKonec`.
    func ustavi() {
        let stara = seja
        oznaka = UUID()
        seja = nil
        naKonec = nil
        stara?.cancel()
    }

    private func konec(oznaka: UUID, klic: URL?, napaka: Error?) {
        guard oznaka == self.oznaka, seja != nil else { return }   // preklicana ali ze zakljucena seja
        let izid: StripePlacilo.SejaIzid
        if let napaka {
            if let e = napaka as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                izid = .prekinil
            } else {
                izid = .napaka
            }
        } else {
            izid = StripePlacilo.SejaIzid.izKlica(klic)
        }
        let naslednji = naKonec
        seja = nil
        naKonec = nil
        naslednji?(izid)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let okno = UIApplication.shared.kljucnoOkno { return okno }
        let scena = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let scena { return ASPresentationAnchor(windowScene: scena) }
        return ASPresentationAnchor()
    }
}

private struct StripeSejaModifier: ViewModifier {
    @Binding var stran: StripeStran?
    let naIzid: (StripePlacilo.SejaIzid) -> Void
    @State private var vodja = StripeSejaVodja()

    func body(content: Content) -> some View {
        content
            .onChange(of: stran) { _, nova in
                guard let nova else { return }
                vodja.zacni(url: nova.url) { izid in
                    stran = nil
                    naIzid(izid)
                }
            }
    }
}

extension View {
    /// Ko `stran` dobi vrednost, odpre Stripovo stran v `ASWebAuthenticationSession`; ob koncu seje `stran` postavi na nil in
    /// pokliče `naIzid`.
    func stripeSeja(stran: Binding<StripeStran?>, naIzid: @escaping (StripePlacilo.SejaIzid) -> Void) -> some View {
        modifier(StripeSejaModifier(stran: stran, naIzid: naIzid))
    }
}

/// Obvestilo pod nakupnim obrazcem, ko Stripe se ni potrdil placila (webhook zakasni nekaj sekund ali uporabnik se ni placal):
/// kratko sporocilo in gumb za ponovno branje. Gumb je nevtralen (modra samo na glavnem gumbu).
struct PlaciloSeVeriKartica: View {
    let preverjanje: Bool
    let onPreveri: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NapotekKartica(besedilo: String(localized: "Checking your payment … your tickets will show up in Profile → Tickets in a few seconds."))

            Button {
                onPreveri()
            } label: {
                Group {
                    if preverjanje {
                        ProgressView().tint(.white)
                    } else {
                        Text("Check again")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(preverjanje)
        }
    }
}
