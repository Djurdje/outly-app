import SwiftUI

/// Vrata, en clan ekipe: koliko vstopnic je pregledal po dogodkih (GET /business/team/:userId/scans).
/// Odprt s tapom na vrstico v "Staff activity" na nadzorni plosci (Martin, 25. 9. 2026).
@MainActor
struct StaffScansView: View {
    let member: BusinessActivity.StaffActivity

    @EnvironmentObject private var session: SessionStore

    @State private var events: [StaffScans.EventScans] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    OutlyAvatarView(avatarUrlString: member.avatarUrl, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.username)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text(member.roleLabel)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.top, 6)

                if isLoading && events.isEmpty {
                    HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 30)
                } else if let errorText {
                    VStack(spacing: 10) {
                        Text(errorText).foregroundColor(.red).font(.subheadline)
                        Button("Try again") { Task { await load() } }.foregroundColor(.outlyBlue)
                    }
                    .frame(maxWidth: .infinity)
                } else if events.isEmpty {
                    Text("No scans yet")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    VStack(spacing: 10) {
                        ForEach(events) { e in
                            row(e)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .outlyOzadje()
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .refreshable { await Task { await load() }.value }
        .task { await load() }
    }

    private func row(_ e: StaffScans.EventScans) -> some View {
        HStack(spacing: 12) {
            if !e.posterUrl.isEmpty, let url = URL(string: e.posterUrl) {
                OutlyAsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.1))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.outlyBlue.opacity(0.25))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "calendar").foregroundColor(.outlyBlue))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(datum(e.startDate))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Text("\(e.scans)")
                .font(.headline)
                .foregroundColor(.outlyBlue)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func datum(_ d: Date?) -> String {
        guard let d else { return "" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await APIClient.shared.fetchStaffScans(token: session.token, userId: member.id).events
            errorText = nil
        } catch {
            errorText = error.userMessage
        }
    }
}
