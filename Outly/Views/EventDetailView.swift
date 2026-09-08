import SwiftUI
import MapKit
import UIKit

struct EventDetailView: View {
    let event: APIEvent

    @State private var club: APIClub?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showBuy = false
    @EnvironmentObject private var session: SessionStore

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.0569, longitude: 14.5058),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                headerPoster

                clubRow

                infoBlock

                aboutBlock

                vipBlock

                contactFooter
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await loadClub() }
        .sheet(isPresented: $showBuy) {
            BuyTicketsView(event: event, clubName: club?.name ?? "Club")
                .environmentObject(session)
        }
    }

    // MARK: - Header (poster + title + centered ticket button)
    private var headerPoster: some View {
        ZStack {
            // Poster
            if !event.posterUrl.isEmpty, let url = URL(string: event.posterUrl) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().opacity(0.12)
                }
            } else {
                Rectangle().opacity(0.12)
            }

            // Gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Centered ticket button a bit above bottom
            VStack {
                Spacer()
                buyTicketButton
                    .padding(.bottom, 24)
            }
        }
        .frame(height: 420)
        .clipped()
    }

    private var buyTicketButton: some View {
        let isEnded = event.isPast
        let topText = isEnded ? "END" : (event.displayPrice ?? "Tickets")

        return VStack(spacing: 2) {
            Text(topText)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white.opacity(isEnded ? 0.6 : 1.0))

            Text(isEnded ? "event ended" : "per ticket")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(isEnded ? 0.45 : 0.75))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        
        .background(
            Group {
                if isEnded {
                    Color.gray.opacity(0.30)
                } else {
                    Color.blackColor.opacity(0.70)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    Color.white.opacity(isEnded ? 0.35 : 0.9),
                    lineWidth: 2
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .opacity(isEnded ? 0.7 : 1.0)
        .onTapGesture {
            guard !isEnded else { return }

            // Cena na Outlyju -> nakup v aplikaciji (BuyTicketsView, testni nacin do Stripa).
            // Brez cene, a s tujo povezavo -> tuja prodaja v brskalniku.
            if event.ticketPriceCents != nil {
                showBuy = true
            } else if let urlStr = event.ticketUrl,
                      !urlStr.isEmpty,
                      let url = URL(string: urlStr) {
                UIApplication.shared.open(url)
            }
        }
    }


    // MARK: - Club line (logo + name)
    private var clubRow: some View {
        HStack(spacing: 12) {
            if let club, !club.logoUrl.isEmpty, let url = URL(string: club.logoUrl) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().opacity(0.12)
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            } else {
                Circle().opacity(0.12)
                    .frame(width: 42, height: 42)
                    .overlay(Text("🎧"))
            }

            Text((club?.name ?? "Club").uppercased())
                .font(.headline)
                .tracking(0.6)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Info block (address/phone/map style)
    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    labeled("ADDRESS", club?.addressFull ?? "-")
                    labeled("PHONE", club?.contactPhone.isEmpty == false ? club!.contactPhone : "-")

                    labeled("DATE", "\(event.displayDateShort) \(event.displayTimeShort.isEmpty ? "" : "• \(event.displayTimeShort)")")
                }

                Spacer(minLength: 0)

                if let club, let lat = club.lat, let lng = club.lng {
                    Map(coordinateRegion: $region, annotationItems: [Pin(lat: lat, lng: lng)]) { pin in
                        MapMarker(coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng))
                    }
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .onAppear {
                        region.center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .opacity(0.10)
                        .frame(width: 150, height: 150)
                        .overlay(Image(systemName: "map").font(.title2))
                }
            }

            Button {
                // kasneje: open bar price link / sheet
            } label: {
                Text("BAR PRICE")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if isLoading {
                ProgressView().padding(.top, 6)
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    // MARK: - About
    private var aboutBlock: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("ABOUT EVENT:")
                .font(.headline)
                .padding(.top, 4)

            Text(event.description.isEmpty ? "No description." : event.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - VIP
    private var vipBlock: some View {
        VStack(spacing: 12) {
            Text("VIP and TABLES:")
                .font(.headline)
                .padding(.top, 8)

            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
                .frame(height: 120)
                .overlay(
                    VStack(spacing: 6) {
                        Text("No VIPs or TABLES available")
                            .font(.headline)
                        Text("For this event!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                )
                .padding(.horizontal, 16)
        }
        .padding(.top, 6)
    }

    // MARK: - Footer contact
    private var contactFooter: some View {
        VStack(spacing: 8) {
            Text("FOR MORE QUESTIONS CALL:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(club?.contactPhone.isEmpty == false ? club!.contactPhone : "+386 ...")
                .font(.headline)
                .foregroundStyle(.blue)
        }
        .padding(.top, 10)
        .padding(.bottom, 40)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func loadClub() async {
        isLoading = true
        errorText = nil
        do {
            let c = try await APIClient.shared.fetchClub(id: event.clubId)
            await MainActor.run {
                self.club = c
            }
        } catch {
            await MainActor.run {
                self.errorText = error.localizedDescription
            }
        }
        isLoading = false
    }
}

// MARK: - Helpers
private struct Pin: Identifiable {
    let id = UUID()
    let lat: Double
    let lng: Double
}

private extension APIClub {
    var addressFull: String {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let co = country.trimmingCharacters(in: .whitespacesAndNewlines)

        if !a.isEmpty && !c.isEmpty { return "\(a) \(c) \(co)".trimmingCharacters(in: .whitespaces) }
        if !a.isEmpty { return "\(a) \(co)".trimmingCharacters(in: .whitespaces) }
        if !c.isEmpty { return "\(c) \(co)".trimmingCharacters(in: .whitespaces) }
        return co.isEmpty ? "-" : co
    }
}
