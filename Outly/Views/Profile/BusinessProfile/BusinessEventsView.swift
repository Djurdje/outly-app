import SwiftUI

/// Dogodki lastnega kluba — pravi podatki (GET /business/events).
/// Prej je zaslon kazal pet izmisljenih dogodkov in gumb "Add event" ni delal nic.
@MainActor
struct BusinessEventsView: View {
    let clubId: Int?
    let clubName: String?

    @EnvironmentObject private var session: SessionStore

    @State private var events: [APIEvent] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showCreate = false
    @State private var editing: APIEvent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Events")
                        .font(.title.bold())
                    Spacer()
                    Button("Add event") { showCreate = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.outlyBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(clubId == nil)
                        .opacity(clubId == nil ? 0.5 : 1)
                }

                if clubId == nil {
                    Text("Your club is not set up yet. Fill in the club info first.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if isLoading {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                        .padding(.vertical, 30)
                } else if let errorText {
                    VStack(spacing: 10) {
                        Text(errorText).foregroundStyle(.red).font(.subheadline)
                        Button("Try again") { Task { await load() } }
                            .foregroundStyle(Color.outlyBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if events.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.outlyBlue)
                        Text("No events yet")
                            .font(.headline)
                        Text("Tap \"Add event\" to publish your first one.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 14) {
                        ForEach(events) { e in
                            Button { editing = e } label: {
                                BusinessEventRow(event: e)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)   // odmik za spodnjo vrstico (past 8)
        }
        .outlyOzadje()
        .preferredColorScheme(.dark)
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            if let clubId {
                EventFormView(clubId: clubId, existing: nil) { _ in
                    Task { await load() }
                }
            }
        }
        .sheet(item: $editing) { e in
            if let clubId {
                EventFormView(clubId: clubId, existing: e) { _ in
                    Task { await load() }
                }
            }
        }
    }

    private func load() async {
        guard clubId != nil, !session.token.isEmpty else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let list = try await APIClient.shared.fetchMyBusinessEvents(token: session.token)
            // Prihajajoci najprej (najblizji na vrhu), nato pretekli (najnovejsi na vrhu).
            let now = Date()
            let upcoming = list.filter { ($0.startDate ?? .distantPast) >= now }
                .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            let past = list.filter { ($0.startDate ?? .distantPast) < now }
                .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            events = upcoming + past
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            errorText = api.userMessage
        } catch {
            errorText = error.userMessage
        }
    }
}

private struct BusinessEventRow: View {
    let event: APIEvent

    private var statusText: String {
        switch event.status {
        case "cancelled": return String(localized: "Cancelled")
        case "draft":     return String(localized: "Draft")
        // "Ended" po istem pravilu kot streznik (lifecycle, backend 019): konec, sicer zacetek + 8 h.
        default:          return event.hasEnded ? String(localized: "Ended") : String(localized: "Upcoming")
        }
    }

    private var statusColor: Color {
        switch event.status {
        case "cancelled": return .red
        case "draft":     return .orange
        default:          return event.hasEnded ? .gray : .green
        }
    }

    private var dateText: String {
        guard let d = event.startDate else { return event.startAt }
        let f = DateFormatter()
        f.dateFormat = "d. MMM yyyy, HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let url = URL(string: event.posterUrl), !event.posterUrl.isEmpty {
                OutlyAsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.08)
                }
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 78, height: 78)
                    .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.4)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(dateText)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                    if let p = event.displayPrice {
                        Text(p)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    // Klub takoj vidi, kje je posnetek in kje ga sme dodati (backend 019).
                    if !event.recapVideoUrl.isEmpty {
                        Label("Video", systemImage: "play.rectangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.outlyBlue)
                    } else if event.recapAllowed {
                        Label("Add video", systemImage: "plus.rectangle.on.folder")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Spacer()

            Text("Edit")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.outlyBlue)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
