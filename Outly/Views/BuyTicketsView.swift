import SwiftUI
import UIKit

/// Nakup vstopnic (sheet iz EventDetailView). Kolicina -> potrditev -> vstopnice s QR.
/// Videz: temna "wallet" kartica s perforacijo (kot WalletTicketCard v Tickets),
/// plakat dogodka v glavi, gumb Pay z zneskom.
/// Kartica se NE vnasa v aplikaciji (PCI DSS): ko pride Stripe, tu vstopi Stripov
/// obrazec. Do takrat backend dela v TESTNEM nacinu — denar se ne premakne, kar
/// zaslon pove v vrstici "Payment".
@MainActor
struct BuyTicketsView: View {
    let event: APIEvent
    let clubName: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var quantity = 1
    /// Izbira se predizpolni samo ob prvem prikazu (glej `predizpolni`).
    @State private var predizpolnjeno = false
    /// Stanje skupnega akcijskega gumba (OutlyAkcijskiGumb) - nadomesca prejsnji isBuying.
    @State private var stanje: StanjeAkcije = .miruje
    @State private var errorMessage: String?
    /// Nerazresena vsebina ob odprtju lista (glej `predizpolni`); izgine ob naslednjem pritisku na Pay. Napotek (`napotek`)
    /// se izpelje iz nje in iz TRENUTNE kolicine.
    @State private var nerazresena: NakupniKljuc.Vsebina?
    @State private var purchase: PurchaseResponse?
    /// 503 zaradi navale ali 409 request_in_progress: gumb je kratek cas onemogocen, nakup se ne ponovi sam.
    @State private var naval = false
    /// Placilo prek Stripe Checkouta (klub s povezanim Stripom): odprta Stripova stran (ASWebAuthenticationSession), narocilo v cakanju, ponovno branje.
    @StateObject private var stripe = StripeNakup()
    @Environment(\.accessibilityReduceMotion) private var manjGibanja

    private var koda: String { event.currency ?? "EUR" }
    private var unitCents: Int { event.ticketPriceCents ?? 0 }
    private var totalCents: Int { unitCents * quantity }
    private var isFree: Bool { unitCents == 0 }
    /// Nacin placila kluba (backend `payment_mode`); nil iz starega backenda = `.neznan` (danasnje vedenje).
    private var nacin: NacinPlacila { event.nacinPlacila }

    /// Koliko jih je se na voljo (nil = neomejeno / neznano).
    private var remaining: Int? {
        guard let cap = event.capacity else { return nil }
        return max(0, cap - event.soldCount)
    }
    private var maxQuantity: Int { min(10, max(1, remaining ?? 10)) }
    private var soldOut: Bool { event.isSoldOut || remaining == 0 }

    /// Napotek ob ponovnem odprtju po nejasnem izidu, izpeljan iz trenutne izbire: »tap the button again« samo, ce je
    /// kolicina ista (isti kljuc) in je Pay na voljo; sicer »Check Profile -> Tickets«. Zacasna onemogocenost zaradi
    /// navale (`naval`, nekaj sekund) napotka ne spremeni: gumb se sam spet odpre.
    private var napotek: NakupniNapotek? {
        NakupniNapotek.zaVstopnice(
            odprta: nerazresena,
            trenutna: NakupniKljuc.Vsebina(dogodekId: event.id, kolicina: quantity),
            gumbNaVoljo: !soldOut)
    }

    private let ozadje = Color(white: 0.06)
    private let kartica = Color(white: 0.11)

    var body: some View {
        NavigationStack {
            Group {
                if let purchase {
                    uspeh(purchase)
                } else {
                    obrazec
                }
            }
            .onAppear { predizpolni() }
            .background(ozadje.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(LocalizedStringKey(purchase == nil ? "Checkout" : "Your tickets"))
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
        // Uspesen nakup = prvi smiseln trenutek za dovoljenje za potisna obvestila (vstopnica, prenos, guest lista). Samo ce se
        // uporabnik se ni odlocil (notDetermined); sistemski poziv se pokaze z zamikom, da je uspeh se viden.
        .onChange(of: purchase != nil) { _, uspel in
            if uspel { PushObvestila.deljen.predlagajDovoljenje() }
        }
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

    // MARK: - Obrazec

    private var obrazec: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                glavaDogodka
                    .padding(.top, 8)

                if let napotek {
                    NapotekKartica(besedilo: napotek.besedilo)
                }

                if stripe.caka != nil {
                    PlaciloSeVeriKartica(preverjanje: stripe.preverjanje) {
                        Task { await preveriPlacilo(poskusov: 1) }
                    }
                }

                karticaNakupa

                // Ko je placilo ze v teku pri Stripu, vrstica »Test mode« ne sme ostati (ni res). Napis se kaze samo pri
                // `payment_mode == "test"` (star backend: kot doslej); »unavailable« = pojasnilo namesto nakupa (sicer 409).
                if stripe.caka == nil {
                    if nacin.prodajaNedosegljiva {
                        NapotekKartica(besedilo: String(localized: "Tickets aren't on sale in the app yet."))
                    } else if nacin.kazeTestniNapis(brezplacno: isFree) {
                        vrsticaPlacila
                    }
                }

                if let errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                gumbPlacaj
                    .padding(.top, 4)

                OutlyPogojiNakupa()

                Text("Tickets for a dated event cannot be returned after purchase (ZVPot-1, 135/12). The seller is the club; Outly is the intermediary.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.40))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    // Plakat + ime kluba, naslov, datum, starost.
    private var glavaDogodka: some View {
        HStack(alignment: .top, spacing: 14) {
            plakat(width: 72, height: 96, radius: 14)

            VStack(alignment: .leading, spacing: 5) {
                Text(clubName.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.55))
                Text(event.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("\(event.displayDateShort) · \(event.displayTimeShort)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                if event.minAge > 0 {
                    Text("\(event.minAge)+ · ID at the door")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // Wallet kartica: zgoraj kolicina in cena, perforacija, spodaj obracun.
    private var karticaNakupa: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("TICKETS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                    if let r = remaining, r <= 20 {
                        Group {
                            if r == 0 {
                                Text("SOLD OUT")
                            } else {
                                Text("\(r) LEFT")
                            }
                        }
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundColor(r == 0 ? .white : .black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(r == 0 ? Color.white.opacity(0.25) : Color.white)
                        .clipShape(Capsule())
                    }
                }

                HStack(alignment: .center) {
                    izbiraKolicine
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isFree ? String(localized: "Free") : Denar.evri(unitCents, koda: koda))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("per ticket")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(18)
            .background(kartica)

            perforacija

            VStack(spacing: 12) {
                HStack {
                    Text("\(quantity) × \(event.title)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(isFree ? String(localized: "Free") : Denar.evri(totalCents, koda: koda))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                }
                Divider().background(Color.white.opacity(0.12))
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Prices include VAT")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    Spacer()
                    Text(Denar.evri(totalCents, koda: koda))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(18)
            .background(kartica)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.outlyBlue.opacity(0.18), radius: 22, y: 8)
    }

    private var izbiraKolicine: some View {
        HStack(spacing: 14) {
            krogGumb("minus", enabled: quantity > 1 && stanje == .miruje) {
                quantity -= 1
            }
            Text("\(quantity)")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .frame(minWidth: 34)
                .contentTransition(.numericText())
                .animation(.snappy, value: quantity)
            krogGumb("plus", enabled: quantity < maxQuantity && stanje == .miruje) {
                quantity += 1
            }
        }
    }

    private func krogGumb(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(enabled ? .white : .white.opacity(0.3))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(enabled ? 0.12 : 0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var perforacija: some View {
        ZStack {
            kartica
            HStack(spacing: 0) {
                Circle().fill(ozadje).frame(width: 22, height: 22).offset(x: -11)
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 1)
                    .overlay(
                        PerforationLine().stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                            .foregroundColor(.white.opacity(0.25))
                    )
                Circle().fill(ozadje).frame(width: 22, height: 22).offset(x: 11)
            }
        }
        .frame(height: 22)
    }

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
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var gumbPlacaj: some View {
        // Krog + kljukica prek skupnega OutlyAkcijskiGumb (Buy ne dobi naslovUspeha - po
        // kljukici se cel zaslon "razpre" v uspeh(purchase), glej kupi()).
        return OutlyAkcijskiGumb(naslov: naslovGumbaPlacaj(soldOut: soldOut), stanje: $stanje) {
            Task { await kupi() }
        }
        .disabled(soldOut || naval || stripe.preverjanje || nacin.prodajaNedosegljiva)
        .opacity(naval || stripe.preverjanje || nacin.prodajaNedosegljiva ? 0.45 : 1)
        .outlySij(moc: 1.0, aktiven: !soldOut && !naval && !stripe.preverjanje && !nacin.prodajaNedosegljiva)
    }

    /// Naslov gumba Pay glede na stanje; loceno od View-ja, da je vsak izid en `String(localized:)` kljuc.
    private func naslovGumbaPlacaj(soldOut: Bool) -> String {
        if soldOut { return String(localized: "Sold out") }
        if isFree { return quantity == 1 ? String(localized: "Get ticket") : String(localized: "Get tickets") }
        return String(localized: "Pay \(Denar.evri(totalCents, koda: koda))")
    }

    // MARK: - Uspeh

    /// Zabrisan vstop z rahlim zamikom (0,15 s) - za vse razen prve kartice vstopnice,
    /// ki namesto tega "zraste" iz mesta gumba (glej `prvaKarticaVstop`).
    private var zabrisZZamikom: AnyTransition {
        manjGibanja ? .opacity : .outlyZabris.animation(.easeOut(duration: 0.25).delay(0.15))
    }

    /// Prva kartica vstopnice "zraste" iz polozaja gumba Buy (spodaj na zaslonu) -
    /// scale 0.2 -> 1 z anchor .bottom, brez zamika (pojavi se takoj z zaslonom uspeha).
    private var prvaKarticaVstop: AnyTransition {
        manjGibanja
            ? .opacity
            : .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity)
                .animation(.spring(response: 0.5, dampingFraction: 0.8))
    }

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
                .transition(zabrisZZamikom)

                Text("You're in!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .transition(zabrisZZamikom)

                Text(povzetekNarocila(p))
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .transition(zabrisZZamikom)

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
                    .transition(zabrisZZamikom)
                }

                ForEach(Array(p.tickets.enumerated()), id: \.element.id) { i, t in
                    karticaVstopnice(t, index: i + 1, count: p.tickets.count)
                        .transition(i == 0 ? prvaKarticaVstop : zabrisZZamikom)
                }

                Text("Saved under Profile → Tickets. Show the QR code at the door.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .transition(zabrisZZamikom)

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
                .transition(zabrisZZamikom)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    /// Povzetek narocila pod "You're in!": loceni kljuci za narocilo in stevilo vstopnic,
    /// namesto enega niza z rocno mnozino (prevod nastavi mnozinsko obliko).
    private func povzetekNarocila(_ p: PurchaseResponse) -> String {
        let narocilo = String(localized: "Order \(p.order.publicRef)")
        let vstopnice = String(localized: "\(p.tickets.count) tickets")
        let znesek = Denar.evri(p.order.totalCents, koda: p.order.currency)
        return "\(narocilo) · \(vstopnice) · \(znesek)"
    }

    // Kupljena vstopnica: plakat z naslovom, perforacija, QR.
    private func karticaVstopnice(_ t: APITicket, index: Int, count: Int) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                plakat(width: nil, height: 150, radius: 0)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(clubName.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        if count > 1 {
                            Text("\(index) OF \(count)")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.8)
                                .foregroundColor(.black)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(event.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(16)
            }
            .frame(height: 150)
            .clipped()

            perforacija

            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    polje(String(localized: "DATE"), event.displayDateShort)
                    Spacer()
                    polje(String(localized: "TIME"), event.displayTimeShort)
                    Spacer()
                    // Prenesena vstopnica: serial pripada prejemniku, kupcu ga ne kazi (star backend ga se poslje, #124).
                    if !t.jePoslanaDalje && !t.serialKratek.isEmpty {
                        polje(String(localized: "TICKET"), t.serialKratek)
                    }
                }
                if t.jePoslanaDalje {
                    Text(verbatim: t.poslanaNapis)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    QRCodeView(content: t.qr, size: 180)
                        .padding(.top, 4)
                }
            }
            .padding(18)
            .background(kartica)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.outlyBlue.opacity(0.18), radius: 22, y: 8)
    }

    private func polje(_ naslov: String, _ vrednost: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(naslov)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.white.opacity(0.45))
            Text(vrednost)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }

    // Plakat dogodka; brez slike modri preliv. Vedno v okvirju (past 12).
    private func plakat(width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        Group {
            if !event.posterUrl.isEmpty, let url = URL(string: event.posterUrl) {
                Color.clear
                    .overlay(
                        OutlyAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color.white.opacity(0.08))
                        }
                    )
            } else {
                Color(white: 0.14).overlay(Image(systemName: "music.note").font(.system(size: 22)).foregroundColor(.white.opacity(0.3)))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Ponovno odprt list po nejasnem izidu (timeout, zapri, odpri): kolicina zadnjega nerazresenega poskusa, da Pay
    /// poslje isto vsebino z istim kljucem (NakupniKljucShramba). Vsebina VIP mize (mizaId != nil) tu ne velja.
    /// Zapomni nerazresen poskus za napotek (kolicine ne zaklene; napotek sledi trenutni izbiri, glej `napotek`).
    private func predizpolni() {
        guard !predizpolnjeno else { return }
        predizpolnjeno = true
        // Samo zapis vstopnic: nerazresen VIP istega dogodka ima svoj zapis in ga ta list ne sme niti prebrati niti povoziti (#137).
        let prej = NakupniKljucShramba.deljena.odprtaVsebina(uporabnik: session.me?.id ?? NakupniKljucShramba.neznanUporabnik,
                                                            dogodekId: event.id, vrsta: .vstopnice)
        nerazresena = prej
        guard let v = prej, v.mizaId == nil else { return }
        quantity = min(max(v.kolicina, 1), maxQuantity)
    }

    /// Po vrnitvi s Stripove strani (samodejno: uspeh vec poskusov, sicer 1 poskus; tiho samo po preklicu) ali na »Check again« (1 poskus): ce je narocilo placano in ima
    /// vstopnice, pokaze obstojeci uspesni zaslon (brez oznake TEST, ker `mode != "test"`); sicer ostane na nakupnem listu.
    private func preveriPlacilo(poskusov: Int, tiho: Bool = false) async {
        errorMessage = nil
        if let p = await stripe.preveri(token: session.token, poskusov: poskusov, tiho: tiho) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { purchase = p }
        } else {
            errorMessage = stripe.napaka
        }
    }

    private func kupi() async {
        errorMessage = nil
        nerazresena = nil
        stripe.ponastavi()
        stanje = .nalaga
        // Idempotentni kljuc zivi v NakupniKljucShramba (pomnilnik, 24 h), ne v @State: ponovno odprt list isti vsebine
        // ob nejasnem izidu (timeout) dobi ISTI kljuc, zato nakup ni podvojen.
        let uporabnik = session.me?.id ?? NakupniKljucShramba.neznanUporabnik
        let kljucNakupa = NakupniKljucShramba.deljena.zaNakup(
            uporabnik: uporabnik, vsebina: NakupniKljuc.Vsebina(dogodekId: event.id, kolicina: quantity))
        do {
            let p = try await APIClient.shared.buyTickets(token: session.token, eventId: event.id, quantity: quantity,
                                                          idempotencyKey: kljucNakupa)
            if p.cakaPlacilo {
                // Stripe: vstopnic se ni (nastanejo po webhooku), zato NE »You're in!«. Kljuc se NE pozabi: ponovni pritisk Pay,
                // dokler je narocilo pending, vrne isto narocilo in isti checkout_url. Pozabi ga StripeNakup, ko je placano.
                if stripe.odpri(p, uporabnik: uporabnik, dogodekId: event.id, vrsta: .vstopnice) {
                    stanje = .miruje
                } else {
                    // Potekla seja (checkout_expired): sporocilo iz StripeNakup, sicer povezave ni bilo mogoce odpreti.
                    errorMessage = stripe.napaka ?? String(localized: "We couldn't open the payment page. Please try again.")
                    stanje = .napaka
                }
                return
            }
            NakupniKljucShramba.deljena.poUspehu(uporabnik: uporabnik, dogodekId: event.id, vrsta: .vstopnice)
            // Haptika .success in kljukica prideta iz OutlyAkcijskiGumb (onChange stanja).
            stanje = .uspeh
            // Kljukica naj bo za hip vidna, preden se krog "razpre" v vstopnico.
            try? await Task.sleep(nanoseconds: manjGibanja ? 100_000_000 : 450_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { purchase = p }
        } catch {
            // Haptika .error pride iz OutlyAkcijskiGumb (onChange stanja).
            NakupniKljucShramba.deljena.poNapaki(uporabnik: uporabnik, dogodekId: event.id, vrsta: .vstopnice, izid: error.nakupniIzid)
            errorMessage = error.nakupUserMessage
            stanje = .napaka
            if let premor = error.nakupPremorNanosekund {
                naval = true
                try? await Task.sleep(nanoseconds: premor)
                naval = false
            }
        }
    }
}

/// Vodoravna crta kot Shape (za perforacijo na kartici nakupa).
private struct PerforationLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
