import SwiftUI

/// Vstop v aplikacijo. Od 19. 10. 2026 (Martin: brskanje brez racuna) neprijavljen uporabnik NI vec zaprt na prijavi:
/// takoj vidi MainTabView (Home, Search, Map, dogodki, klubi), prijava se odpre v listu (PrijavaTok), ko jo dejanje zahteva.
///
/// - Zagon s prijavo: kot prej najprej SessionLoadingView (GET /me) in po potrebi CompleteAccountView, sele nato MainTabView
///   (vloga in obraz profila morata biti znana).
/// - Ko je MainTabView enkrat na zaslonu, ostane: prijava, nalaganje /me in dokoncanje racuna tecejo v listu, zato se uporabnik po
///   prijavi vrne na ISTI zaslon.
/// - Odjava (ali zavrnjena seja) zgradi MainTabView na novo (`odjav`): navigacija in podatki prejsnjega racuna ne ostanejo.
/// - `authStage` zdaj pomeni samo, kateri obrazec pokaze list (register | verifyEmail | login); "main" = prijava.
@MainActor
struct AuthGateView: View {
    @AppStorage("authStage") private var authStage: String = "register"
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var nadzor = PrijavaNadzor.deljen
    /// MainTabView je ze bil prikazan (gost ali po zagonu s prijavo): odslej ostane, prijava gre v list.
    @State private var glavniZiv = false
    /// Stevec odjav: nov `.id` MainTabView, da se po odjavi zgradi na novo.
    @State private var odjav = 0
    /// Tok prijave, ki ga odpre koren sam (potekla seja, nedokoncan racun, `me` ni nalozen, nedokoncana registracija ob zagonu).
    @State private var korenska: PrijavaZahteva?
    /// Odjava (ali zavrnjena seja) med odprtim listom s prijavo: zavihki se zgradijo na novo, ko se list zapre (glej `poZaprtjuTokov`).
    @State private var odjavaMedTokom = false
    /// Zadnji znan uporabnik (`me.id`): ce se po odjavi v listu prijavi DRUG racun, se zavihki zgradijo na novo.
    @State private var zadnjiUporabnik: Int?
    @State private var uporabnikPredOdjavo: Int?

    /// Zagon s prijavo, preden je MainTabView kdaj bil na zaslonu: najprej /me in dokoncanje racuna (kot doslej).
    private var zacetniTok: Bool {
        session.isLoggedIn && !glavniZiv && (session.me == nil || session.needsOnboarding)
    }

    /// Varovalo: prijavljen, a `me` ni nalozen ali racun ni dokoncan, in noben tok prijave ni odprt (npr. pogled, ki je drzal list,
    /// je izginil). Koren takrat sam odpre tok: SessionLoadingView (z »Try again«) ali dokoncanje racuna.
    private var tokManjka: Bool {
        glavniZiv && session.isLoggedIn && (session.me == nil || session.needsOnboarding) && !nadzor.jeKajOdprto
    }

    var body: some View {
        Group {
            if zacetniTok {
                if session.me == nil {
                    // Zeton je, uporabnika se nismo nalozili. GET /me pove, ali je racun dokoncan.
                    SessionLoadingView()
                } else {
                    // onboarded_at je prazen -> dokoncanje racuna (telefon, datum rojstva, drzava, zanri).
                    CompleteAccountView()
                }
            } else {
                MainTabView()
                    .id(odjav)
                    .onAppear { glavniZiv = true }
            }
        }
        .prijavaPoZahtevi($korenska)
        .onChange(of: session.me?.id) { _, novi in
            if let novi { zadnjiUporabnik = novi }
        }
        .onChange(of: session.isLoggedIn) { prej, zdaj in
            guard prej && !zdaj else { return }
            // Odjava iz profila / zavrnjena seja: zavihki od zacetka. Med odprtim listom s prijavo (npr. »Log out« na
            // SessionLoadingView v listu) zaslona pod listom ne podremo takoj, ampak ko se list zapre.
            if nadzor.jeKajOdprto {
                if !odjavaMedTokom { uporabnikPredOdjavo = zadnjiUporabnik }
                odjavaMedTokom = true
            } else {
                odjav += 1
                // Gost nima »zadnjega uporabnika«: sicer bi ga poznejsa odjava v listu (uporabnikPredOdjavo) primerjala s starim racunom.
                zadnjiUporabnik = nil
            }
        }
        .onChange(of: nadzor.jeKajOdprto) { _, odprto in
            guard !odprto else { return }
            poZaprtjuTokov()
            // Koren je lahko po treh neuspelih poskusih odnehal (list se ni pokazal, ker je bil odprt drug list), `tokManjka` pa se
            // od takrat ni spremenil: ob zaprtju lista s prijavo poskusi znova. Brez zanke: odpriKorensko ima najvec 3 poskuse,
            // sprozi pa se samo ob zaprtju (odprtje lista ga ne klice), v istem trenutku ga lahko klice se onChange(tokManjka);
            // drugi klic ga zaradi `korenska == nil` zavrne.
            if tokManjka { odpriKorensko { tokManjka } }
        }
        .onChange(of: session.sessionExpiredNotice) { _, obvestilo in
            // Streznik je sejo zavrnil: prijava (LoginView pokaze obvestilo).
            guard obvestilo != nil else { return }
            authStage = "login"
            odpriKorensko(zacetek: "login") { !session.isLoggedIn }
        }
        .onChange(of: tokManjka) { _, manjka in
            if manjka { odpriKorensko { tokManjka } }
        }
        .task {
            // Registracija, prekinjena pred vnosom kode (aplikacija zaprta): ob zagonu spet zaslon s kodo.
            // Gost, ki je list s kodo zaprl sam, ima authStage "login" (PrijavaPoZahteviModifier) in tega ne dobi.
            if !session.isLoggedIn && authStage == "verifyEmail" && korenska == nil {
                odpriKorensko(zamik: 0) { !session.isLoggedIn && authStage == "verifyEmail" }
            }
        }
    }

    /// Vsi listi s prijavo so zaprti: odlozena prenova zavihkov po odjavi med tokom. Isti racun, ki se je v listu prijavil znova,
    /// obdrzi zaslon; gost ali drug racun dobi zavihke na novo (brez podatkov prejsnjega).
    private func poZaprtjuTokov() {
        guard odjavaMedTokom else { return }
        odjavaMedTokom = false
        if !session.isLoggedIn || session.me?.id != uporabnikPredOdjavo { odjav += 1 }
        uporabnikPredOdjavo = nil
        if !session.isLoggedIn { zadnjiUporabnik = nil }
    }

    /// Koren odpre svoj tok prijave z zamikom (drug list se morda se zapira; SwiftUI dveh hkrati ne pokaze). Ce se list v 1,5 s
    /// ne pokaze (PrijavaNadzor ga ne pozna), se `korenska` ponastavi in poskusi znova (najvec 3-krat), da ne ostane visela.
    private func odpriKorensko(zacetek: String? = nil, zamik: UInt64 = 600_000_000, poskus: Int = 0,
                               pogoj: @escaping () -> Bool) {
        Task {
            if zamik > 0 { try? await Task.sleep(nanoseconds: zamik) }
            guard pogoj(), korenska == nil, !nadzor.jeKajOdprto else { return }
            let z = PrijavaZahteva(zacetek: zacetek)
            korenska = z
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard korenska?.id == z.id, !nadzor.odprti.contains(z.id) else { return }
            korenska = nil
            if poskus < 2 { odpriKorensko(zacetek: zacetek, poskus: poskus + 1, pogoj: pogoj) }
        }
    }
}

/// Kratek zaslon med nalaganjem GET /me. Ob napaki omrezja ponudi ponovni poskus
/// in odjavo; ob 401 SessionStore sam odjavi in gate pokaze prijavo.
@MainActor
struct SessionLoadingView: View {
    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "main"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)

                if let err = session.meLoadError {
                    Text(err)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    OutlyPrimaryButton(title: "Try again") {
                        Task { await session.refreshMe() }
                    }
                    .padding(.horizontal, 40)
                    Button("Log out") {
                        session.logout()
                        authStage = "login"
                    }
                    .foregroundColor(.white.opacity(0.6))
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await session.refreshMe() }
    }
}
