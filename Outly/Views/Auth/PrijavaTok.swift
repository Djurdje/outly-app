import SwiftUI
import Combine

// Brskanje brez racuna (Martin, 19. 10. 2026): neprijavljen uporabnik vidi Home, Search, Map, dogodke, klube, cenik in VIP pregled
// (vse, kar backend streze javno). Prijava ali registracija se odpre v listu sele, ko gost naredi nekaj, kar zahteva racun
// (nakup vstopnice ali VIP mize, »I'm in«, Follow, Report, zavihek Profile). Po uspesni prijavi (in dokoncanju racuna) se list
// zapre, uporabnik ostane na ISTEM zaslonu in, ce je smiselno, se dejanje nadaljuje (`PrijavaZahteva.nadaljuj`).
// Nakupa brez racuna (gost, samo splet) iOS nima: ob nakupu vedno prijava.

/// Ena zahteva za prijavo. `nadaljuj` se izvede PO zaprtju lista (prijavljen, `me` nalozen, racun dokoncan).
struct PrijavaZahteva: Identifiable {
    let id = UUID()
    /// Zacetni zaslon lista ("login" | "register"); nil = kjer je tok ostal (`authStage`), "main" pomeni prijavo.
    var zacetek: String? = nil
    var nadaljuj: (() -> Void)? = nil
}

/// Kateri tokovi prijave so odprti (lahko je list v listu, npr. VIP mize). AuthGateView po njem ve, ali sme sam odpreti tok
/// (potekla seja, nedokoncan racun), da ne odpre drugega lista cez obstojecega; PushPrehod pocaka na zaprtje.
/// Mnozica po `PrijavaZahteva.id`, ne stevec: ponovljen onAppear ali manjkajoc onDisappear ne more trajno blokirati
/// (zapiranje istega id je idempotentno, onDismiss modifikatorja ga zapre se enkrat).
@MainActor
final class PrijavaNadzor: ObservableObject {
    static let deljen = PrijavaNadzor()
    @Published private(set) var odprti: Set<UUID> = []

    var jeKajOdprto: Bool { !odprti.isEmpty }

    func odpri(_ id: UUID) {
        if !odprti.contains(id) { odprti.insert(id) }
    }

    func zapri(_ id: UUID) {
        if odprti.contains(id) { odprti.remove(id) }
    }
}

/// Tok prijave v listu: obstojeci zasloni (RegisterView, LoginView, VerifyEmailView) po `authStage`, po prijavi nalaganje /me
/// (SessionLoadingView) in po potrebi dokoncanje racuna (CompleteAccountView -> SelectGenresView). Ko je vse nared, poklice `koncano`.
@MainActor
struct PrijavaTok: View {
    /// `PrijavaZahteva.id` (za PrijavaNadzor).
    let id: UUID
    var zacetek: String? = nil
    let koncano: () -> Void

    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "register"
    @Environment(\.dismiss) private var dismiss
    /// `koncano` samo enkrat (onAppear in onChange se lahko zgodita oba).
    @State private var zakljuceno = false

    /// Prijavljen, `me` nalozen in racun dokoncan: list se lahko zapre.
    private var pripravljen: Bool { session.isLoggedIn && session.me != nil && !session.needsOnboarding }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            vsebina
            // Zapri samo pred prijavo: po prijavi mora tok do konca (nalaganje /me, dokoncanje racuna).
            if !session.isLoggedIn {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                .padding(.top, 14)
                .padding(.trailing, 16)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(session.isLoggedIn)
        .onAppear {
            PrijavaNadzor.deljen.odpri(id)
            if let zacetek {
                authStage = zacetek
            } else if !["register", "verifyEmail", "login"].contains(authStage) {
                // "main" (po odjavi) ali neznano: prijava.
                authStage = "login"
            }
            if pripravljen { zakljuci() }
        }
        .onDisappear { PrijavaNadzor.deljen.zapri(id) }
        .onChange(of: pripravljen) { _, da in
            if da { zakljuci() }
        }
    }

    @ViewBuilder
    private var vsebina: some View {
        if session.isLoggedIn {
            if session.me == nil {
                // GET /me pove, ali je racun dokoncan (ob napaki »Try again« / »Log out«).
                SessionLoadingView()
            } else if session.needsOnboarding {
                CompleteAccountView()
            } else {
                Color.black.ignoresSafeArea()
            }
        } else {
            switch authStage {
            case "register": RegisterView()
            case "verifyEmail": VerifyEmailView()
            default: LoginView()
            }
        }
    }

    private func zakljuci() {
        guard !zakljuceno else { return }
        zakljuceno = true
        koncano()
    }
}

private struct PrijavaPoZahteviModifier: ViewModifier {
    @Binding var zahteva: PrijavaZahteva?
    @EnvironmentObject private var session: SessionStore
    @AppStorage("authStage") private var authStage: String = "register"
    /// Nadaljevanje uspesne zahteve; izvede se v onDismiss (ko je list res zaprt, da lahko nadaljevanje odpre drug list).
    @State private var poZaprtju: (() -> Void)?
    /// Id zadnje prikazane zahteve (onDismiss ga pri PrijavaNadzor zapre, tudi ce onDisappear ni prisel).
    @State private var prikazanaId: UUID?

    func body(content: Content) -> some View {
        content
            .sheet(item: $zahteva, onDismiss: {
                if let id = prikazanaId { PrijavaNadzor.deljen.zapri(id) }
                prikazanaId = nil
                // Gost je list zaprl na zaslonu s kodo (X ali poteg): ob naslednjem zagonu ali menjavi jezika se ne sme vec
                // sam odpreti (AuthGateView). Koda iz maila ostane veljavna; prijava z geslom ga vrne na zaslon s kodo.
                if !session.isLoggedIn && authStage == "verifyEmail" { authStage = "login" }
                let n = poZaprtju
                poZaprtju = nil
                n?()
            }) { z in
                PrijavaTok(id: z.id, zacetek: z.zacetek) {
                    poZaprtju = z.nadaljuj
                    zahteva = nil
                }
                .environmentObject(session)
                .onAppear { prikazanaId = z.id }
            }
    }
}

extension View {
    /// List s prijavo, ko je `zahteva` nastavljena. Pripni ga na pogled, ki dejanje sprozi (tudi znotraj drugega lista).
    func prijavaPoZahtevi(_ zahteva: Binding<PrijavaZahteva?>) -> some View {
        modifier(PrijavaPoZahteviModifier(zahteva: zahteva))
    }
}

/// Zavihek Profile za neprijavljenega: povabilo k prijavi namesto profila, plus pomoc, O aplikaciji in jezik.
@MainActor
struct GostProfilView: View {
    @EnvironmentObject private var jezik: Jezik
    /// List s prijavo pripne ProfileView (nivo, ki se ob prijavi ne zamenja), tu se samo nastavi.
    @Binding var prijava: PrijavaZahteva?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.top, 32)
                    Text("Sign in to Outly")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("Buy tickets, reserve VIP tables, follow clubs and see your friends' plans. You can browse events without an account.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    OutlyPrimaryButton(title: "Sign in") {
                        prijava = PrijavaZahteva(zacetek: "login")
                    }
                    Button {
                        prijava = PrijavaZahteva(zacetek: "register")
                    } label: {
                        Text("Create an account")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }

                Divider().background(Color.gray)

                VStack(spacing: 12) {
                    NavigationLink(destination: HelpCenterView()) {
                        OutlyMenuRowButton(icon: "questionmark.circle", title: "Support")
                    }
                    NavigationLink(destination: AboutView()) {
                        OutlyMenuRowButton(icon: "info.circle", title: "About")
                    }
                }

                // Kot JezikGumb, a po ponovni gradnji (nov .id korena) nazaj na zavihek Profile (3).
                Button {
                    jezik.nastavi(jezik.jeSlovenscina ? "en" : "sl", zavihek: 3)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text(verbatim: jezik.jeSlovenscina ? "English" : "Slovenščina")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                // Spodnji odmik zaradi plavajoce spodnje vrstice (trdo pravilo 6).
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("")
        .outlyOzadje()
    }
}
