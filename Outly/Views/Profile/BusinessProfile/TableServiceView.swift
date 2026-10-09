import SwiftUI

/// Strezba VIP miz (vloga bartender, backend issue #176): ko vratar skenira VIP vstopnico, miza pride na ta seznam.
/// Natakar, manager in lastnik jo oznacijo »Delivered« (in jo lahko razveljavijo z »Undo«). Vratar zaslona ne vidi.
/// Brez kupcevih podatkov (invarianta I27): kartica kaze samo oznako mize, paket, opis in cas skena.
/// Izbira dogodka: privzeto tisti, ki tece, sicer najblizji prihajajoci. Osvezitev: poteg navzdol + samodejno vsakih 30 s,
/// dokler je zaslon viden. Potisnjen pogled, brez lastnega NavigationStack.
@MainActor
struct TableServiceView: View {
    let clubId: Int
    let clubName: String?
    /// Dogodek, ki ga odpre zvonec; nil = privzeti (tisti, ki tece).
    var initialEventId: Int? = nil

    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var events: [APIEvent] = []
    @State private var eventId: Int?
    @State private var items: [TableServiceItem] = []
    @State private var eventsLoaded = false
    @State private var itemsLoaded = false
    @State private var errorText: String?
    @State private var busyId: Int?

    /// Vloge, ki smejo videti strezbo (vratar ne).
    static func smeVideti(role: String) -> Bool {
        role == "owner" || role == "manager" || role == "bartender"
    }

    private static let osvezitevNs: UInt64 = 30_000_000_000

    // MARK: - Izpeljano

    private var cakajoce: [TableServiceItem] {
        items.filter { !$0.jeDostavljeno }
            .sorted { ($0.scannedDate ?? .distantFuture) < ($1.scannedDate ?? .distantFuture) }
    }

    private var dostavljene: [TableServiceItem] {
        items.filter { $0.jeDostavljeno }
            .sorted { ($0.deliveredDate ?? .distantPast) > ($1.deliveredDate ?? .distantPast) }
    }

    private var izbraniDogodek: APIEvent? {
        guard let eventId else { return nil }
        return events.first { $0.id == eventId }
    }

    // MARK: - Telo

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                glava
                if eventsLoaded && events.isEmpty {
                    prazno(ikona: "calendar", besedilo: "No events yet")
                } else {
                    izbiraDogodka
                    vsebina
                }
                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        // Samostojna naloga: SwiftUI sicer prekine osvezitev ob spremembi stanja (glej HomeView).
        .refreshable { await Task { await osvezi() }.value }
        .task { await naloziDogodke() }
        // Ob izbiri dogodka: nalozi seznam in ga osvezuj vsakih 30 s. Naloga se ob izginotju zaslona prekine.
        .task(id: eventId) { await zanka() }
        .onChange(of: scenePhase) { _, faza in
            if faza == .active, let id = eventId { Task { await naloziStrezbo(id, tiho: true) } }
        }
    }

    private var glava: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Table service")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
            if let clubName, !clubName.isEmpty {
                Text(verbatim: clubName)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.top, 6)
    }

    private var izbiraDogodka: some View {
        Menu {
            Picker("Event", selection: $eventId) {
                ForEach(events) { e in
                    Text(verbatim: Self.oznaka(e)).tag(Optional(e.id))
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Text(verbatim: izbraniDogodek.map { Self.oznaka($0) } ?? String(localized: "Choose an event"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .disabled(events.count < 2)
    }

    @ViewBuilder
    private var vsebina: some View {
        if eventId == nil || !itemsLoaded {
            if errorText == nil {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                    .padding(.top, 30)
            }
        } else if items.isEmpty {
            prazno(ikona: "wineglass", besedilo: "No tables scanned yet.")
        } else {
            if cakajoce.isEmpty {
                prazno(ikona: "checkmark.circle", besedilo: "Nothing left to serve.")
            } else {
                VStack(spacing: 12) {
                    ForEach(cakajoce) { t in
                        kartica(t)
                    }
                }
            }
            if !dostavljene.isEmpty {
                Text("Delivered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 6)
                VStack(spacing: 12) {
                    ForEach(dostavljene) { t in
                        karticaDostavljena(t)
                    }
                }
            }
        }
    }

    private func prazno(ikona: String, besedilo: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: ikona)
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.4))
            Text(besedilo)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Kartice

    private func oznakaMize(_ label: String, dimljeno: Bool) -> some View {
        Text(verbatim: label.isEmpty ? "-" : label)
            .font(.system(size: 30, weight: .bold))
            .foregroundColor(.white.opacity(dimljeno ? 0.6 : 1))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 8)
            .frame(width: 84, height: 84)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(dimljeno ? 0.06 : 0.12)))
    }

    private func podatki(_ t: TableServiceItem, vrstica: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !t.packageName.isEmpty {
                Text(verbatim: t.packageName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if !t.packageDescription.isEmpty {
                Text(verbatim: t.packageDescription)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if t.tableSeats > 0 {
                Text("Seats: \(t.tableSeats)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(verbatim: vrstica)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func kartica(_ t: TableServiceItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                oznakaMize(t.tableLabel, dimljeno: false)
                podatki(t, vrstica: String(localized: "Scanned \(Self.ura(t.scannedDate))"))
                Spacer(minLength: 0)
            }
            OutlyPrimaryButton(title: "Delivered", isLoading: busyId == t.id) {
                Task { await nastavi(t, dostavljeno: true) }
            }
            .disabled(busyId != nil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func karticaDostavljena(_ t: TableServiceItem) -> some View {
        let kdo: String = t.deliveredByUsername ?? ""
        let cas: String = Self.ura(t.deliveredDate)
        let vrstica: String = kdo.isEmpty
            ? String(localized: "Delivered at \(cas)")
            : String(localized: "Delivered at \(cas) by \(kdo)")
        return HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                oznakaMize(t.tableLabel, dimljeno: true)
                podatki(t, vrstica: vrstica)
                Spacer(minLength: 0)
            }
            .opacity(0.55)

            Button {
                Task { await nastavi(t, dostavljeno: false) }
            } label: {
                Group {
                    if busyId == t.id {
                        ProgressView().tint(.white)
                    } else {
                        Text("Undo")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(busyId != nil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    // MARK: - Pomozne

    private static func ura(_ d: Date?) -> String {
        guard let d else { return "" }
        return DateParsing.shortTime.string(from: d)
    }

    /// »Naslov · 10/10 23:00« za izbirnik dogodka.
    private static func oznaka(_ e: APIEvent) -> String {
        let cas = [e.displayDateShort, e.displayTimeShort].filter { !$0.isEmpty }.joined(separator: " ")
        return cas.isEmpty ? e.title : "\(e.title) · \(cas)"
    }

    /// Dogodek tece od 2 h pred zacetkom do konca (brez konca: zacetek + 8 h) — isto okno kot na strezniku.
    private static func tece(_ e: APIEvent, zdaj: Date) -> Bool {
        guard let zacetek = e.startDate else { return false }
        let konec = e.endDate ?? zacetek.addingTimeInterval(8 * 3600)
        return zacetek.addingTimeInterval(-2 * 3600) <= zdaj && zdaj <= konec
    }

    /// Dogodki za izbirnik: tekoci, prihajajoci (najblizji najprej), nato nekaj preteklih (najnovejsi najprej).
    /// Osnutki in odpovedani so izpuscen.
    static func urediDogodke(_ vsi: [APIEvent], zdaj: Date = Date()) -> [APIEvent] {
        let objavljeni = vsi.filter { $0.status != "draft" && $0.status != "cancelled" }
        let zacetek: (APIEvent) -> Date = { $0.startDate ?? .distantPast }
        let tececi = objavljeni.filter { tece($0, zdaj: zdaj) }.sorted { zacetek($0) < zacetek($1) }
        let ostali = objavljeni.filter { !tece($0, zdaj: zdaj) }
        let prihajajoci = ostali.filter { zacetek($0) > zdaj }.sorted { zacetek($0) < zacetek($1) }
        let pretekli = Array(ostali.filter { zacetek($0) <= zdaj }.sorted { zacetek($0) > zacetek($1) }.prefix(10))
        return tececi + prihajajoci + pretekli
    }

    /// Privzeti dogodek: ta, ki ga odpre zvonec; sicer tekoci (najblizji zacetku), sicer najblizji prihajajoci,
    /// sicer najnovejsi pretekli. `urediDogodke` ze vrne ta vrstni red, zato je privzeti kar prvi.
    private func privzeti(_ urejeni: [APIEvent]) -> Int? {
        if let initialEventId, urejeni.contains(where: { $0.id == initialEventId }) { return initialEventId }
        return urejeni.first?.id
    }

    // MARK: - Podatki

    private func naloziDogodke() async {
        guard !session.token.isEmpty else { return }
        do {
            let vsi = try await APIClient.shared.fetchBusinessEvents(token: session.token, clubId: clubId)
            let urejeni = Self.urediDogodke(vsi)
            events = urejeni
            eventsLoaded = true
            errorText = nil
            if eventId == nil { eventId = privzeti(urejeni) }
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            eventsLoaded = true
            errorText = api.userMessage
        } catch {
            if Task.isCancelled { return }
            eventsLoaded = true
            errorText = error.userMessage
        }
    }

    /// Nalozi seznam izbranega dogodka, nato ga osvezuje vsakih 30 s, dokler je zaslon viden (v ozadju aplikacije iOS zamrzne
    /// casovnik; ob vrnitvi osvezi onChange(scenePhase)).
    private func zanka() async {
        guard let id = eventId else { return }
        items = []
        itemsLoaded = false
        await naloziStrezbo(id, tiho: false)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.osvezitevNs)
            if Task.isCancelled { break }
            await naloziStrezbo(id, tiho: true)
        }
    }

    /// `tiho`: osvezitev v ozadju — ob napaki ostane star seznam, napaka se ne kaze.
    private func naloziStrezbo(_ id: Int, tiho: Bool) async {
        guard !session.token.isEmpty else { return }
        do {
            let novi = try await APIClient.shared.fetchTableService(token: session.token, eventId: id, clubId: clubId)
            guard eventId == id else { return }
            items = novi
            itemsLoaded = true
            errorText = nil
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            guard eventId == id else { return }
            if !tiho { itemsLoaded = true; errorText = api.userMessage }
        } catch {
            if Task.isCancelled || tiho { return }
            guard eventId == id else { return }
            itemsLoaded = true
            errorText = error.userMessage
        }
    }

    /// Poteg navzdol: osvezi seznam (in dogodke, ce jih se ni).
    private func osvezi() async {
        if events.isEmpty { await naloziDogodke() }
        if let id = eventId { await naloziStrezbo(id, tiho: false) }
    }

    private func nastavi(_ t: TableServiceItem, dostavljeno: Bool) async {
        busyId = t.id
        defer { busyId = nil }
        do {
            let nov = try await APIClient.shared.setTableServiceDelivered(token: session.token, id: t.id,
                                                                          delivered: dostavljeno, clubId: clubId)
            if let i = items.firstIndex(where: { $0.id == t.id }) { items[i] = nov }
            errorText = nil
        } catch APIError.decodingFailed {
            // Streznik je sprejel spremembo, odgovora ne razumemo: preberi seznam znova.
            if let id = eventId { await naloziStrezbo(id, tiho: false) }
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            errorText = api.userMessage
        } catch {
            errorText = error.userMessage
        }
    }
}
