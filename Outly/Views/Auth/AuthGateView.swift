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
    /// Tok prijave, ki ga odpre koren sam (potekla seja, nedokoncan racun, nedokoncana registracija ob zagonu).
    @State private var korenska: PrijavaZahteva?

    /// Zagon s prijavo, preden je MainTabView kdaj bil na zaslonu: najprej /me in dokoncanje racuna (kot doslej).
    private var zacetniTok: Bool {
        session.isLoggedIn && !glavniZiv && (session.me == nil || session.needsOnboarding)
    }

    /// Varovalo: prijavljen z nedokoncanim racunom, a noben tok prijave ni odprt (npr. list z VIP mizami je bil zaprt).
    private var nedokoncanBrezToka: Bool {
        glavniZiv && session.isLoggedIn && session.needsOnboarding && nadzor.odprtih == 0
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
        .onChange(of: session.isLoggedIn) { prej, zdaj in
            // Odjava iz profila / zavrnjena seja: zavihki od zacetka. Odjava ZNOTRAJ toka prijave (npr. »Log out« na
            // SessionLoadingView v listu) zaslona pod listom ne podre.
            if prej && !zdaj && nadzor.odprtih == 0 { odjav += 1 }
        }
        .onChange(of: session.sessionExpiredNotice) { _, obvestilo in
            // Streznik je sejo zavrnil: prijava (LoginView pokaze obvestilo), ce tok se ni odprt.
            guard obvestilo != nil, korenska == nil, nadzor.odprtih == 0 else { return }
            authStage = "login"
            korenska = PrijavaZahteva(zacetek: "login")
        }
        .onChange(of: nedokoncanBrezToka) { _, da in
            if da, korenska == nil { korenska = PrijavaZahteva() }
        }
        .task {
            // Registracija, prekinjena pred vnosom kode (aplikacija zaprta): ob zagonu spet zaslon s kodo.
            if !session.isLoggedIn && authStage == "verifyEmail" && korenska == nil {
                korenska = PrijavaZahteva()
            }
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
