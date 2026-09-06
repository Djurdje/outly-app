import SwiftUI

struct SearchView: View {
    @State private var query = ""

    @State private var clubs: [APIClub] = []
    @State private var isLoading = false
    @State private var errorText: String?

    // filtrirani klubi glede na vnos
    private var filteredClubs: [APIClub] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        return clubs.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {

                // SEARCH BAR
                TextField("Search clubs or events", text: $query)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                if isLoading {
                    ProgressView()
                        .padding(.top, 8)
                }

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                // SUGGESTIONS
                if !filteredClubs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredClubs) { club in
                            NavigationLink {
                                ClubDetailView(clubId: club.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.gray)

                                    Text(club.name)
                                        .foregroundColor(.white)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray.opacity(0.7))
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .background(Color.gray.opacity(0.3))
                        }
                    }
                    .padding(.top, 8)
                } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading {
                    Text("No results.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Search")
            .task {
                await loadClubs()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadClubs() async {
        guard clubs.isEmpty else { return }
        isLoading = true
        errorText = nil
        do {
            clubs = try await APIClient.shared.fetchClubs()
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
