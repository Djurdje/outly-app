import SwiftUI

/// Izbira prizorisca dogodka med klubi na Outlyju (GET /clubs, iskanje po imenu na napravi).
/// Uporablja ga obrazec dogodka organizatorja brez lastnega kluba. Potisnjen pogled — brez lastnega
/// NavigationStacka (trdo pravilo 4). Organizatorji niso prizorisca (nimajo naslova) in se ne kazejo.
@MainActor
struct VenueClubPickerView: View {
    /// Klub, ki dogodek objavlja (ne more biti svoje prizorisce; streznik to zavrne).
    let excludeClubId: Int
    var onPick: (APIClub) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var clubs: [APIClub] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorText: String?

    private var shown: [APIClub] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return clubs
            .filter { $0.id != excludeClubId && !$0.isOrganizer }
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if isLoading && clubs.isEmpty {
                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let errorText {
                VStack(spacing: 10) {
                    Text(errorText).foregroundStyle(.red).font(.subheadline)
                    Button("Try again") { Task { await load() } }
                        .foregroundStyle(Color.outlyBlue)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else if shown.isEmpty {
                Text("No clubs found.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .listRowBackground(Color.clear)
            }

            ForEach(shown) { club in
                Button {
                    onPick(club)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        logo(club)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(club.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if !club.city.isEmpty {
                                Text(club.city)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Select venue")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search"))
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func logo(_ club: APIClub) -> some View {
        Group {
            if !club.logoUrl.isEmpty, let url = URL(string: club.logoUrl) {
                OutlyAsyncImage(url: url) { img in
                    Color.clear.overlay(img.resizable().scaledToFill()).clipped()
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.1))
                }
            } else {
                Rectangle().fill(Color.white.opacity(0.1))
                    .overlay(Image(systemName: "building.2").foregroundStyle(.white.opacity(0.6)))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func load() async {
        guard clubs.isEmpty else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            clubs = try await APIClient.shared.fetchClubs()
        } catch is CancellationError {
        } catch let url as URLError where url.code == .cancelled {
        } catch {
            errorText = error.userMessage
        }
    }
}
