import SwiftUI

/// Kartica guest liste na vrhu Profile -> Tickets (8. 10. 2026): plakat, naslov dogodka, klub, datum, »Spots left: 3 of 5«.
/// Dotik odpre `GuestListDetailView`.
struct GuestListKartica: View {
    let lista: GuestList

    var body: some View {
        HStack(spacing: 12) {
            plakat
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: lista.event.title)
                    .font(.headline).foregroundColor(.white).lineLimit(1)
                Text(verbatim: podnaslov)
                    .font(.subheadline).foregroundColor(.gray).lineLimit(1)
                HStack(spacing: 8) {
                    GuestListZnacka(kompakten: true)
                    Text(verbatim: GuestListPrikaz.mestaOpis(lista))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.gray)
        }
        .padding(14)
        .background(Color.gray.opacity(0.14))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var plakat: some View {
        if !lista.event.posterUrl.isEmpty, let url = URL(string: lista.event.posterUrl) {
            PlakatDogodkaSlika(url: url, mirenPlaceholder: true)
                .frame(width: 70, height: 70)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.10))
                .frame(width: 70, height: 70)
                .overlay(Image(systemName: "list.clipboard").foregroundColor(.white.opacity(0.8)))
        }
    }

    private var podnaslov: String {
        let klub = lista.event.clubName
        guard let d = lista.event.startDate else { return klub }
        return "\(klub) · \(DateParsing.shortDate.string(from: d)) \(DateParsing.shortTime.string(from: d))"
    }
}

/// Detajl guest liste (potisnjen pogled, brez lastnega NavigationStack): moja QR koda (gostiteljeva vstopnica -> obstojeci
/// detajl vstopnice), povabljeni prijatelji (»Checked in« za tiste na vratih), »Invite friends« (skupna izbira prijateljev,
/// najvec `remaining`, ze povabljeni izkljuceni) in odstranitev prijatelja s potrditvijo.
/// Podatki: GET /me/guest-lists (kartica), POST /me/guest-lists/:id/invites, DELETE /me/guest-lists/:id/invites/:userId;
/// odgovora vrneta posodobljeno listo.
@MainActor
struct GuestListDetailView: View {
    @State private var lista: GuestList
    /// Moje vstopnice (iz TicketsView): iz njih se vzame gostiteljeva vstopnica za QR.
    let vstopnice: [APITicket]

    @EnvironmentObject private var session: SessionStore

    @State private var pokaziPovabi = false
    @State private var pokaziOdstranitev = false
    /// Zajeto OB ODPIRANJU dialoga (SwiftUI ob zaprtju lahko stanje ze spremeni; past iz #63).
    @State private var zaOdstranitev: GuestListInvited?
    /// Id uporabnika, ki ga ravno odstranjujemo (gumb kaze vrtavko).
    @State private var odstranjujem: Int?
    @State private var errorMessage: String?

    init(lista: GuestList, vstopnice: [APITicket]) {
        _lista = State(initialValue: lista)
        self.vstopnice = vstopnice
    }

    private var mojaVstopnica: APITicket? {
        GuestListPrikaz.gostiteljevaVstopnica(lista, med: vstopnice)
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    glava
                        .padding(.top, 6)

                    if !lista.note.isEmpty {
                        Text(verbatim: lista.note)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    mojaKoda

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Invited friends")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text(verbatim: GuestListPrikaz.mestaOpis(lista))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        if lista.invited.isEmpty {
                            Text("Nobody invited yet.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.vertical, 6)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(lista.invited) { i in vrsticaPovabljenega(i) }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    povabiGumb

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pokaziPovabi) {
            GuestListPovabiSheet(lista: lista, onInvited: { nova in lista = nova })
                .environmentObject(session)
        }
        // presenting: akcija in besedilo dobita svojo kopijo - ne zanasata se na @State ob zaprtju (past iz #63).
        .alert(naslovOdstranitve, isPresented: $pokaziOdstranitev, presenting: zaOdstranitev) { i in
            Button("Remove", role: .destructive) { Task { await odstrani(i) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Their ticket will stop working and the spot becomes free.")
        }
    }

    private var naslovOdstranitve: String {
        guard let i = zaOdstranitev else { return "" }
        return String(localized: "Remove \(i.username) from your guest list?")
    }

    // MARK: - Deli

    private var glava: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guest list")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            if !lista.event.posterUrl.isEmpty, let url = URL(string: lista.event.posterUrl) {
                PlakatDogodkaSlika(url: url, mirenPlaceholder: true)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            Text(verbatim: lista.event.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
            Text(verbatim: podnaslov)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.65))
            if lista.event.minAge > 0 {
                Text("\(lista.event.minAge)+ · ID at the door")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
    }

    private var podnaslov: String {
        let klub = lista.event.clubName
        guard let d = lista.event.startDate else { return klub }
        return "\(klub) · \(DateParsing.shortDate.string(from: d)) \(DateParsing.shortTime.string(from: d))"
    }

    /// Moja QR koda = gostiteljeva vstopnica: odpre obstojeci detajl vstopnice (kartica z QR).
    @ViewBuilder
    private var mojaKoda: some View {
        if let t = mojaVstopnica {
            NavigationLink {
                TicketDetailView(ticket: t)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your QR code")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Show it at the entrance")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.gray)
                }
                .padding(14)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Text("Your ticket is under Tickets.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private func vrsticaPovabljenega(_ i: GuestListInvited) -> some View {
        HStack(spacing: 12) {
            OutlyAvatarView(avatarUrlString: i.avatarUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: i.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(verbatim: GuestListPrikaz.statusPovabljenega(i))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(i.jeVstopil ? .white : .white.opacity(0.55))
            }
            Spacer()
            if odstranjujem == i.userId {
                ProgressView().tint(.white)
            } else if !i.jeVstopil {
                Button {
                    errorMessage = nil
                    zaOdstranitev = i
                    pokaziOdstranitev = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(odstranjujem != nil)
                .accessibilityLabel(Text("Remove"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var povabiGumb: some View {
        if let zakaj = GuestListPrikaz.zakajNeVabi(lista) {
            Text(verbatim: zakaj)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            OutlyPrimaryButton(title: "Invite friends") {
                errorMessage = nil
                pokaziPovabi = true
            }
        }
    }

    // MARK: - Dejanja

    private func odstrani(_ i: GuestListInvited) async {
        guard odstranjujem == nil else { return }
        odstranjujem = i.userId
        errorMessage = nil
        defer { odstranjujem = nil }
        do {
            lista = try await APIClient.shared.removeGuestListInvite(token: session.token, listId: lista.id, userId: i.userId)
        } catch {
            errorMessage = error.userMessage
        }
    }
}
