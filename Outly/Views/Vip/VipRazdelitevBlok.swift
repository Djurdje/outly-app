import SwiftUI
import UIKit

/// Uspesni zaslon po nakupu VIP mize (tudi po vrnitvi s Stripa): namesto besedila »Send the VIP tickets to your friends from Tickets«
/// izbira prijateljev (najvec N-1, kupcu ostane ena vstopnica), »Send to N friends« in »Skip« (8. 10. 2026).
/// Posiljanje: za vsakega izbranega obstojeci `POST /tickets/:id/transfer` na RAZLICNO vstopnico, zaporedno, od druge naprej
/// (`VipRazdelitev`). Delni neuspeh je prikazan (komu je slo, komu ne, z razlogom); neposlane vstopnice ostanejo v Tickets.
/// Brez prijateljev: kratko besedilo, povezava do dodajanja prijateljev in »Done«.
/// Brez lastnega NavigationStack (pogled je v listu VipTablesView, ki ga ima; povezava »Add friends« se potisne vanj).
@MainActor
struct VipRazdelitevBlok: View {
    /// Vstopnice nakupa (`PurchaseResponse.tickets`): prva ostane kupcu.
    let vstopnice: [APITicket]
    /// `min_age` dogodka.
    let minAge: Int
    /// Miza s paketom pijace: meja starosti vsaj 18 (enako kot pri navadnem prenosu).
    let imaPaket: Bool
    /// true med posiljanjem: starsevski pogled ne sme zapreti lista.
    @Binding var zaposlen: Bool
    /// »Done« / »Skip«: zapre list (vse neposlane vstopnice ostanejo v Tickets).
    var onDone: () -> Void

    @EnvironmentObject private var session: SessionStore

    @State private var prijatelji: [FriendUser] = []
    @State private var nalaganje = true
    @State private var napakaNalaganja: String?
    @State private var izbrani: [Int] = []
    @State private var starostPotrjena = false
    /// `min_age` iz 400 `age_confirmation_required` (nil = se ni bilo take napake).
    @State private var starostIzStrezniku: Int?
    @State private var posilja = false
    /// Posiljanje je bilo izvedeno vsaj enkrat: zaslon kaze izid.
    @State private var imaIzid = false
    @State private var poslani: [FriendUser] = []
    @State private var neuspeli: [VipRazdelitev.Neuspeh] = []

    private var meja: Int { VipRazdelitev.meja(vstopnice) }
    private var starostnaMeja: Int {
        PrenosStarosti.meja(minAge: minAge, imaPaket: imaPaket, izStrezniku: starostIzStrezniku)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if meja <= 0 {
                gumbDone(glavni: true)
            } else if imaIzid {
                izid
            } else if nalaganje && prijatelji.isEmpty {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                    .frame(height: 52)
            } else if let napakaNalaganja, prijatelji.isEmpty {
                brezPrijateljev(sporocilo: napakaNalaganja, ponovi: true)
            } else if prijatelji.isEmpty {
                brezPrijateljev(sporocilo: String(localized: "You don't have any friends on Outly yet. Your tickets are waiting under Tickets: add friends, then send them from there."),
                                ponovi: false)
            } else {
                izbira
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { Task { await naloziPrijatelje() } }
    }

    // MARK: - Izbira

    private var izbira: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Send tickets to your friends")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text("Choose up to \(meja) friends. You keep one ticket; any you don't send stay under Tickets.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            IzbiraPrijateljevView(prijatelji: prijatelji, izbrani: $izbrani, meja: meja,
                                  starostnaMeja: starostnaMeja, starostPotrjena: $starostPotrjena,
                                  omogocen: !posilja)

            let lahko = IzbiraPrijateljev.lahkoPosljes(izbranih: izbrani.count, starostnaMeja: starostnaMeja,
                                                       starostPotrjena: starostPotrjena)
            glavniGumb(naslov: naslovPosiljanja, vrteti: posilja, aktiven: lahko && !posilja) {
                Task { await posljiIzbrane() }
            }
            gumbSekundarni(naslov: "Skip", aktiven: !posilja, action: onDone)
        }
    }

    private var naslovPosiljanja: String {
        izbrani.isEmpty ? String(localized: "Send to friends") : String(localized: "Send to \(izbrani.count) friends")
    }

    // MARK: - Brez prijateljev

    private func brezPrijateljev(sporocilo: String, ponovi: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: sporocilo)
                .font(.system(size: 14))
                .foregroundColor(ponovi ? .red : .white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if ponovi {
                Button("Try again") { Task { await naloziPrijatelje() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                NavigationLink {
                    MyFriendsView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                        Text("Add friends")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            gumbDone(glavni: true)
        }
    }

    // MARK: - Izid

    private var izid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey(neuspeli.isEmpty ? "Tickets sent" : "Some tickets weren't sent"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 8) {
                ForEach(poslani) { f in vrsticaIzida(f, sporocilo: nil) }
                ForEach(neuspeli, id: \.par.prijatelj.id) { n in vrsticaIzida(n.par.prijatelj, sporocilo: n.sporocilo) }
            }

            if !neuspeli.isEmpty {
                Text("Tickets that weren't sent are still yours, under Tickets.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                // Streznik je zahteval potrditev starosti: kljukica in ponovitev za preostale.
                if starostIzStrezniku != nil {
                    StarostKljukica(starostnaMeja: starostnaMeja, potrjena: $starostPotrjena)
                        .disabled(posilja)
                }

                let lahko = starostIzStrezniku == nil || starostPotrjena
                glavniGumb(naslov: "Try again", vrteti: posilja, aktiven: lahko && !posilja) {
                    Task { await posljiPare(neuspeli.map(\.par)) }
                }
                gumbDone(glavni: false)
            } else {
                gumbDone(glavni: true)
            }
        }
    }

    private func vrsticaIzida(_ f: FriendUser, sporocilo: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            OutlyAvatarView(avatarUrlString: f.avatarUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: f.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let sporocilo {
                    Text(verbatim: sporocilo)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Sent")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: sporocilo == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(sporocilo == nil ? .white : .red)
                .padding(.top, 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Gumbi

    private func glavniGumb(naslov: String, vrteti: Bool, aktiven: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if vrteti { ProgressView().tint(.white) }
                Text(LocalizedStringKey(naslov))
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.outlyBlue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!aktiven)
        .opacity(aktiven || vrteti ? 1 : 0.45)
    }

    private func gumbSekundarni(naslov: String, aktiven: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(naslov))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!aktiven)
        .opacity(aktiven ? 1 : 0.45)
    }

    private func gumbDone(glavni: Bool) -> some View {
        Group {
            if glavni {
                glavniGumb(naslov: "Done", vrteti: false, aktiven: !posilja, action: onDone)
            } else {
                gumbSekundarni(naslov: "Done", aktiven: !posilja, action: onDone)
            }
        }
    }

    // MARK: - Dejanja

    /// Prijatelji (GET /me/friends). Napaka ni ovira: vstopnice so v Tickets. Ob vrnitvi z »Add friends« se seznam osvezi,
    /// izbira pa obdrzi se obstojece prijatelje.
    private func naloziPrijatelje() async {
        guard !posilja, !imaIzid, meja > 0 else { return }
        nalaganje = true
        defer { nalaganje = false }
        do {
            let r = try await APIClient.shared.fetchMyFriends(token: session.token)
            prijatelji = r.friends
            napakaNalaganja = nil
            izbrani = IzbiraPrijateljev.ocisti(izbrani, razpolozljivi: r.friends, meja: meja)
        } catch {
            if prijatelji.isEmpty { napakaNalaganja = error.userMessage }
        }
    }

    private func posljiIzbrane() async {
        let izbraniPrijatelji = VipRazdelitev.prijateljiIzIdjev(izbrani, prijatelji)
        await posljiPare(VipRazdelitev.pari(prijatelji: izbraniPrijatelji, vstopnice: vstopnice))
    }

    /// Zaporedno posljje; kar uspe, se odstrani tudi iz shranjenega seznama vstopnic (kot po navadnem prenosu).
    private func posljiPare(_ pari: [VipRazdelitev.Par]) async {
        guard !posilja, !pari.isEmpty else { return }
        posilja = true
        zaposlen = true
        defer {
            posilja = false
            zaposlen = false
        }
        let potrjena = starostnaMeja > 0 && starostPotrjena
        let token = session.token
        let izidPosiljanja = await VipRazdelitev.razdeli(pari) { par in
            _ = try await APIClient.shared.transferTicket(token: token, ticketId: par.vstopnicaId,
                                                          userId: par.prijatelj.id, ageConfirmed: potrjena)
            VstopniceShramba().odstrani(vstopnicaId: par.vstopnicaId)
        }
        poslani += izidPosiljanja.poslani.map(\.prijatelj)
        neuspeli = izidPosiljanja.neuspeli
        if let n = izidPosiljanja.zahtevaStarost { starostIzStrezniku = n }
        // Kljukica velja za en poskus: po napaki jo uporabnik znova zavestno oznaci.
        starostPotrjena = false
        imaIzid = true
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(izidPosiljanja.jePopoln ? .success : .warning)
    }
}
