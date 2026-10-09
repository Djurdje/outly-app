import SwiftUI

/// Razdelek »VIP tables« v obrazcu dogodka za organizatorja (backend migracija 039, issue outly-backend#175).
/// Organizator izbere vir razporeda miz za ta dogodek: tloris kluba gostitelja (kopija), lasten tloris ali brez VIP miz.
/// Razdelek je samo za obstojec dogodek (potrebuje id): pri novem pove, naj dogodek najprej shrani.
/// Star backend (404 na `vip-layout`) razdelek skrije. Brez lastnega NavigationStack: urejevalnik se odpre v listu.
@MainActor
struct VipRazporedOddelek: View {
    let clubId: Int
    /// nil = dogodek se ni shranjen.
    let eventId: Int?
    /// Obrazec ima neshranjene spremembe: kopija gostitelja in urejevalnik delata na shranjenem dogodku, zato sta onemogocena.
    let neshranjeno: Bool

    @EnvironmentObject private var session: SessionStore

    private enum Nalaganje {
        case nalaga
        case skrito
        case napaka(String)
        case pripravljeno(VipLayout)
    }

    private struct Urejanje: Identifiable {
        let id = UUID()
        let layout: VipLayout
    }

    @State private var nalaganje: Nalaganje = .nalaga
    @State private var urejanje: Urejanje?
    @State private var dela = false
    @State private var sporocilo: String?
    @State private var potrdiKopijo = false
    @State private var potrdiBrez = false

    var body: some View {
        if let eventId {
            if case .skrito = nalaganje {
                EmptyView()
            } else {
                Section {
                    vsebina(eventId: eventId)
                } header: {
                    Text("VIP tables")
                }
            }
        } else {
            Section {
                Text("Save the event first, then set up its VIP tables.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("VIP tables")
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
        case .pripravljeno(let layout):
            izbira(layout: layout, eventId: eventId)
        }
    }

    @ViewBuilder
    private func izbira(layout: VipLayout, eventId: Int) -> some View {
        let imeGostitelja = layout.venueClubName.isEmpty ? String(localized: "the venue") : layout.venueClubName

        if layout.venueHasLayout {
            vrstica(layout.jeKopijaGostitelja, onemogoceno: neshranjeno) {
                if layout.jeDogodkov {
                    potrdiKopijo = true
                } else {
                    Task { await kopiraj(eventId: eventId) }
                }
            } naslov: {
                Text("Use \(imeGostitelja)'s layout")
            }
        }

        vrstica(layout.jeDogodkov && !layout.jeKopijaGostitelja, onemogoceno: neshranjeno) {
            if layout.jeDogodkov {
                urejanje = Urejanje(layout: layout)
            } else {
                urejanje = Urejanje(layout: layout.prazen())
            }
        } naslov: {
            Text("Own layout for this event")
        }

        vrstica(!layout.jeDogodkov) {
            if layout.jeDogodkov { potrdiBrez = true }
        } naslov: {
            Text("No VIP tables")
        }

        if layout.jeDogodkov {
            Button {
                urejanje = Urejanje(layout: layout)
            } label: {
                HStack {
                    Text("Edit tables and layout")
                    Spacer()
                    Text(verbatim: String(layout.aktivneMize.count)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .disabled(dela || neshranjeno)
        }

        if neshranjeno {
            Text("Save your changes first. The layout is set up on the saved event.")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if let sporocilo {
            Text(sporocilo).foregroundStyle(.red)
        }

        Text(opis(layout))
            .font(.caption)
            .foregroundColor(.secondary)
            .sheet(item: $urejanje) { z in
                NavigationStack {
                    VipUrejevalnikView(vir: .dogodek(eventId: eventId, clubId: clubId), zacetno: z.layout) { shranjen in
                        nalaganje = .pripravljeno(shranjen)
                        sporocilo = nil
                    }
                }
                .environmentObject(session)
            }
            .confirmationDialog("Replace the tables of this event?", isPresented: $potrdiKopijo, titleVisibility: .visible) {
                Button("Copy the venue's layout", role: .destructive) { Task { await kopiraj(eventId: eventId) } }
                Button("Keep my layout", role: .cancel) {}
            } message: {
                Text("Your current tables and prices for this event are replaced by a fresh copy of the venue's layout.")
            }
            .confirmationDialog("Remove VIP tables from this event?", isPresented: $potrdiBrez, titleVisibility: .visible) {
                Button("Remove VIP tables", role: .destructive) { Task { await brezVip(eventId: eventId) } }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("The tables and prices drawn for this event are lost. Tables with orders stay archived and those orders stay valid. Phone reservations on these tables are released.")
            }
    }

    private func opis(_ layout: VipLayout) -> String {
        if !layout.jeDogodkov {
            return String(localized: "This event has no VIP tables. Choose a layout to sell tables.")
        }
        if layout.aktivneMize.isEmpty {
            return String(localized: "This event has its own layout, but no tables yet.")
        }
        return String(localized: "Guests pick a table on this event's own layout.")
    }

    /// Vrstica izbire s kljukico. `izbrana` je trenutno stanje; dotik poklice `dejanje`.
    private func vrstica<L: View>(_ izbrana: Bool, onemogoceno: Bool = false, dejanje: @escaping () -> Void, @ViewBuilder naslov: () -> L) -> some View {
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
        .disabled(dela || onemogoceno)
        .opacity(onemogoceno ? 0.4 : 1)
        .accessibilityAddTraits(izbrana ? .isSelected : [])
    }

    // MARK: - Klici

    private func nalozi(eventId: Int) async {
        do {
            let r = try await APIClient.shared.fetchVipLayout(vir: .dogodek(eventId: eventId, clubId: clubId), token: session.token)
            nalaganje = .pripravljeno(r)
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api {
                if code == 401 { session.logout(); return }
                // Star backend (brez migracije 039) ali tuj dogodek: razdelka ni.
                if code == 404 { nalaganje = .skrito; return }
            }
            nalaganje = .napaka(api.userMessage)
        } catch {
            nalaganje = .napaka(error.userMessage)
        }
    }

    /// Kopija tlorisa gostitelja, nato se odpre urejevalnik na dogodku (cene in mize se uredijo tam).
    private func kopiraj(eventId: Int) async {
        sporocilo = nil
        dela = true
        defer { dela = false }
        do {
            let r = try await APIClient.shared.copyVipLayoutFromVenue(eventId: eventId, clubId: clubId, token: session.token)
            nalaganje = .pripravljeno(r)
            urejanje = Urejanje(layout: r)
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            sporocilo = api.userMessage
        } catch {
            sporocilo = error.userMessage
        }
    }

    private func brezVip(eventId: Int) async {
        sporocilo = nil
        dela = true
        defer { dela = false }
        do {
            let r = try await APIClient.shared.resetVipLayoutToClub(eventId: eventId, clubId: clubId, token: session.token)
            nalaganje = .pripravljeno(r)
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            sporocilo = api.userMessage
        } catch {
            sporocilo = error.userMessage
        }
    }
}
