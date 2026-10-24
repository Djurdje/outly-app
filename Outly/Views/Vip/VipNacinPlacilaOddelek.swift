import SwiftUI

/// Razdelek »VIP table sales« v obrazcu dogodka (za vse klube; owner, manager): VIP mize na dogodku vklop/izklop in NACIN PLACILA —
/// »Pay in the app« (kupec mizo placa v aplikaciji in dobi VIP vstopnice) ali »Cash at the VIP door« (kupec mizo v aplikaciji samo
/// rezervira, placa z gotovino na VIP vratih; backend 23. 10. 2026). PUT /business/events/:id/vip poslje samo `enabled` in `payment`;
/// `tables` (cene in izklopi po mizah) NI v telesu, zato jih ne povozi. Spremembe veljajo takoj (kot razdelek razporeda), brez gumba Save.
/// Razdelek je samo za obstojec dogodek (potrebuje id). Star backend (404 na GET /business/events/:id/vip) razdelek skrije.
/// Spremenjen nacin ne vpliva na ze obstojece nakupe ali rezervacije. Brez lastnega NavigationStack.
@MainActor
struct VipNacinPlacilaOddelek: View {
    let clubId: Int
    /// nil = dogodek se ni shranjen.
    let eventId: Int?
    /// Organizatorjev obrazec ze ima razdelek »VIP tables« z namigom za nov dogodek: tu ga ne podvajamo.
    var brezNamigaZaNovDogodek: Bool = false

    @EnvironmentObject private var session: SessionStore

    private enum Nalaganje {
        case nalaga
        case skrito
        case napaka(String)
        case pripravljeno(BusinessEventVip)
    }

    @State private var nalaganje: Nalaganje = .nalaga
    @State private var dela = false
    @State private var sporocilo: String?

    var body: some View {
        if let eventId {
            if case .skrito = nalaganje {
                EmptyView()
            } else {
                Section {
                    vsebina(eventId: eventId)
                } header: {
                    Text("VIP table sales")
                }
            }
        } else if !brezNamigaZaNovDogodek {
            Section {
                Text("Save the event first, then turn on VIP tables.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("VIP table sales")
            }
        }
    }

    // MARK: - Vsebina

    @ViewBuilder
    private func vsebina(eventId: Int) -> some View {
        switch nalaganje {
        case .nalaga:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading...").foregroundStyle(.secondary)
            }
            .task { await nalozi(eventId: eventId) }
        case .skrito:
            EmptyView()
        case .napaka(let besedilo):
            Text(besedilo).foregroundStyle(.red)
            Button("Try again") {
                nalaganje = .nalaga
            }
        case .pripravljeno(let vip):
            nastavitve(vip: vip, eventId: eventId)
        }
    }

    @ViewBuilder
    private func nastavitve(vip: BusinessEventVip, eventId: Int) -> some View {
        Toggle("Sell VIP tables", isOn: Binding(
            get: { vip.enabled },
            set: { novo in Task { await shrani(eventId: eventId, enabled: novo, payment: nil, prejsnji: vip) } }
        ))
        .disabled(dela)

        if vip.enabled {
            vrstica(izbrana: vip.payment == VipPlacilo.aplikacija) {
                Task { await shrani(eventId: eventId, enabled: true, payment: VipPlacilo.aplikacija, prejsnji: vip) }
            } naslov: {
                Text("Pay in the app")
            }
            vrstica(izbrana: vip.payment == VipPlacilo.vrata) {
                Task { await shrani(eventId: eventId, enabled: true, payment: VipPlacilo.vrata, prejsnji: vip) }
            } naslov: {
                Text("Cash at the VIP door")
            }

            Text(LocalizedStringKey(vip.payment == VipPlacilo.vrata
                 ? "Guests reserve a table in the app and pay in cash at the VIP door. Nothing is charged in the app and no tickets are issued."
                 : "Guests pay for the table in the app and get VIP tickets."))
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if let sporocilo {
            Text(sporocilo).foregroundStyle(.red)
        }

        if vip.enabled && !vip.isSetUp {
            Text("Set up VIP tables at outly.si/app")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Text("Changing this does not affect tables that are already bought or reserved.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    /// Vrstica izbire s kljukico (isti vzorec kot VipRazporedOddelek).
    private func vrstica<L: View>(izbrana: Bool, dejanje: @escaping () -> Void, @ViewBuilder naslov: () -> L) -> some View {
        Button(action: dejanje) {
            HStack {
                naslov()
                Spacer()
                if izbrana {
                    Image(systemName: "checkmark").foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(dela)
        .accessibilityAddTraits(izbrana ? .isSelected : [])
    }

    // MARK: - Klici

    private func nalozi(eventId: Int) async {
        do {
            let r = try await APIClient.shared.fetchBusinessEventVip(eventId: eventId, token: session.token)
            nalaganje = .pripravljeno(r)
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api {
                if code == 401 { session.logout(); return }
                // Star backend ali tuj dogodek: razdelka ni.
                if code == 404 { nalaganje = .skrito; return }
            }
            nalaganje = .napaka(api.userMessage)
        } catch {
            nalaganje = .napaka(error.userMessage)
        }
    }

    /// Takojsnja shranitev. Ob napaki ostane prejsnje stanje (`prejsnji`), sporocilo pove, kaj je narobe.
    private func shrani(eventId: Int, enabled: Bool, payment: String?, prejsnji: BusinessEventVip) async {
        if let payment, payment == prejsnji.payment, enabled == prejsnji.enabled { return }
        sporocilo = nil
        dela = true
        defer { dela = false }
        do {
            let r = try await APIClient.shared.setBusinessEventVip(eventId: eventId, enabled: enabled, payment: payment,
                                                                   token: session.token, clubId: clubId)
            nalaganje = .pripravljeno(r)
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            sporocilo = api.userMessage
        } catch {
            sporocilo = error.userMessage
        }
    }
}
