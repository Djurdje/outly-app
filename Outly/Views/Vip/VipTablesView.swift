import SwiftUI
import UIKit

/// VIP mize dogodka (sheet iz EventDetailView, kot BuyTicketsView): tloris kluba -> dotik proste mize ->
/// izbira bottle paketa (vstet v ceno) -> "Reserve table". Placilo je do Stripa v TESTNEM nacinu
/// (narocilo je takoj placano, denar se ne premakne) - zaslon to pove enako kot pri vstopnicah.
/// Prijava, starost in omejitve uveljavi streznik (isto kot pri nakupu vstopnic): napaka gre v `userMessage`.
/// Po uspehu ima kupec N VIP vstopnic (vsaka svoja QR koda) v Profile -> Tickets. Uspesni zaslon (tudi po vrnitvi s Stripa) takoj
/// ponudi izbiro prijateljev (najvec N-1, `VipRazdelitevBlok`); kar kupec ne poslje, ostane v Tickets in gre od tam z navadnim prenosom.
@MainActor
struct VipTablesView: View {
    let event: APIEvent
    let clubName: String
    /// Prodajalec (klub dogodka), ce ga klicatelj ze ima; sicer `vip.seller` (GET /events/:id/vip), sicer `event.seller`.
    /// Star backend ga nima -> nil in zaslon je kot doslej (backend#94).
    var seller: Seller? = nil

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
    /// Predizpolnitev po nerazresenem poskusu tece (branje GET /me/orders): izbira mize in paketa je do konca onemogocena.
    @State private var predizpolnjujem = false
    @State private var stanje: StanjeAkcije = .miruje
    @State private var errorMessage: String?
    /// Nerazresena vsebina ob odprtju lista (glej `predizpolniIzbiro`); izgine ob naslednjem pritisku na Reserve. Napotek
    /// (`napotek`) se izpelje iz nje in iz TRENUTNE izbire mize in paketa.
    @State private var nerazresena: NakupniKljuc.Vsebina?
    @State private var purchase: PurchaseResponse?
    /// 503 zaradi navale ali 409 request_in_progress: gumb je kratek cas onemogocen, nakup se ne ponovi sam.
    @State private var naval = false
    /// Razdelitev VIP vstopnic prijateljem tece (`VipRazdelitevBlok`): list se med posiljanjem ne sme zapreti.
    @State private var razdeljuje = false
    /// Placilo prek Stripe Checkouta (klub s povezanim Stripom): odprta Stripova stran (ASWebAuthenticationSession), narocilo v cakanju, ponovno branje.
    @StateObject private var stripe = StripeNakup()
    /// Vsebina MOJEGA `pending` narocila, ki drzi mizo (outly-app#59): nastavi se ob ponovnem odprtju lista (miza je »Booked«, a drzana zame)
    /// in ko Stripova stran uspesno odprta. Dokler je nastavljena, kupec ne sme izbrati druge mize ali zamenjati paketa (nov kljuc bi
    /// prepisal edini zapis in izgubil pot nazaj na to narocilo); gumb nadaljuje placilo z ISTIM kljucem in paketom iz narocila.
    /// Pocisti jo uspeh, 409 `order_not_active` / zavrnjen kljuc in opuscen nakup (v `rezerviraj` in `preveriPlacilo`).
    @State private var zadrzana: NakupniKljuc.Vsebina?

    private let ozadje = Color(white: 0.06)
    private let kartica = Color(white: 0.11)

    private var koda: String { vip?.currency ?? event.currency ?? "EUR" }

    /// Prodajalec mize: odgovor tloris (sveze), sicer klicatelj, sicer dogodek.
    private var prodajalec: Seller? { vip?.seller ?? seller ?? event.seller }

    /// Nacin placila kluba (backend `payment_mode`): iz odgovora tlorisa, sicer iz dogodka; nil iz starega backenda = `.neznan`.
    private var nacin: NacinPlacila { NacinPlacila(vip?.paymentMode ?? event.paymentMode) }

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
    private var paketIzbran: Bool {
        VipNadaljevanje.paketIzbran(paketObvezen: paketObvezen, izbraniPaketId: izbraniPaketId, mizaId: izbranaMizaId, zadrzana: zadrzana)
    }

    private var jeStripe: Bool { nacin == .stripe }

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
                    .disabled(stanje == .nalaga || razdeljuje)
                }
            }
            .toolbarBackground(ozadje, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(stanje == .nalaga || razdeljuje)
        // Uspesen nakup = prvi smiseln trenutek za dovoljenje za potisna obvestila (vstopnica, prenos, guest lista). Samo ce se
        // uporabnik se ni odlocil (notDetermined); sistemski poziv se pokaze z zamikom, da je uspeh se viden.
        .onChange(of: purchase != nil) { _, uspel in
            if uspel { PushObvestila.deljen.predlagajDovoljenje() }
        }
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

                    if VipNadaljevanje.kazeKarticoZadrzano(zadrzana: zadrzana, izbranaMizaId: izbranaMizaId, stripe: jeStripe,
                                                           cakaNaPotrditev: stripe.caka != nil) {
                        NapotekKartica(besedilo: String(localized: "Your table is on hold until you pay. Continue to payment to finish booking it."))
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
                        VStack(alignment: .leading, spacing: 12) {
                            karticaMize(m, vip: vip)
                            // Prodajalec + DDV PRED placilom (backend#94, #101); tu ni drugega stavka o posredniku.
                            if let prodajalec {
                                OutlyProdajalecBlok(seller: prodajalec, kazeDdv: true, kazePosrednika: true)
                            } else {
                                // Star backend brez `seller`: samo DDV vrstica `null` (pogodba backend#94/#101).
                                Text(Seller.ddvBesedilo(nil))
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                        }
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
                    VStack(spacing: 8) {
                        gumbRezerviraj(m)
                        OutlyPogojiNakupa()
                        // Isti stavek in slog kot v BuyTicketsView (ZVPot-1, 135/12): miza je vedno za dogodek z datumom.
                        Text("Tickets for a dated event cannot be returned after purchase (ZVPot-1, 135/12). The seller is the club; Outly is the intermediary.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.40))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
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

            // Ko je placilo ze v teku pri Stripu, vrstica »Test mode« ne sme ostati (ni res). Napis se kaze samo pri
            // `payment_mode == "test"` in ceni > 0 (star backend: kot doslej); »unavailable« = pojasnilo namesto nakupa (sicer 409).
            if stripe.caka == nil {
                if nacin.prodajaNedosegljiva {
                    NapotekKartica(besedilo: String(localized: "Tickets aren't on sale in the app yet."))
                } else if nacin.kazeTestniNapis(brezplacno: m.priceCents <= 0) {
                    vrsticaPlacila
                }
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
            guard stanje == .miruje, !predizpolnjujem else { return }
            guard VipNadaljevanje.smeZamenjatiPaket(zadrzana: zadrzana) else {
                errorMessage = String(localized: "Finish paying for your held table first.")
                return
            }
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

    /// Gumb nadaljuje obstojece placilo (zadrzana miza), ne zacne novega nakupa. Pri nejasnem izidu brez znanega narocila
    /// (timeout) ostane »Reserve table« z obstojecim kljucem.
    private func nadaljujePlacilo(_ m: VipTable) -> Bool {
        VipNadaljevanje.nadaljujePlacilo(mizaId: m.id, zadrzana: zadrzana, stripe: jeStripe)
    }

    private func naslovGumba(_ m: VipTable) -> String {
        if nadaljujePlacilo(m) { return String(localized: "Continue to payment") }
        if m.priceCents <= 0 { return String(localized: "Reserve table") }
        return String(localized: "Reserve table · \(Denar.evri(m.priceCents, koda: koda))")
    }

    private func gumbRezerviraj(_ m: VipTable) -> some View {
        OutlyAkcijskiGumb(naslov: naslovGumba(m), stanje: $stanje) {
            Task { await rezerviraj(m) }
        }
        .disabled(!paketIzbran || naval || stripe.preverjanje || nacin.prodajaNedosegljiva)
        .opacity(paketIzbran && !naval && !stripe.preverjanje && !nacin.prodajaNedosegljiva ? 1 : 0.45)
        .outlySij(moc: 1.0, aktiven: paketIzbran && !naval && !stripe.preverjanje && !nacin.prodajaNedosegljiva)
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

                // Izbira prijateljev (najvec N-1); »Skip« in »Done« zapreta list, neposlane vstopnice ostanejo v Tickets.
                VipRazdelitevBlok(vstopnice: p.tickets, minAge: event.minAge,
                                  imaPaket: !(p.order.packageName ?? "").isEmpty,
                                  zaposlen: $razdeljuje, onDone: { dismiss() })
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
        guard stanje == .miruje, !predizpolnjujem else { return }
        guard VipNadaljevanje.smeIzbrati(mizaId: m.id, prosta: m.available, zadrzana: zadrzana) else {
            // Moje placilo za drugo mizo se ni zakljuceno: druga izbira bi izgubila pot nazaj nanj.
            if m.available, zadrzana != nil {
                errorMessage = String(localized: "Finish paying for your held table first.")
            }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        errorMessage = nil
        izbranaMizaId = m.id
    }

    /// Nerazresena vsebina VIP mize tega uporabnika in dogodka (zivi kljuc v `NakupniKljucShramba`), sicer nil.
    private func odprtaVsebinaMize() -> NakupniKljuc.Vsebina? {
        NakupniKljucShramba.deljena.odprtaVsebina(uporabnik: session.me?.id ?? NakupniKljucShramba.neznanUporabnik,
                                                 dogodekId: event.id, vrsta: .vipMiza)
    }

    /// Nalozi tloris. Ob osvezitvi po 409 se izbira obdrzi samo, ce je miza se prosta; izjema je miza, ki jo drzi MOJE
    /// placilo (`zadrzana`, `obdrziMojo`, outly-app#59: `pending` narocilo zasede mizo, a je moja). Po 409 »already booked« / »price changed«
    /// (`obdrziMojo: false`) mize ne drzimo: ponovitev z istim kljucem bi bila 409 le, ce narocila s tem kljucem ni.
    private func naloziVip(obdrziMojo: Bool = true) async {
        nalaganje = true
        defer { nalaganje = false }
        do {
            let novo = try await APIClient.shared.fetchEventVip(eventId: event.id, token: session.token)
            vip = novo
            napakaNalaganja = nil
            if let id = izbranaMizaId, !(novo.tables.first { $0.id == id }?.available ?? false) {
                let moja = obdrziMojo && VipNadaljevanje.jeMojaMiza(odprta: zadrzana, dogodekId: event.id, mizaId: id)
                if !moja { izbranaMizaId = nil }
            }
            if let pid = izbraniPaketId, !novo.packages.contains(where: { $0.id == pid }) {
                izbraniPaketId = nil
            }
            await predizpolniIzbiro(novo)
        } catch {
            if vip == nil { napakaNalaganja = error.userMessage }
        }
    }

    /// Ponovno odprt list po nejasnem izidu (timeout, zapri, odpri): miza in paket zadnjega nerazresenega poskusa, da
    /// Reserve table poslje isto vsebino z istim kljucem (NakupniKljucShramba). Samo ob prvem nalaganju; paket samo, ce ga klub se ponuja.
    /// Vsebina vstopnic (mizaId == nil) tu ne velja. Zapomni nerazresen poskus za napotek. Mize ne zaklene.
    ///
    /// Miza, ki ni vec prosta (outly-app#59: moje `pending` narocilo jo drzi, ker jo backend steje za zasedeno), se NE izbere na slepo:
    /// preberemo moja narocila in `VipNadaljevanje.razvrsti` pove, kaj je z narocilom. Brez odgovora strezniku ostane stari napotek
    /// (»Check Profile -> Tickets«), izbire ni.
    private func predizpolniIzbiro(_ novo: EventVip) async {
        guard !predizpolnjeno else { return }
        predizpolnjeno = true
        predizpolnjujem = true
        defer { predizpolnjujem = false }   // tudi ob zgodnjem izhodu, napaki branja ali preklicu
        // Samo zapis VIP mize: nerazresene vstopnice istega dogodka imajo svoj zapis (#137).
        let prej = odprtaVsebinaMize()
        nerazresena = prej
        guard let v = prej, let mizaId = v.mizaId,
              let miza = novo.tables.first(where: { $0.id == mizaId }) else { return }
        if miza.available {
            izberiPredizpolnjeno(v, novo)
            return
        }
        guard let narocila = try? await APIClient.shared.fetchMyOrders(token: session.token) else { return }
        // Branje lahko traja (strezniku za potekla narocila kliče Stripe): kupec je medtem lahko izbral drugo mizo ali pritisnil Reserve,
        // zapis kljuca pa pripada ze drugi vsebini. Takrat NE naredimo nicesar (zlasti ne zavrzemo kljuca nove izbire).
        // `!Task.isCancelled`: odgovor, ki je prisel po zaprtju lista, ne sme klicati poNapaki/poUspehu.
        guard !Task.isCancelled,
              VipNadaljevanje.smeUveljaviti(zacetna: v, odprtaZdaj: odprtaVsebinaMize(),
                                            izbranaMizaId: izbranaMizaId, miruje: stanje == .miruje) else { return }
        let izid = VipNadaljevanje.razvrsti(narocila: narocila, dogodekId: event.id, mizaId: mizaId)
        let uporabnik = session.me?.id ?? NakupniKljucShramba.neznanUporabnik
        switch izid.stanje {
        case .nadaljuj:
            izberiPredizpolnjeno(v, novo)
            nerazresena = nil          // znamo vec kot »morda«: namesto napotka o nejasnem izidu pove kartica »on hold«
            zadrzana = v               // paket ostane tisti iz kljuca, tudi ce ga klub medtem ne ponuja vec (glej vsebinaNakupa)
        case .placano:
            guard let n = izid.narocilo else { return }
            // Kupec je placal, uspeha pa ni videl: kljuc stran, uspesni zaslon (VIP vstopnice + razdelitev prijateljem).
            NakupniKljucShramba.deljena.poUspehu(uporabnik: uporabnik, dogodekId: event.id, vrsta: .vipMiza)
            nerazresena = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { purchase = VipNadaljevanje.odgovor(n) }
        case .vObdelavi:
            nerazresena = nil
            errorMessage = StripePlacilo.sporociloVObdelavi
        case .poteklo:
            nerazresena = nil
            errorMessage = StripePlacilo.sporociloPotekla
        case .ni:
            // Mojega aktivnega narocila ni (preklicano) in miza je zasedena: tuja ali telefonska rezervacija. Kljuc se zavrze.
            NakupniKljucShramba.deljena.poNapaki(uporabnik: uporabnik, dogodekId: event.id, vrsta: .vipMiza, izid: .narociloNeaktivno)
            nerazresena = nil
            errorMessage = String(localized: "This table is already booked.")
            // Osvezi tloris (miza je lahko spet prosta). Brez rekurzije: `predizpolnjeno` je ze true, zato predizpolniIzbiro takoj vrne.
            await naloziVip(obdrziMojo: false)
        case .nejasno:
            break
        }
    }

    /// Predizbere mizo in paket nerazresenega poskusa (paket samo, ce ga klub se ponuja).
    private func izberiPredizpolnjeno(_ v: NakupniKljuc.Vsebina, _ novo: EventVip) {
        guard let mizaId = v.mizaId else { return }
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
            zadrzana = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { purchase = p }
        } else {
            errorMessage = stripe.napaka
            // Opuscen nakup (`StripeNakup.preveri` `.opuscen`) zavrti kljuc: zapisa ni vec, narocila na mizi ni, miza ni vec zadrzana.
            if odprtaVsebinaMize() == nil { zadrzana = nil }
        }
    }

    private func rezerviraj(_ m: VipTable) async {
        errorMessage = nil
        nerazresena = nil
        stripe.ponastavi()
        stanje = .nalaga
        let uporabnik = session.me?.id ?? NakupniKljucShramba.neznanUporabnik
        // Zadrzana miza: vsebina (miza + paket) zadrzanega narocila, da kljuc ostane isti; sicer navadna izbira.
        let vsebina = VipNadaljevanje.vsebinaNakupa(dogodekId: event.id, mizaId: m.id, izbraniPaketId: izbraniPaketId, zadrzana: zadrzana)
        let kljucNakupa = NakupniKljucShramba.deljena.zaNakup(uporabnik: uporabnik, vsebina: vsebina)
        do {
            let p = try await APIClient.shared.buyTable(eventId: event.id, tableId: m.id,
                                                        packageId: vsebina.paketId, expectedPriceCents: m.priceCents,
                                                        idempotencyKey: kljucNakupa, token: session.token)
            if p.cakaPlacilo {
                // Narocilo je `pending` in drzi mizo: izbira druge mize ali paketa je od zdaj blokirana (kljuc ostane isti).
                zadrzana = vsebina
                // Stripe: vstopnic se ni (nastanejo po webhooku), zato NE »Your VIP table is booked«. Kljuc se NE pozabi: ponovni
                // pritisk Reserve, dokler je narocilo pending, vrne isto narocilo in isti checkout_url (miza ostane drzana).
                // Pozabi ga StripeNakup, ko je placano.
                if stripe.odpri(p, uporabnik: uporabnik, dogodekId: event.id, vrsta: .vipMiza) {
                    stanje = .miruje
                } else {
                    // Potekla seja (checkout_expired): sporocilo iz StripeNakup, sicer povezave ni bilo mogoce odpreti.
                    errorMessage = stripe.napaka ?? String(localized: "We couldn't open the payment page. Please try again.")
                    stanje = .napaka
                }
                return
            }
            NakupniKljucShramba.deljena.poUspehu(uporabnik: uporabnik, dogodekId: event.id, vrsta: .vipMiza)
            zadrzana = nil
            // Haptika .success in kljukica prideta iz OutlyAkcijskiGumb (onChange stanja).
            stanje = .uspeh
            try? await Task.sleep(nanoseconds: manjGibanja ? 100_000_000 : 450_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { purchase = p }
        } catch {
            let izid = error.nakupniIzid
            NakupniKljucShramba.deljena.poNapaki(uporabnik: uporabnik, dogodekId: event.id, vrsta: .vipMiza, izid: izid)
            errorMessage = error.nakupUserMessage
            stanje = .napaka
            // Kljuc zavrnjen ali narocilo ni vec aktivno (potekla seja): narocila, ki bi drzalo mizo, ni vec.
            if izid == .narociloNeaktivno || izid == .kljucZavrzen || error.osveziTlorisPoNapaki { zadrzana = nil }
            // 409: miza je medtem ze prodana, cena spremenjena ali prodaja zaprta -> osvezi tloris, izbira izgine
            // (izjemi request_in_progress in order_not_active: glej `osveziTlorisPoNapaki`).
            if error.osveziTlorisPoNapaki {
                await naloziVip(obdrziMojo: false)
            }
            if let premor = error.nakupPremorNanosekund {
                naval = true
                try? await Task.sleep(nanoseconds: premor)
                naval = false
            }
        }
    }
}
