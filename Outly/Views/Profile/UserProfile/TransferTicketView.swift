import SwiftUI

/// Cista logika starostne meje pri prenosu (locena od pogleda zaradi testov).
enum PrenosStarosti {
    /// Meja za kljukico: `izStrezniku` (min_age iz 400 `age_confirmation_required`) ima prednost; sicer `minAge`,
    /// pri vstopnici s paketom pijace vsaj 18 (enako kot `starostZaPaket` na strezniku). 0 = kljukice ni.
    static func meja(minAge: Int, imaPaket: Bool, izStrezniku: Int?) -> Int {
        if let n = izStrezniku { return n }
        return imaPaket ? max(minAge, 18) : minAge
    }

    /// `min_age` iz telesa `{ "error": "age_confirmation_required", "min_age": N }`; sicer nil.
    static func izNapake(_ error: Error) -> Int? {
        guard let api = error as? APIError, case let .requestFailed(_, raw) = api,
              let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
              (obj["error"] as? String) == "age_confirmation_required",
              let n = obj["min_age"] as? Int, n > 0 else { return nil }
        return n
    }
}

/// Posiljanje vstopnice prijatelju (sheet iz TicketDetailView).
/// Od 20. 9. (Martin): najprej izbira prijatelja iz seznama (GET /me/friends, prenos po
/// user_id); vpis e-naslova ostane kot druga pot (za nekoga, ki se ni prijatelj).
/// Od 5. 10. 2026: ce `Me.canTransferToGuest`, gre vstopnica po e-naslovu tudi prijatelju BREZ Outly racuna
/// (streznik mu poslje mail s QR); pri dogodku s starostno mejo posiljatelj potrdi starost (kljukica).
/// Po uspehu vstopnica izgine iz mojih (nov QR dobi prijatelj), zato zapremo tudi detajl.
@MainActor
struct TransferTicketView: View {
    let ticket: APITicket
    /// Poklicano po uspesnem prenosu (starsevski pogled zapre detajl vstopnice).
    var onTransferred: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var friends: [FriendUser] = []
    @State private var friendsLoading = true
    @State private var selected: FriendUser?
    /// true = vpis e-naslova (tudi ce ima uporabnik prijatelje).
    @State private var byEmail = false
    @State private var email = ""
    /// Stanje skupnega akcijskega gumba (OutlyAkcijskiGumb) - nadomesca prejsnji isSending.
    @State private var stanje: StanjeAkcije = .miruje
    @State private var errorMessage: String?
    /// Sistemska potrditev pred posiljanjem (Martin, 23. 9. 2026: "ne rabi vprasati kot
    /// da poslje" velja za nakup, NE za prenos - vstopnica gre iz mojega racuna).
    @State private var pokaziPotrditev = false
    /// Kljukica "prijatelj je star vsaj N" (vsak prenos, meja > 0). Ni vnaprej oznacena.
    @State private var starostPotrjena = false
    /// Kar je uporabnik potrdil: zajeto OB ODPIRANJU dialoga, ne bere se iz @State ob pritisku na "Send"
    /// (SwiftUI ob zaprtju dialoga stanje lahko ze spremeni - past iz #63).
    @State private var potrditev: PotrditevPrenosa?
    /// `min_age` iz odgovora 400 `age_confirmation_required` (nil = se ni bilo take napake).
    @State private var starostIzStrezniku: Int?
    /// Sporocilo streznika po uspehu prenosa po e-naslovu (npr. "Ticket sent to ana@mail.com.").
    @State private var uspehSporocilo: String?

    /// Zajeta vrednost za potrditveni dialog in klic `posli`.
    private struct PotrditevPrenosa {
        /// Prijatelj iz seznama (id) ali nil = po e-naslovu.
        let userId: Int?
        let email: String
        let ime: String
        /// Posiljanje po e-naslovu z `allow_guest` (prijatelj morda nima racuna).
        let gost: Bool
        let starostPotrjena: Bool
    }

    private var emailOk: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.contains("@") && e.contains(".") && e.count >= 6
    }

    /// Prikaz e-naslova: uporabnik ga je izbral ali pa nima prijateljev.
    private var kazeEmail: Bool { byEmail || (!friendsLoading && friends.isEmpty) }
    /// Prenos prijatelju brez racuna je na voljo: streznik je prizgal stikalo (`Me.canTransferToGuest`).
    /// Tudi VIP vstopnica s paketom pijace se sme poslati gostu (Martin, 5. 10. 2026), a s strozjo potrditvijo starosti.
    private var gostLahko: Bool { session.me?.canTransferToGuest ?? false }
    /// Starostna meja za kljukico: pri vstopnici s paketom pijace vsaj 18 (enako kot `starostZaPaket` na strezniku).
    /// Ce streznik zavrne z `age_confirmation_required`, ima prednost njegov `min_age` (kljukica se pokaze po napaki).
    private var starostnaMeja: Int {
        PrenosStarosti.meja(minAge: ticket.minAge, imaPaket: ticket.packageName != nil, izStrezniku: starostIzStrezniku)
    }
    /// Vpis e-naslova z moznostjo gosta (nova pot).
    private var gostNacin: Bool { kazeEmail && gostLahko }
    /// Kljukica starosti pri VSAKEM prenosu (prijatelj iz seznama, e-naslov, gost), ko je meja > 0
    /// (dogodek s starostno mejo ali vstopnica s paketom). Stikalo `canTransferToGuest` na to ne vpliva.
    private var trebaStarost: Bool { !friendsLoading && starostnaMeja > 0 }
    private var lahkoPoslje: Bool {
        (kazeEmail ? emailOk : selected != nil) && (!trebaStarost || starostPotrjena)
    }

    /// Ime/e-naslov prejemnika za potrditveno sporocilo in naslov uspeha ("Sent to Ana").
    private var prejemnikIme: String {
        if !kazeEmail, let f = selected { return f.username }
        return email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Send to a friend")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ticket.eventTitle)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(ticket.clubName) · \(ticket.publicRef)")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    obrazec
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .outlyOzadje()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                        if stanje == .uspeh { onTransferred() }
                    } label: {
                        Text("Cancel")
                    }
                    .foregroundColor(.white)
                    .disabled(stanje == .nalaga)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(stanje == .nalaga)
        .task { await loadFriends() }
        // Kljukica starosti velja za enega prejemnika: ob menjavi prejemnika/nacina se ponastavi (ne prenese se z A na B).
        .onChange(of: selected?.id) { _, _ in starostPotrjena = false }
        .onChange(of: byEmail) { _, _ in starostPotrjena = false }
        .onChange(of: email) { _, _ in starostPotrjena = false }
        // presenting: akcija in besedilo dobita svojo kopijo - ne zanasata se na @State ob zaprtju (past iz #63).
        .alert(potrditevNaslov, isPresented: $pokaziPotrditev, presenting: potrditev) { p in
            Button("Send") { Task { await posli(p) } }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            if p.gost {
                Text("Check the address – the ticket will be theirs and your QR code will stop working.")
            } else {
                Text("Your copy stops working.")
            }
        }
    }

    /// "Send this ticket to Ana?" / "Send ticket to ana@mail.com?" - kljuca "Send this ticket to %@?" in
    /// "Send ticket to %@?" v Localizable.xcstrings. Bere zajeto `potrditev`, ne zivih @State vrednosti.
    private var potrditevNaslov: String {
        guard let p = potrditev else { return "" }
        return p.gost
            ? String(localized: "Send ticket to \(p.ime)?")
            : String(localized: "Send this ticket to \(p.ime)?")
    }

    /// Zajame, kar bo poslano, in odpre potrditveni dialog.
    private func odpriPotrditev() {
        let naslov = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if kazeEmail {
            potrditev = PotrditevPrenosa(userId: nil, email: naslov, ime: naslov,
                                         gost: gostNacin, starostPotrjena: trebaStarost && starostPotrjena)
        } else if let f = selected {
            potrditev = PotrditevPrenosa(userId: f.id, email: "", ime: f.username, gost: false,
                                         starostPotrjena: trebaStarost && starostPotrjena)
        } else {
            return
        }
        pokaziPotrditev = true
    }

    private var obrazec: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Izbira prejemnika: zamrznjena in zatemnjena med posiljanjem/po uspehu.
            VStack(alignment: .leading, spacing: 16) {
                if friendsLoading {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                        .frame(height: 52)
                } else if kazeEmail {
                    Text(gostNacin ? "Your friend's email" : "Your friend's Outly email")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    OutlyTextField(placeholder: "friend@email.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !friends.isEmpty {
                        preklop("Choose from my friends instead") { byEmail = false }
                    }
                } else {
                    Text("Choose a friend")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    VStack(spacing: 8) {
                        ForEach(friends) { f in
                            Button { selected = (selected?.id == f.id) ? nil : f } label: {
                                HStack(spacing: 12) {
                                    OutlyAvatarView(avatarUrlString: f.avatarUrl, size: 40)
                                    Text(f.username)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: selected?.id == f.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundColor(selected?.id == f.id ? .outlyBlue : .white.opacity(0.35))
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(selected?.id == f.id ? 0.12 : 0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(selected?.id == f.id ? Color.outlyBlue : Color.clear, lineWidth: 1.5)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    preklop("Send by email instead") { byEmail = true; selected = nil }
                }

                if trebaStarost {
                    starostKljukica
                }

                Group {
                    if gostNacin {
                        Text("If your friend doesn't have an Outly account, we'll email them the ticket with a QR code.")
                        // Obvestilo posiljatelju (GDPR 13): prejemnik dobi njegovo uporabnisko ime.
                        Text("We'll email them the ticket with your username. Only enter the address of someone who is expecting it.")
                    } else if ticket.minAge > 0 {
                        Text("The ticket moves to your friend's account with a new QR code. Your copy stops working. Your friend needs an Outly account and must be \(ticket.minAge)+.")
                    } else {
                        Text("The ticket moves to your friend's account with a new QR code. Your copy stops working. Your friend needs an Outly account.")
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))

                // Vracilo ob odpovedi gre vedno prvotnemu kupcu (outly-backend #103).
                Text("If the event is cancelled, the refund goes to the original buyer, not to your friend.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .disabled(stanje != .miruje)
            .opacity(stanje == .miruje ? 1 : 0.6)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }

            OutlyAkcijskiGumb(
                naslov: "Send ticket",
                stanje: $stanje,
                naslovUspeha: String(localized: "Sent to \(prejemnikIme)")
            ) {
                odpriPotrditev()
            }
            // .disabled() se sklada z notranjim (stanje != .miruje) - torej AND, ne prepise.
            .disabled(!lahkoPoslje)
            .opacity(lahkoPoslje || stanje != .miruje ? 1 : 0.5)
            .padding(.top, 6)

            if stanje == .uspeh {
                VStack(spacing: 14) {
                    if let uspehSporocilo {
                        Text(verbatim: uspehSporocilo)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    } else {
                        Text("It will show up under Tickets in their app.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        dismiss()
                        onTransferred()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .transition(.outlyZabris)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: stanje == .uspeh)
    }

    /// Kljukica starosti (meja > 0, vsak nacin prenosa): brez nje gumb "Send ticket" ni aktiven. Ni vnaprej oznacena.
    private var starostKljukica: some View {
        Button { starostPotrjena.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: starostPotrjena ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(starostPotrjena ? .white : .white.opacity(0.5))
                    .accessibilityHidden(true)
                Text("I confirm the person I'm sending this ticket to is at least \(starostnaMeja) years old. They must show a valid photo ID at the door; if they are younger, the club will refuse entry.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }

    private func preklop(_ naslov: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(naslov))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.outlyBlue)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private func loadFriends() async {
        friendsLoading = true
        defer { friendsLoading = false }
        // Napaka pri nalaganju prijateljev ni ovira: pade se nazaj na vpis e-naslova.
        if let r = try? await APIClient.shared.fetchMyFriends(token: session.token) {
            friends = r.friends
        }
    }

    /// Poslje to, kar je uporabnik potrdil (`p` je zajet ob odprtju dialoga).
    private func posli(_ p: PotrditevPrenosa) async {
        guard stanje == .miruje else { return }
        errorMessage = nil
        uspehSporocilo = nil
        stanje = .nalaga
        do {
            if let userId = p.userId {
                _ = try await APIClient.shared.transferTicket(token: session.token, ticketId: ticket.id, userId: userId,
                                                              ageConfirmed: p.starostPotrjena)
            } else {
                let odgovor = try await APIClient.shared.transferTicket(
                    token: session.token, ticketId: ticket.id, email: p.email,
                    allowGuest: p.gost, ageConfirmed: p.starostPotrjena)
                // Nacin gost: streznik odgovori enotno ("Ticket sent to <email>."), ne glede na to, ali ima naslov racun.
                // (ob praznem message-u nevtralno besedilo, ne "pojavila se bo pod Tickets": gost nima aplikacije).
                if p.gost {
                    uspehSporocilo = odgovor.message.isEmpty ? String(localized: "Ticket sent to \(p.email).") : odgovor.message
                }
            }
            stanje = .uspeh
        } catch {
            if let n = PrenosStarosti.izNapake(error) { starostIzStrezniku = n }
            // Kljukica velja za eno poskusno posiljanje: po napaki jo uporabnik znova zavestno oznaci.
            starostPotrjena = false
            errorMessage = error.userMessage
            stanje = .napaka
        }
    }
}
