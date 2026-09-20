import SwiftUI

/// Profil -> My friends (Martin, 20. 9. 2026): iskanje po uporabniskem imenu, prejete
/// in poslane prosnje, seznam prijateljev. Isti slog kot My Clubs (kartice bela 8 %,
/// radij 16-18, modra samo za dejanje). Potisnjen pogled — brez lastnega NavigationStack.
/// Podatki: GET /users/search, GET /me/friends, POST/DELETE /me/friends/requests*, DELETE /me/friends/:id.
@MainActor
struct MyFriendsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var friends: [FriendUser] = []
    @State private var requestsIn: [FriendRequest] = []
    @State private var requestsOut: [FriendRequest] = []
    @State private var isLoading = false
    @State private var errorText: String?

    @State private var query = ""
    @State private var results: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    /// Id uporabnika ali prosnje, za katero teče klic (gumb kaže vrtavko).
    @State private var busy: Set<String> = []
    @State private var removeCandidate: FriendUser?

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("My friends")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    iskanje

                    if !requestsIn.isEmpty {
                        naslov("Friend requests")
                        VStack(spacing: 10) {
                            ForEach(requestsIn) { r in prejetaProsnja(r) }
                        }
                    }

                    if !requestsOut.isEmpty {
                        naslov("Sent requests")
                        VStack(spacing: 10) {
                            ForEach(requestsOut) { r in poslanaProsnja(r) }
                        }
                    }

                    naslov("Friends")
                    if isLoading && friends.isEmpty {
                        HStack { Spacer(); ProgressView().tint(.white); Spacer() }.padding(.vertical, 20)
                    } else if friends.isEmpty {
                        prazno
                    } else {
                        VStack(spacing: 10) {
                            ForEach(friends) { f in prijatelj(f) }
                        }
                    }

                    if let errorText {
                        Text(errorText)
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
        .onChange(of: query) { _, nova in isci(nova) }
        .confirmationDialog("Remove friend?", isPresented: Binding(get: { removeCandidate != nil }, set: { if !$0 { removeCandidate = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let f = removeCandidate { Task { await remove(f) } }
            }
            Button("Cancel", role: .cancel) { removeCandidate = nil }
        } message: {
            Text("You will no longer see each other's plans. You can add them again later.")
        }
    }

    // MARK: - Iskanje

    private var iskanje: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                TextField("Search by username", text: $query)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .tint(.outlyBlue)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if isSearching {
                    ProgressView().tint(.white)
                } else if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))

            if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                if results.isEmpty && !isSearching {
                    Text("No one with that username.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(results) { r in zadetek(r) }
                    }
                }
            }
        }
    }

    private func zadetek(_ r: UserSearchResult) -> some View {
        vrstica(user: r.user) {
            switch r.relation {
            case .nobody:
                gumb("Add", modra: true, busy: busy.contains("u\(r.id)")) { Task { await add(r.user) } }
            case .friends:
                oznaka("Friends")
            case .requestSent:
                oznaka("Requested")
            case .requestReceived:
                if let req = requestsIn.first(where: { $0.user.id == r.id }) {
                    gumb("Accept", modra: true, busy: busy.contains("r\(req.id)")) { Task { await accept(req) } }
                } else {
                    oznaka("Requested")
                }
            }
        }
    }

    // MARK: - Prosnje in prijatelji

    private func prejetaProsnja(_ r: FriendRequest) -> some View {
        vrstica(user: r.user, podnaslov: String(localized: "wants to be your friend")) {
            HStack(spacing: 8) {
                gumb("Decline", modra: false, busy: busy.contains("r\(r.id)")) { Task { await decline(r) } }
                gumb("Accept", modra: true, busy: busy.contains("r\(r.id)")) { Task { await accept(r) } }
            }
        }
    }

    private func poslanaProsnja(_ r: FriendRequest) -> some View {
        vrstica(user: r.user, podnaslov: String(localized: "request sent")) {
            gumb("Cancel", modra: false, busy: busy.contains("r\(r.id)")) { Task { await cancel(r) } }
        }
    }

    private func prijatelj(_ f: FriendUser) -> some View {
        vrstica(user: f) {
            Button { removeCandidate = f } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove friend"))
        }
    }

    private var prazno: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.5))
            Text("No friends yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            Text("Search by username to add someone. Friends can see which events you're going to.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Gradniki

    private func naslov(_ besedilo: String) -> some View {
        Text(LocalizedStringKey(besedilo))
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .padding(.top, 6)
    }

    private func vrstica<Desno: View>(user: FriendUser, podnaslov: String? = nil, @ViewBuilder desno: () -> Desno) -> some View {
        HStack(spacing: 12) {
            OutlyAvatarView(avatarUrlString: user.avatarUrl, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let podnaslov {
                    Text(podnaslov)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 8)
            desno()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func gumb(_ naslov: String, modra: Bool, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(LocalizedStringKey(naslov))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(minWidth: 64)
            .frame(height: 34)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(modra ? Color.outlyBlue : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func oznaka(_ besedilo: String) -> some View {
        Text(LocalizedStringKey(besedilo))
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    // MARK: - Podatki

    private func load() async {
        guard session.isLoggedIn else { return }
        isLoading = true
        defer { isLoading = false }
        errorText = nil
        do {
            let r = try await APIClient.shared.fetchMyFriends(token: session.token)
            friends = r.friends
            requestsIn = r.requestsIn
            requestsOut = r.requestsOut
        } catch {
            errorText = error.userMessage
        }
        // Znacka na zvoncu in v profilu (pending_friend_requests).
        await session.refreshMe()
    }

    /// Iskanje s kratkim zamikom, da ne klicemo streznika ob vsaki crki (omejitev 120/h).
    private func isci(_ q: String) {
        searchTask?.cancel()
        let ocisceno = q.trimmingCharacters(in: .whitespaces)
        guard ocisceno.count >= 2 else { results = []; isSearching = false; return }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            do {
                let r = try await APIClient.shared.searchUsers(token: session.token, query: ocisceno)
                if !Task.isCancelled { results = r }
            } catch {
                if !Task.isCancelled { results = []; errorText = error.userMessage }
            }
            if !Task.isCancelled { isSearching = false }
        }
    }

    private func add(_ u: FriendUser) async {
        busy.insert("u\(u.id)"); defer { busy.remove("u\(u.id)") }
        errorText = nil
        do {
            _ = try await APIClient.shared.sendFriendRequest(token: session.token, userId: u.id)
            await load()
            isci(query)
        } catch { errorText = error.userMessage }
    }

    private func accept(_ r: FriendRequest) async {
        busy.insert("r\(r.id)"); defer { busy.remove("r\(r.id)") }
        errorText = nil
        do {
            _ = try await APIClient.shared.acceptFriendRequest(token: session.token, requestId: r.id)
            await load()
            isci(query)
        } catch { errorText = error.userMessage }
    }

    private func decline(_ r: FriendRequest) async {
        busy.insert("r\(r.id)"); defer { busy.remove("r\(r.id)") }
        errorText = nil
        do {
            try await APIClient.shared.declineFriendRequest(token: session.token, requestId: r.id)
            await load()
        } catch { errorText = error.userMessage }
    }

    private func cancel(_ r: FriendRequest) async {
        busy.insert("r\(r.id)"); defer { busy.remove("r\(r.id)") }
        errorText = nil
        do {
            try await APIClient.shared.cancelFriendRequest(token: session.token, requestId: r.id)
            await load()
            isci(query)
        } catch { errorText = error.userMessage }
    }

    private func remove(_ f: FriendUser) async {
        removeCandidate = nil
        errorText = nil
        do {
            try await APIClient.shared.removeFriend(token: session.token, userId: f.id)
            await load()
        } catch { errorText = error.userMessage }
    }
}
