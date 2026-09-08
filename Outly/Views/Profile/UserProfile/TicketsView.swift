import SwiftUI

/// Vstopnice uporabnika (GET /me/tickets). Prihajajoce zgoraj, pretekle spodaj.
/// Dotik odpre vstopnico s kodo QR za vrata.
@MainActor
struct TicketsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var tickets: [APITicket] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private var upcoming: [APITicket] { tickets.filter { !$0.isPast } }
    private var past: [APITicket] { tickets.filter { $0.isPast } }

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
                    if t.isUsed {
                        Text("USED").font(.caption.weight(.bold)).foregroundColor(.gray)
                    } else {
                        Text("VALID").font(.caption.weight(.bold)).foregroundColor(.outlyBlue)
                    }
                    Text(t.publicRef).font(.caption).foregroundColor(.gray)
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

/// Ena vstopnica: QR za vrata, podatki o dogodku.
struct TicketDetailView: View {
    let ticket: APITicket

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Text(ticket.eventTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                Text(ticket.clubName)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))

                if let d = ticket.startDate {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }

                QRCodeView(content: ticket.qr, size: 240)
                    .padding(.top, 6)
                    .opacity(ticket.isUsed ? 0.35 : 1)
                    .overlay {
                        if ticket.isUsed {
                            Text("ALREADY USED")
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(.red)
                                .rotationEffect(.degrees(-15))
                        }
                    }

                Text(ticket.serial.uppercased())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))

                VStack(spacing: 8) {
                    vrstica("Order", ticket.publicRef)
                    vrstica("Status", ticket.isUsed ? "Used" : "Valid")
                    if !ticket.address.isEmpty { vrstica("Address", "\(ticket.address), \(ticket.city)") }
                    if ticket.minAge > 0 { vrstica("Age", "\(ticket.minAge)+ (ID at the door)") }
                }
                .padding(16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("Show this code at the entrance. Screenshot works too — the code is signed and valid only once.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private func vrstica(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(v).foregroundColor(.white)
        }
        .font(.system(size: 14))
    }
}

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white)

            TextField(placeholder, text: $text)
                .foregroundColor(.white)
        }
        .padding(12)
        .background(Color.outlyBlue)
        .cornerRadius(12)
    }
}
