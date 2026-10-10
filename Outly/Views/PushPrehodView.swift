import SwiftUI

/// Usmerjanje ob dotiku na potisno obvestilo (APNs, outly-backend#184).
///
/// Cilj dotika (`PushCilj`) pride iz `OutlyAppDelegate` v `PushUsmerjevalnik.deljen.postavi`. Na HLADNEM zagonu je to pred
/// prijavo in prej, kot obstaja MainTabView, zato cilj tam caka: `PushPrehod` (v ozadju MainTabView) ga prevzame ob prikazu
/// in ob vsaki spremembi. Zaslon se odpre kot LIST s svojim NavigationStack (koren lista), cilji pa so potisnjeni pogledi BREZ
/// lastnega NavigationStack (trdo pravilo 4): TicketsView, EventDetailView, TableServiceView. List je izbran zato, ker dotik
/// pride kadarkoli (katerikoli zavihek, odprt zvonec) in Home ima svoj NavigationStack, ki ga od zunaj ni mogoce voditi.
///
/// Cilji (isti kot vrstice zvonca, NotificationsMenuView):
///   vstopnice (`ticket_received`, `guest_list_invite`) -> TicketsView (id vstopnice se ne rabi)
///   dogodek (`club_event`)                              -> EventDetailView (GET /events/:id)
///   strezba (`table_service`)                           -> TableServiceView (klub iz GET /me/table-service, kot vrstica zvonca)
@MainActor
struct PushPrehod: View {
    @EnvironmentObject private var usmerjevalnik: PushUsmerjevalnik
    @EnvironmentObject private var session: SessionStore
    @State private var cilj: PushCilj?

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            // Hladen zagon: cilj caka ze od zagona. Kratek zamik, da se zaslon postavi, preden SwiftUI odpre list
            // (list, odprt med prvim izrisom, se rad izgubi).
            .onAppear {
                guard usmerjevalnik.cakajoci != nil else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    prevzemi()
                }
            }
            .onChange(of: usmerjevalnik.cakajoci) { _, _ in prevzemi() }
            .sheet(item: $cilj) { c in
                PushCiljVsebina(cilj: c)
                    .environmentObject(session)
            }
    }

    private func prevzemi() {
        guard let c = usmerjevalnik.prevzemi() else { return }
        cilj = c
    }
}

/// Koren lista: NavigationStack + Close; vsebina po cilju.
@MainActor
private struct PushCiljVsebina: View {
    let cilj: PushCilj
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            vsebina
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                            .foregroundColor(.white)
                    }
                }
        }
        .preferredColorScheme(.dark)
        // Nov dotik medtem ko je list odprt: nova vsebina z novim stanjem nalaganja.
        .id(cilj.id)
    }

    @ViewBuilder
    private var vsebina: some View {
        switch cilj {
        case .vstopnice:
            TicketsView()
        case .dogodek(let id):
            PushDogodekNalagalnik(eventId: id)
        case .strezba(let id):
            PushStrezbaNalagalnik(strezbaId: id)
        }
    }
}

/// Nalozi dogodek (GET /events/:id) in pokaze EventDetailView.
@MainActor
private struct PushDogodekNalagalnik: View {
    let eventId: Int
    @State private var dogodek: APIEvent?
    @State private var napaka: String?

    var body: some View {
        Group {
            if let dogodek {
                EventDetailView(event: dogodek)
            } else {
                PushNalaganje(napaka: napaka) { Task { await nalozi() } }
            }
        }
        .task { await nalozi() }
    }

    private func nalozi() async {
        napaka = nil
        do {
            dogodek = try await APIClient.shared.fetchEvent(id: eventId)
        } catch {
            napaka = error.userMessage
        }
    }
}

/// Nalozi strezbe, ki cakajo (GET /me/table-service, isti vir kot zvonec), poisce strezbo iz obvestila in pokaze Table service
/// njenega kluba in dogodka. Ce strezbe ni vec na seznamu (je ze dostavljena), odpre prvo cakajoco; ce je ni nobene, to pove.
@MainActor
private struct PushStrezbaNalagalnik: View {
    let strezbaId: Int
    @EnvironmentObject private var session: SessionStore
    @State private var postavka: MyTableServiceItem?
    @State private var nicZaStrezbo = false
    @State private var napaka: String?

    var body: some View {
        Group {
            if let postavka {
                TableServiceView(clubId: postavka.clubId, clubName: postavka.clubName, initialEventId: postavka.eventId)
            } else if nicZaStrezbo {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.45))
                    Text("Nothing left to serve.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .outlyOzadje()
            } else {
                PushNalaganje(napaka: napaka) { Task { await nalozi() } }
            }
        }
        .task { await nalozi() }
    }

    private func nalozi() async {
        napaka = nil
        do {
            let vse = try await APIClient.shared.fetchMyTableService(token: session.token)
            if let najdena = vse.first(where: { $0.id == strezbaId }) ?? vse.first {
                postavka = najdena
            } else {
                nicZaStrezbo = true
            }
        } catch {
            napaka = error.userMessage
        }
    }
}

/// Vrtavka med nalaganjem; ob napaki sporocilo in »Try again«.
@MainActor
private struct PushNalaganje: View {
    let napaka: String?
    let znova: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let napaka {
                Text(napaka)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                OutlyPrimaryButton(title: "Try again", action: znova)
                    .padding(.horizontal, 40)
            } else {
                ProgressView().tint(.white)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .outlyOzadje()
    }
}
