import SwiftUI

/// Povabilo prijateljev na guest listo (list iz `GuestListDetailView`, 8. 10. 2026): skupna izbira prijateljev (`IzbiraPrijateljevView`),
/// najvec `remaining`, ze povabljeni izkljuceni, kljukica starosti pri dogodku z mejo. Samo prijatelji z Outlyja (GET /me/friends),
/// ne po e-naslovu. Povabilo je vse ali nic (ena transakcija): `POST /me/guest-lists/:id/invites`. Po uspehu vrne posodobljeno listo.
@MainActor
struct GuestListPovabiSheet: View {
    let lista: GuestList
    var onInvited: (GuestList) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var prijatelji: [FriendUser] = []
    @State private var nalaganje = true
    @State private var napakaNalaganja: String?
    @State private var izbrani: [Int] = []
    @State private var starostPotrjena = false
    /// `min_age` iz 400 `age_confirmation_required` (nil = se ni bilo take napake).
    @State private var starostIzStrezniku: Int?
    @State private var posilja = false
    @State private var errorMessage: String?

    private var meja: Int { max(0, lista.remaining) }
    private var starostnaMeja: Int {
        PrenosStarosti.meja(minAge: lista.event.minAge, imaPaket: false, izStrezniku: starostIzStrezniku)
    }
    private var razpolozljivi: [FriendUser] {
        IzbiraPrijateljev.razpolozljivi(prijatelji, izkljuceni: lista.povabljeniIdji)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Invite friends")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: lista.event.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Each friend gets their own ticket with their own QR code. They can arrive separately.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    vsebina

                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .outlyOzadje()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                        .foregroundColor(.white)
                        .disabled(posilja)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(posilja)
        .task { await naloziPrijatelje() }
    }

    @ViewBuilder
    private var vsebina: some View {
        if nalaganje && prijatelji.isEmpty {
            HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                .frame(height: 52)
        } else if let napakaNalaganja, prijatelji.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: napakaNalaganja)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                Button("Try again") { Task { await naloziPrijatelje() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        } else if razpolozljivi.isEmpty {
            Text(LocalizedStringKey(prijatelji.isEmpty
                 ? "You don't have any friends on Outly yet. Add friends in Profile, under My friends, then invite them here."
                 : "All your friends are already on this guest list."))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            IzbiraPrijateljevView(prijatelji: prijatelji, izbrani: $izbrani, meja: meja,
                                  izkljuceni: lista.povabljeniIdji,
                                  starostnaMeja: starostnaMeja, starostPotrjena: $starostPotrjena,
                                  omogocen: !posilja)

            let lahko = IzbiraPrijateljev.lahkoPosljes(izbranih: izbrani.count, starostnaMeja: starostnaMeja,
                                                       starostPotrjena: starostPotrjena)
            OutlyPrimaryButton(title: GuestListPrikaz.gumbPovabi(izbranih: izbrani.count), isLoading: posilja) {
                Task { await povabi() }
            }
            .disabled(!lahko || posilja)
            .opacity(lahko || posilja ? 1 : 0.5)
        }
    }

    // MARK: - Dejanja

    /// Napaka ni ovira za zaslon: prikaze se sporocilo s ponovnim poskusom.
    private func naloziPrijatelje() async {
        guard !posilja else { return }
        nalaganje = true
        defer { nalaganje = false }
        do {
            let r = try await APIClient.shared.fetchMyFriends(token: session.token)
            prijatelji = r.friends
            napakaNalaganja = nil
            izbrani = IzbiraPrijateljev.ocisti(izbrani, razpolozljivi: razpolozljivi, meja: meja)
        } catch {
            if prijatelji.isEmpty { napakaNalaganja = error.userMessage }
        }
    }

    private func povabi() async {
        guard !posilja, !izbrani.isEmpty else { return }
        errorMessage = nil
        posilja = true
        defer { posilja = false }
        let potrjena = starostnaMeja > 0 && starostPotrjena
        do {
            let r = try await APIClient.shared.inviteToGuestList(token: session.token, listId: lista.id, userIds: izbrani,
                                                                 ageConfirmed: potrjena)
            onInvited(r.guestList)
            dismiss()
        } catch {
            if let n = PrenosStarosti.izNapake(error) { starostIzStrezniku = n }
            // Kljukica velja za en poskus: po napaki jo uporabnik znova zavestno oznaci.
            starostPotrjena = false
            errorMessage = error.userMessage
        }
    }
}
