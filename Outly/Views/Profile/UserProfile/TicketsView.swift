import SwiftUI

/// Vstopnice uporabnika (GET /me/tickets). Prihajajoce zgoraj, pretekle spodaj.
/// Dotik odpre vstopnico s kodo QR za vrata.
@MainActor
struct TicketsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var tickets: [APITicket] = []
    @State private var isLoading = false
    @State private var errorText: String?

    // Skenirane (used) izginejo iz glavnega seznama — Martin: "ko se karta skenira, naj zgine iz profila".
    // Ostanejo dosegljive pod zloženim "Used tickets".
    private var upcoming: [APITicket] { tickets.filter { !$0.isPast && !$0.isUsed } }
    private var past: [APITicket] { tickets.filter { $0.isPast && !$0.isUsed } }
    private var used: [APITicket] { tickets.filter { $0.isUsed } }
    @State private var showUsed = false

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tickets")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    if isLoading && tickets.isEmpty {
                        HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.top, 40)
                    } else if let errorText {
                        VStack(spacing: 10) {
                            Text(errorText).foregroundColor(.red).font(.subheadline)
                            Button("Try again") { Task { await load() } }.foregroundColor(.outlyBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    } else if tickets.isEmpty {
                        prazno
                    } else {
                        if upcoming.isEmpty && past.isEmpty {
                            prazno
                        }
                        if !upcoming.isEmpty {
                            Text("Upcoming")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                            ForEach(upcoming) { t in
                                NavigationLink { TicketDetailView(ticket: t) } label: { vrstica(t) }
                                    .buttonStyle(.plain)
                            }
                        }
                        if !past.isEmpty {
                            Text("Past")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.top, 8)
                            ForEach(past) { t in
                                NavigationLink { TicketDetailView(ticket: t) } label: { vrstica(t) }
                                    .buttonStyle(.plain)
                                    .opacity(0.6)
                            }
                        }
                        if !used.isEmpty {
                            Button {
                                withAnimation(.snappy) { showUsed.toggle() }
                            } label: {
                                HStack {
                                    Text("Used tickets (\(used.count))")
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.5))
                                    Spacer()
                                    Image(systemName: showUsed ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .padding(.top, 8)
                            }
                            .buttonStyle(.plain)
                            if showUsed {
                                ForEach(used) { t in
                                    NavigationLink { TicketDetailView(ticket: t) } label: { vrstica(t) }
                                        .buttonStyle(.plain)
                                        .opacity(0.5)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await load() } }
    }

    private var prazno: some View {
        VStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.outlyBlue)
            Text("No tickets yet")
                .font(.title3).fontWeight(.semibold).foregroundColor(.white)
            Text("Tickets you buy through Outly\nwill show up here.")
                .font(.footnote).foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func vrstica(_ t: APITicket) -> some View {
        HStack(spacing: 12) {
            if !t.posterUrl.isEmpty, let url = URL(string: t.posterUrl) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Rectangle().opacity(0.12) }
                    .frame(width: 70, height: 70)
                    .clipped()
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.outlyBlue.opacity(0.25))
                    .frame(width: 70, height: 70)
                    .overlay(Image(systemName: "ticket").foregroundColor(.outlyBlue))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(t.eventTitle)
                    .font(.headline).foregroundColor(.white).lineLimit(1)
                Text("\(t.clubName) · \(datum(t))")
                    .font(.subheadline).foregroundColor(.gray).lineLimit(1)
                HStack(spacing: 6) {
                    Text(t.statusLabel)
                        .font(.caption.weight(.bold))
                        .foregroundColor(t.statusLabel == "VALID" ? .outlyBlue : .gray)
                    Text(t.publicRef).font(.caption).foregroundColor(.gray)
                    if t.transferred && !t.buyerUsername.isEmpty {
                        Text("· from \(t.buyerUsername)").font(.caption).foregroundColor(.gray)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.gray)
        }
        .padding(14)
        .background(Color.gray.opacity(0.14))
        .cornerRadius(16)
    }

    private func datum(_ t: APITicket) -> String {
        guard let d = t.startDate else { return "" }
        return "\(DateParsing.shortDate.string(from: d)) \(DateParsing.shortTime.string(from: d))"
    }

    private func load() async {
        guard session.isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            tickets = try await APIClient.shared.fetchMyTickets(token: session.token)
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }
}

/// Ena vstopnica kot "wallet" kartica: zgornji del s plakatom in podatki, perforacija,
/// spodnji del s QR. Uporabljena vstopnica je zatemnjena in prekrizana.
struct TicketDetailView: View {
    let ticket: APITicket
    @State private var prikazana = false
    @State private var showTransfer = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                WalletTicketCard(ticket: ticket)
                    .padding(.top, 12)
                    .scaleEffect(prikazana ? 1 : 0.96)
                    .opacity(prikazana ? 1 : 0)

                if ticket.transferred && !ticket.buyerUsername.isEmpty {
                    Text("Sent to you by \(ticket.buyerUsername)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Text("Show this code at the entrance. A screenshot works too — the code is signed and valid only once.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                // Prenos prijatelju: samo veljavna vstopnica pred zacetkom dogodka (streznik preveri znova).
                if ticket.transferable {
                    Button { showTransfer = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                            Text("Send to a friend")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { prikazana = true } }
        .sheet(isPresented: $showTransfer) {
            // Po prenosu vstopnica ni vec moja -> nazaj na seznam, ki se ob prikazu osvezi.
            TransferTicketView(ticket: ticket, onTransferred: { dismiss() })
                .environmentObject(session)
        }
    }
}

/// Kartica vstopnice v slogu denarnice. Zgoraj plakat (zatemnjen) s podatki,
/// perforacija z izrezanima polkrogoma, spodaj QR na beli podlagi.
struct WalletTicketCard: View {
    let ticket: APITicket

    private var barva: Color { Color.outlyBlue }

    var body: some View {
        VStack(spacing: 0) {
            zgornjiDel
            perforacija
            spodnjiDel
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: barva.opacity(0.25), radius: 24, y: 10)
        .opacity(ticket.isUsed ? 0.6 : 1)
    }

    private var zgornjiDel: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if !ticket.posterUrl.isEmpty, let url = URL(string: ticket.posterUrl) {
                    AsyncImage(url: url) { img in
                        Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                    } placeholder: { SkeletonBlock() }
                } else {
                    LinearGradient(colors: [barva, Color.purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(height: 210)
            .clipped()

            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if !ticket.logoUrl.isEmpty, let url = URL(string: ticket.logoUrl) {
                        AsyncImage(url: url) { img in
                            Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                        } placeholder: { Circle().fill(Color.white.opacity(0.2)) }
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                    }
                    Text(ticket.clubName.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text(ticket.statusLabel)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundColor(ticket.isUsed ? .white : .black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(ticket.isUsed ? Color.white.opacity(0.25) : Color.white)
                        .clipShape(Capsule())
                }
                Text(ticket.eventTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(18)
        }
        .frame(height: 210)
        // Kartica (ne zaslon): ostane crna tudi nad zamegljenim Home — sicer posnetek preseva skozi robove.
        .background(Color.black)
    }

    private var perforacija: some View {
        ZStack {
            Color(white: 0.09)
            HStack(spacing: 0) {
                Circle().fill(Color.black).frame(width: 22, height: 22).offset(x: -11)
                Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(height: 1)
                Circle().fill(Color.black).frame(width: 22, height: 22).offset(x: 11)
            }
        }
        .frame(height: 22)
    }

    private var spodnjiDel: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                polje("DATE", datum)
                Spacer()
                polje("TIME", cas)
                Spacer()
                polje("ORDER", ticket.publicRef)
            }
            if !ticket.address.isEmpty {
                HStack {
                    polje("VENUE", "\(ticket.address), \(ticket.city)")
                    Spacer()
                }
            }

            ZStack {
                QRCodeView(content: ticket.qr, size: 200)
                if ticket.isUsed {
                    Text("ALREADY USED")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.red)
                        .rotationEffect(.degrees(-14))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.9))
                }
            }
            .padding(.top, 4)

            Text(ticket.serial.uppercased())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            if ticket.minAge > 0 {
                Text("\(ticket.minAge)+ · ID checked at the door")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.09))
    }

    private func polje(_ naslov: String, _ vrednost: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(naslov))
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.white.opacity(0.45))
            Text(vrednost)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
        }
    }

    private var datum: String {
        guard let d = ticket.startDate else { return "—" }
        let f = DateFormatter(); f.locale = Jezik.shared.locale; f.dateFormat = "EEE, d MMM"
        return f.string(from: d)
    }

    private var cas: String {
        guard let d = ticket.startDate else { return "—" }
        return DateParsing.shortTime.string(from: d)
    }
}

/// Vodoravna crta kot Shape (za perforacijo).
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white)

            TextField(LocalizedStringKey(placeholder), text: $text)
                .foregroundColor(.white)
        }
        .padding(12)
        .background(Color.outlyBlue)
        .cornerRadius(12)
    }
}
