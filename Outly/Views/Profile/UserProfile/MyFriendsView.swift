import SwiftUI

/// Profil -> My friends (Martin, 20. 9. 2026; prenova 21. 9.): zgoraj moder gumb "Add friends",
/// ki odpre list z iskanjem po uporabniskem imenu (vzorec kot Instagram/BeReal: iskanje je
/// loceno od seznama, poslana prosnja = obrobljen pil "Requested", dotik ga preklice).
/// Pod gumbom prejete prosnje (Accept / Decline), poslane ("Requested") in seznam prijateljev.
/// Isti slog kot My Clubs (kartice bela 8 %, radij 16, modra samo za dejanje).
/// Potisnjen pogled — brez lastnega NavigationStack.
/// Podatki: GET /users/search, GET /me/friends, POST/DELETE /me/friends/requests*, DELETE /me/friends/:id.
@MainActor
struct MyFriendsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var friends: [FriendUser] = []
    @State private var requestsIn: [FriendRequest] = []
    @State private var requestsOut: [FriendRequest] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showAdd = false

    /// Id prosnje, za katero teče klic (gumb kaže vrtavko).
    @State private var busy: Set<Int> = []
    @State private var removeCandidate: FriendUser?

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    VStack(alignment: .leading, spacing: 4) {
                        Text("My friends")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        Text("Friends can see which events you're going to.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .padding(.top, 6)

                    gumbDodaj

                    if !requestsIn.isEmpty {
                        naslov("Friend requests", stevilo: requestsIn.count)
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

                    naslov("Friends", stevilo: friends.isEmpty ? nil : friends.count)
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
        .sheet(isPresented: $showAdd) {
            AddFriendsSheet(requestsIn: requestsIn, requestsOut: requestsOut,
                            onChanged: { Task { await load() } })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .confirmationDialog("Remove friend?", isPresented: Binding(get: { removeCandidate != nil }, set: { if !$0 { removeCandidate = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let f = removeCandidate { Task { await remove(f) } }
            }
            Button("Cancel", role: .cancel) { removeCandidate = nil }
        } message: {
            Text("You will no longer see each other's plans. You can add them again later.")
        }
    }

    // MARK: - Add friends

    /// Edini moder gumb na zaslonu: odpre list z iskanjem.
    private var gumbDodaj: some View {
        Button { showAdd = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                Text("Add friends")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.outlyBlue))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prosnje in prijatelji

    private func prejetaProsnja(_ r: FriendRequest) -> some View {
        FriendRow(user: r.user, podnaslov: String(localized: "wants to be your friend")) {
            HStack(spacing: 8) {
                FriendPill(naslov: "Decline", slog: .obroba, busy: busy.contains(r.id)) { Task { await decline(r) } }
                FriendPill(naslov: "Accept", slog: .modra, busy: busy.contains(r.id)) { Task { await accept(r) } }
            }
        }
    }

    private func poslanaProsnja(_ r: FriendRequest) -> some View {
        FriendRow(user: r.user, podnaslov: String(localized: "Requested · tap to cancel")) {
            FriendPill(naslov: "Requested", slog: .obroba, ikona: "checkmark", busy: busy.contains(r.id)) { Task { await cancel(r) } }
        }
    }

    private func prijatelj(_ f: FriendUser) -> some View {
        FriendRow(user: f) {
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
            Text("Tap Add friends and search by username.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func naslov(_ besedilo: String, stevilo: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LocalizedStringKey(besedilo))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            if let stevilo {
                Text("\(stevilo)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
        }
        .padding(.top, 6)
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

    private func accept(_ r: FriendRequest) async {
        busy.insert(r.id); defer { busy.remove(r.id) }
        errorText = nil
        do {
            _ = try await APIClient.shared.acceptFriendRequest(token: session.token, requestId: r.id)
            await load()
        } catch { errorText = error.userMessage }
    }

    private func decline(_ r: FriendRequest) async {
        busy.insert(r.id); defer { busy.remove(r.id) }
        errorText = nil
        do {
            try await APIClient.shared.declineFriendRequest(token: session.token, requestId: r.id)
            await load()
        } catch { errorText = error.userMessage }
    }

    private func cancel(_ r: FriendRequest) async {
        busy.insert(r.id); defer { busy.remove(r.id) }
        errorText = nil
        do {
            try await APIClient.shared.cancelFriendRequest(token: session.token, requestId: r.id)
            await load()
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

// MARK: - List "Add friends"

/// Iskanje po uporabniskem imenu v listu (odpre ga gumb Add friends). Zadetek: "Add" (moder),
/// "Requested" (obroba, dotik preklice), "Accept" (nasprotna prosnja ze caka) ali "Friends".
/// Po vsakem dejanju javi staršu (`onChanged`), da osvezi sezname; sam osvezi zadetke.
@MainActor
struct AddFriendsSheet: View {
    let requestsIn: [FriendRequest]
    let requestsOut: [FriendRequest]
    var onChanged: () -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fokus: Bool

    @State private var query = ""
    @State private var results: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var busy: Set<Int> = []
    @State private var errorText: String?
    /// Prosnje, poslane v tem listu (id uporabnika -> id prosnje), da "Requested" lahko preklice
    /// tudi preden stars osvezi requestsOut.
    @State private var poslane: [Int: Int] = [:]

    private var ociscen: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add friends")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

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
                    .focused($fokus)
                    .submitLabel(.search)
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

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if ociscen.count < 2 {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 34))
                                .foregroundColor(.white.opacity(0.4))
                            Text("Type at least 2 letters of a username.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if results.isEmpty && !isSearching {
                        Text("No one with that username.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else {
                        ForEach(results) { r in zadetek(r) }
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .onAppear { fokus = true }
        .onChange(of: query) { _, nova in isci(nova) }
    }

    private func zadetek(_ r: UserSearchResult) -> some View {
        FriendRow(user: r.user) {
            switch r.relation {
            case .nobody:
                FriendPill(naslov: "Add", slog: .modra, busy: busy.contains(r.id)) { Task { await add(r.user) } }
            case .friends:
                FriendPill(naslov: "Friends", slog: .oznaka, ikona: "checkmark") {}
            case .requestSent:
                FriendPill(naslov: "Requested", slog: .obroba, ikona: "checkmark", busy: busy.contains(r.id)) { Task { await cancel(userId: r.id) } }
            case .requestReceived:
                if let req = requestsIn.first(where: { $0.user.id == r.id }) {
                    FriendPill(naslov: "Accept", slog: .modra, busy: busy.contains(r.id)) { Task { await accept(req, userId: r.id) } }
                } else {
                    FriendPill(naslov: "Requested", slog: .oznaka) {}
                }
            }
        }
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
        busy.insert(u.id); defer { busy.remove(u.id) }
        errorText = nil
        do {
            let r = try await APIClient.shared.sendFriendRequest(token: session.token, userId: u.id)
            if let req = r.request { poslane[u.id] = req.id }
            onChanged()
            isci(query)
        } catch { errorText = error.userMessage }
    }

    private func accept(_ r: FriendRequest, userId: Int) async {
        busy.insert(userId); defer { busy.remove(userId) }
        errorText = nil
        do {
            _ = try await APIClient.shared.acceptFriendRequest(token: session.token, requestId: r.id)
            onChanged()
            isci(query)
        } catch { errorText = error.userMessage }
    }

    /// Preklic poslane prosnje iz zadetka: id prosnje iz requestsOut ali iz tega lista.
    private func cancel(userId: Int) async {
        guard let reqId = requestsOut.first(where: { $0.user.id == userId })?.id ?? poslane[userId] else {
            onChanged(); return
        }
        busy.insert(userId); defer { busy.remove(userId) }
        errorText = nil
        do {
            try await APIClient.shared.cancelFriendRequest(token: session.token, requestId: reqId)
            poslane[userId] = nil
            onChanged()
            isci(query)
        } catch { errorText = error.userMessage }
    }
}

// MARK: - Skupni gradniki (My friends + list)

/// Vrstica z avatarjem, imenom, neobveznim podnaslovom in vsebino na desni.
struct FriendRow<Desno: View>: View {
    let user: FriendUser
    var podnaslov: String? = nil
    @ViewBuilder var desno: () -> Desno

    var body: some View {
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
                        .lineLimit(1)
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
}

/// Pil za dejanje ob uporabniku: moder (Add, Accept), obrobljen (Requested, Decline) ali oznaka (Friends).
struct FriendPill: View {
    enum Slog { case modra, obroba, oznaka }

    let naslov: String
    var slog: Slog = .modra
    var ikona: String? = nil
    var busy: Bool = false
    var action: () -> Void

    private var barvaBesedila: Color {
        switch slog {
        case .modra: return .white
        case .obroba: return .white.opacity(0.9)
        case .oznaka: return .white.opacity(0.55)
        }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: 5) {
                        if let ikona {
                            Image(systemName: ikona).font(.system(size: 11, weight: .bold))
                        }
                        Text(LocalizedStringKey(naslov)).font(.system(size: 13, weight: .bold))
                    }
                }
            }
            .foregroundColor(barvaBesedila)
            .frame(minWidth: 64)
            .frame(height: 34)
            .padding(.horizontal, 12)
            .background(Capsule().fill(slog == .modra ? Color.outlyBlue : Color.white.opacity(slog == .obroba ? 0.06 : 0.0)))
            .overlay(Capsule().stroke(Color.white.opacity(slog == .obroba ? 0.35 : 0), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy || slog == .oznaka)
    }
}
