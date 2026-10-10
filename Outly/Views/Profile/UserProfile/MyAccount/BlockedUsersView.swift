import SwiftUI

/// Moj racun -> Blocked users (outly-backend #189, Apple App Review 1.2): seznam uporabnikov, ki sem jih blokiral,
/// z dejanjem Unblock. Prijateljstvo se ob odblokiranju NE obnovi.
/// Potisnjen pogled — brez lastnega NavigationStack. Podatki: GET /me/blocks, DELETE /me/blocks/:userId.
/// Star backend (brez poti) vrne 404 -> sporocilo »Not available yet.«, seznam se ne pokaze kot prazen.
@MainActor
struct BlockedUsersView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var blocked: [BlockedUser] = []
    @State private var isLoading = false
    /// Seznam je bil vsaj enkrat uspesno nalozen (sicer »prazen« ne pomeni, da ni blokiranih).
    @State private var loaded = false
    @State private var errorText: String?
    @State private var busy: Set<Int> = []

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blocked users")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        Text("People you block can't find you or send you requests.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .padding(.top, 6)

                    if isLoading && !loaded {
                        HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 20)
                    } else if loaded && blocked.isEmpty {
                        prazno
                    } else {
                        VStack(spacing: 10) {
                            ForEach(blocked) { b in vrstica(b) }
                        }
                    }

                    if let errorText {
                        Text(verbatim: errorText)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
            // Samostojna naloga: SwiftUI sicer prekine osvezitev ob spremembi stanja (glej HomeView).
            .refreshable { await Task { await load() }.value }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func vrstica(_ b: BlockedUser) -> some View {
        FriendRow(user: b.user) {
            FriendPill(naslov: "Unblock", slog: .obroba, busy: busy.contains(b.userId)) { Task { await unblock(b) } }
        }
    }

    private var prazno: some View {
        VStack(spacing: 8) {
            Image(systemName: "nosign")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.5))
            Text("You haven't blocked anyone.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func load() async {
        guard session.isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }
        errorText = nil
        do {
            blocked = try await APIClient.shared.fetchBlocks(token: session.token)
            loaded = true
        } catch {
            errorText = error.prijavaSporocilo
        }
    }

    private func unblock(_ b: BlockedUser) async {
        busy.insert(b.userId); defer { busy.remove(b.userId) }
        errorText = nil
        do {
            try await APIClient.shared.unblockUser(token: session.token, userId: b.userId)
            blocked.removeAll { $0.userId == b.userId }
        } catch { errorText = error.prijavaSporocilo }
    }
}
