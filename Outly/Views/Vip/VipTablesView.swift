import SwiftUI
import UIKit

/// VIP mize dogodka (sheet iz EventDetailView, kot BuyTicketsView): tloris kluba -> dotik proste mize ->
/// izbira bottle paketa (vstet v ceno) -> "Reserve table". Placilo je do Stripa v TESTNEM nacinu
/// (narocilo je takoj placano, denar se ne premakne) - zaslon to pove enako kot pri vstopnicah.
/// Prijava, starost in omejitve uveljavi streznik (isto kot pri nakupu vstopnic): napaka gre v `userMessage`.
/// Po uspehu ima kupec N VIP vstopnic (vsaka svoja QR koda) v Profile -> Tickets in jih od tam
/// z navadnim prenosom razdeli prijateljem.
@MainActor
struct VipTablesView: View {
    let event: APIEvent
    let clubName: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @Environment(\.accessibilityReduceMotion) private var manjGibanja

    @State private var vip: EventVip?
    @State private var nalaganje = true
    @State private var napakaNalaganja: String?
    @State private var izbranaMizaId: Int?
    @State private var izbraniPaketId: Int?
    /// Izbira se predizpolni samo ob prvem uspesnem nalaganju tlorisa (glej `naloziVip`).
    @State private var predizpolnjeno = false
    @State private var stanje: StanjeAkcije = .miruje
    @State private var errorMessage: String?
    /// Nerazresena vsebina ob odprtju lista (glej `predizpolniIzbiro`); izgine ob naslednjem pritisku na Reserve. Napotek
    /// (`napotek`) se izpelje iz nje in iz TRENUTNE izbire mize in paketa.
    @State private var nerazresena: NakupniKljuc.Vsebina?
    @State private var purchase: PurchaseResponse?
    /// 503 zaradi navale ali 409 request_in_progress: gumb je kratek cas onemogocen, nakup se ne ponovi sam.
    @State private var naval = false
    /// Placilo prek Stripe Checkouta (klub s povezanim Stripom): odprta Stripova stran (ASWebAuthenticationSession), narocilo v cakanju, ponovno branje.
    @StateObject private var stripe = StripeNakup()

    private let ozadje = Color(white: 0.06)
    private let kartica = Color(white: 0.11)

    private var koda: String { vip?.currency ?? event.currency ?? "EUR" }

    /// Napotek ob ponovnem odprtju po nejasnem izidu, izpeljan iz trenutne izbire: »tap the button again« samo pri isti mizi
    /// in istem paketu (isti kljuc) in ce je prodaja odprta (gumb Reserve); sicer »Check Profile -> Tickets« (miza »Booked«,
    /// druga izbira = nov kljuc, prodaja zaprta). Zacasna onemogocenost zaradi navale (`naval`) napotka ne spremeni.
    private var napotek: NakupniNapotek? {
        var trenutna: NakupniKljuc.Vsebina?
        if let m = izbranaMiza {
            trenutna = NakupniKljuc.Vsebina(dogodekId: event.id, mizaId: m.id, paketId: izbraniPaketId)
        }
        return NakupniNapotek.zaVip(odprta: nerazresena, trenutna: trenutna, gumbNaVoljo: vip?.onSale == true)
    }

    private var izbranaMiza: VipTable? {
        guard let id = izbranaMizaId else { return nil }
        return vip?.tables.first { $0.id == id }
    }

    /// Paket je obvezen, ce ga klub ponuja (backend: sicer 400).
    private var paketObvezen: Bool { !(vip?.packages.isEmpty ?? true) }
    private var paketIzbran: Bool { !paketObvezen || izbraniPaketId != nil }

    var body: some View {
        NavigationStack {
            Group {
                if let purchase {
                    uspeh(purchase)
                } else {
                    vsebina
                }
            }
            .background(ozadje.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(LocalizedStringKey(purchase == nil ? "VIP tables" : "Your VIP table is booked"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(LocalizedStringKey(purchase == nil ? "Cancel" : "Done"))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .disabled(stanje == .nalaga)
                }
            }
            .toolbarBackground(ozadje, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(stanje == .nalaga)
        .task { await naloziVip() }
        // Stripova gostovana stran v ASWebAuthenticationSession: po placilu jo outly://placilo zapre sama in takoj preberemo narocilo
        // (uspeh: vec samodejnih branj, webhook zakasni); izrecni preklic: ostanemo na listu, narocilo preverimo tiho enkrat;
        // zaprtje seje ali napaka: narocilo preberemo enkrat, pending ostane na kartici »Checking your payment«.
        .stripeSeja(stran: $stripe.stran) { izid in
            if izid == .nezagnana {
                stripe.sejaNiZagnana()
                errorMessage = stripe.napaka
                return
            }
            Task { await preveriPlacilo(poskusov: izid.poskusov, tiho: izid.tiho) }
        }
    }

    // MARK: - Vsebina

    @ViewBuilder
    private var vsebina: some View {
        if nalaganje && vip == nil {
            VStack { ProgressView().tint(.white) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let napakaNalaganja, vip == nil {
            VStack(spacing: 10) {
                Text(napakaNalaganja).foregroundColor(.red).font(.subheadline)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await naloziVip() } }.foregroundColor(.outlyBlue)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let vip, vip.isUsable, let plan = vip.plan {
            tloris(vip, plan: plan)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "table.furniture")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text("No VIP tables for this event yet.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tloris(_ vip: EventVip, plan: VipPlan) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    glava
                        .padding(.top, 8)

                    if let napotek {
                        NapotekKartica(besedilo: napotek.besedilo)
                    }

                    if stripe.caka != nil {
                        PlaciloSeVeriKartica(preverjanje: stripe.preverjanje) {
                            Task { await preveriPlacilo(poskusov: 1) }
                        }
                    }

                    VipTloris(
                        plan: plan,
                        mize: vip.tables,
                        izbranaId: izbranaMizaId,
                        prodajaOdprta: vip.onSale,
                        onSelect: { m in izberi(m) }
                    )

                    legenda

                    if !vip.onSale {
                        Text("Table reservations are closed for this event.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if let m = izbranaMiza {
                        karticaMize(m, vip: vip)
                            .id("izbira")
                    } else {
                        Text("Tap a free table to reserve it.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if let errorMessage {
                        napaka(errorMessage)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .onChange(of: izbranaMizaId) { _, novo in
                guard novo != nil else { return }
                withAnimation(manjGibanja ? nil : Animation.easeOut(duration: 0.3)) {
                    proxy.scrollTo("izbira", anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if vip.onSale, let m = izbranaMiza {
                    gumbRezerviraj(m)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                        .background(ozadje)
                }
            }
        }
    }

    private var glava: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clubName.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.55))
            Text(event.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text("\(event.displayDateShort) · \(event.displayTimeShort)")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var legenda: some View {
        HStack(spacing: 18) {
            legendaVnos(polnilo: Color(white: 0.14), obroba: Color.white.opacity(0.65), napis: "Available")
            legendaVnos(polnilo: .outlyBlue, obroba: Color.white.opacity(0.9), napis: "Selected")
            legendaVnos(polnilo: Color.white.opacity(0.03), obroba: Color.white.opacity(0.12), napis: "Booked")
            Spacer(minLength: 0)
        }
    }

    private func legendaVnos(polnilo: Color, obroba: Color, napis: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(polnilo)
                .overlay(Circle().stroke(obroba, lineWidth: 1.5))
                .frame(width: 14, height: 14)
            Text(LocalizedStringKey(napis))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
        }
    }

    // MARK: - Izbrana miza

    private func opisMize(_ m: VipTable) -> String {
        let osebe = String(localized: "Up to \(m.seats) people")
        return "\(VipOznaka.miza(m.label)) · \(osebe) · \(Denar.evri(m.priceCents, koda: koda))"
    }

    private func karticaMize(_ m: VipTable, vip: EventVip) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "table.furniture")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                Text(opisMize(m))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if !vip.packages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "wineglass")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Choose your bottle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    Text("Included in the table price")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))

                    VStack(spacing: 8) {
                        ForEach(vip.packages) { p in
                            vrsticaPaketa(p)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            // Ko je placilo ze v teku pri Stripu, vrstica »Test mode« ne sme ostati (ni res).
            if stripe.caka == nil {
                vrsticaPlacila
            }

            if event.minAge > 0 {
                Text("\(event.minAge)+ · ID at the door")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kartica)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func napaka(_ besedilo: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
            Text(besedilo)
                .font(.system(size: 13))
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func vrsticaPaketa(_ p: VipPackage) -> some View {
        let izbran = izbraniPaketId == p.id
        return Button {
            guard stanje == .miruje else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            izbraniPaketId = p.id
            errorMessage = nil
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: izbran ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(izbran ? .white : .white.opacity(0.45))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: p.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    if !p.description.isEmpty {
                        Text(verbatim: p.description)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(izbran ? 0.10 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(izbran ? 0.55 : 0.0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(izbran ? .isSelected : [])
    }

    /// Isto sporocilo kot pri vstopnicah: dokler ni Stripa, se nic ne zaracuna.
    private var vrsticaPlacila: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Payment")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Test mode — nothing is charged")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Gumb

    private func naslovGumba(_ m: VipTable) -> String {
        if m.priceCents <= 0 { return String(localized: "Reserve table") }
        return String(localized: "Reserve table · \(Denar.evri(m.priceCents, koda: koda))")
    }

    private func gumbRezerviraj(_ m: VipTable) -> some View {
        OutlyAkcijskiGumb(naslov: naslovGumba(m), stanje: $stanje) {
            Task { await rezerviraj(m) }
        }
        .disabled(!paketIzbran || naval || stripe.preverjanje)
        .opacity(paketIzbran && !naval && !stripe.preverjanje ? 1 : 0.45)
        .outlySij(moc: 1.0, aktiven: paketIzbran && !naval && !stripe.preverjanje)
    }

    // MARK: - Uspeh

    private func uspeh(_ p: PurchaseResponse) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color.outlyBlue.opacity(0.15)).frame(width: 84, height: 84)
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.outlyBlue)
                }
                .padding(.top, 16)

                Text("Your VIP table is booked")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        VipZnacka()
                        Text(verbatim: povzetekNarocila(p))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    if let paket = p.order.packageName, !paket.isEmpty {
                        Text(verbatim: paket)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    Text("Order \(p.order.publicRef)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }

                if p.mode == "test" {
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("Test purchase — nothing was charged")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }

                Text("Send the VIP tickets to your friends from Tickets.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.outlyBlue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    /// "Table T1 · Up to 6 people · 300,00 €" iz narocila (posnetek na strezniku).
    private func povzetekNarocila(_ p: PurchaseResponse) -> String {
        var deli: [String] = []
        if let l = p.order.tableLabel, !l.isEmpty { deli.append(VipOznaka.miza(l)) }
        if let n = p.order.tableSeats { deli.append(String(localized: "Up to \(n) people")) }
        deli.append(Denar.evri(p.order.totalCents, koda: p.order.currency))
        return deli.joined(separator: " · ")
    }

    // MARK: - Dejanja

    private func izberi(_ m: VipTable) {
        guard stanje == .miruje, m.available else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        errorMessage = nil
        izbranaMizaId = m.id
    }

    /// Nalozi tloris. Ob osvezitvi po 409 se izbira obdrzi samo, ce je miza se prosta.
    private func naloziVip() async {
        nalaganje = true
        defer { nalaganje = false }
        do {
            let novo = try await APIClient.shared.fetchEventVip(eventId: event.id, token: session.token)
            vip = novo
            napakaNalaganja = nil
            if let id = izbranaMizaId, !(novo.tables.first { $0.id == id }?.available ?? false) {
                izbranaMizaId = nil
            }
            if let pid = izbraniPaketId, !novo.packages.contains(where: { $0.id == pid }) {
                izbraniPaketId = nil
            }
            predizpolniIzbiro(novo)
        } catch {
            if vip == nil { napakaNalaganja = error.userMessage }
        }
    }

    /// Ponovno odprt list po nejasnem izidu (timeout, zapri, odpri): miza in paket zadnjega nerazresenega poskusa, da
    /// Reserve table poslje isto vsebino z istim kljucem (NakupniKljucShramba). Samo ob prvem nalaganju in samo ce je miza
    /// v tlorisu se na voljo (sicer brez izbire); paket samo, ce ga klub se ponuja. Vsebina vstopnic (mizaId == nil) tu ne velja.
    /// Zapomni nerazresen poskus za napotek (miza se ni vec prosta -> »Booked« -> napotek Profile -> Tickets). Mize ne zaklene.
    private func predizpolniIzbiro(_ novo: EventVip) {
        guard !predizpolnjeno else { return }
        predizpolnjeno = true
        // Samo zapis VIP mize: nerazresene vstopnice istega dogodka imajo svoj zapis (#137).
        let prej = NakupniKljucShramba.deljena.odprtaVsebina(uporabnik: session.me?.id ?? NakupniKljucShramba.neznanUporabnik,
                                                            dogodekId: event.id, vrsta: .vipMiza)
        nerazresena = prej
        guard let v = prej, let mizaId = v.mizaId,
              novo.tables.first(where: { $0.id == mizaId })?.available == true else { return }
        izbranaMizaId = mizaId
        if let paketId = v.paketId, novo.packages.contains(where: { $0.id == paketId }) {
            izbraniPaketId = paketId
        }
    }

    /// Po vrnitvi s Stripove strani (samodejno: uspeh vec poskusov, sicer 1 poskus; tiho samo po preklicu) ali na »Check again« (1 poskus): ce je narocilo placano in ima
    /// vstopnice, pokaze obstojeci uspesni zaslon (brez oznake TEST, ker `mode != "test"`); sicer ostane na listu.
    private func preveriPlacilo(poskusov: Int, tiho: Bool = false) async {
        errorMessage = nil
        if let p = await stripe.preveri(token: session.token, poskusov: poskusov, tiho: tiho) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { purchase = p }
        } else {
            errorMessage = stripe.napaka
        }
    }

    private func rezerviraj(_ m: VipTable) async {
        errorMessage = nil
        nerazresena = nil
        stripe.ponastavi()
        stanje = .nalaga
        let uporabnik = session.me?.id ?? NakupniKljucShramba.neznanUporabnik
        let kljucNakupa = NakupniKljucShramba.deljena.zaNakup(
            uporabnik: uporabnik, vsebina: NakupniKljuc.Vsebina(dogodekId: event.id, mizaId: m.id, paketId: izbraniPaketId))
        do {
            let p = try await APIClient.shared.buyTable(eventId: event.id, tableId: m.id,
                                                        packageId: izbraniPaketId, expectedPriceCents: m.priceCents,
                                                        idempotencyKey: kljucNakupa, token: session.token)
            if p.cakaPlacilo {
                // Stripe: vstopnic se ni (nastanejo po webhooku), zato NE »Your VIP table is booked«. Kljuc se NE pozabi: ponovni
                // pritisk Reserve, dokler je narocilo pending, vrne isto narocilo in isti checkout_url (miza ostane drzana).
                // Pozabi ga StripeNakup, ko je placano.
                if stripe.odpri(p, uporabnik: uporabnik, dogodekId: event.id, vrsta: .vipMiza) {
                    stanje = .miruje
                } else {
                    errorMessage = String(localized: "We couldn't open the payment page. Please try again.")
                    stanje = .napaka
                }
                return
            }
            NakupniKljucShramba.deljena.poUspehu(uporabnik: uporabnik, dogodekId: event.id, vrsta: .vipMiza)
            // Haptika .success in kljukica prideta iz OutlyAkcijskiGumb (onChange stanja).
            stanje = .uspeh
            try? await Task.sleep(nanoseconds: manjGibanja ? 100_000_000 : 450_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { purchase = p }
        } catch {
            let izid = error.nakupniIzid
            NakupniKljucShramba.deljena.poNapaki(uporabnik: uporabnik, dogodekId: event.id, vrsta: .vipMiza, izid: izid)
            errorMessage = error.nakupUserMessage
            stanje = .napaka
            // 409: miza je medtem ze prodana, cena spremenjena ali prodaja zaprta -> osvezi tloris, izbira izgine
            // (izjemi request_in_progress in order_not_active: glej `osveziTlorisPoNapaki`).
            if error.osveziTlorisPoNapaki {
                await naloziVip()
            }
            if let premor = error.nakupPremorNanosekund {
                naval = true
                try? await Task.sleep(nanoseconds: premor)
                naval = false
            }
        }
    }
}
