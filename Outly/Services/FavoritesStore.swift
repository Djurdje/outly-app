import Foundation
import SwiftUI
import Combine

/// Priljubljeni dogodki (srcek) — od 11. 9. 2026 na strezniku (migracija 012,
/// GET/PUT/DELETE /me/favorites). Prej samo lokalno v @AppStorage, zato so se ob
/// novi namestitvi izgubili.
///
/// Uporaba: @EnvironmentObject var favorites: FavoritesStore
///   favorites.contains(id)            -> srcek poln/prazen
///   favorites.toggle(id, token:)      -> optimisticno, streznik v ozadju
///   favorites.load(token:)            -> ob prijavi / zagonu (MainTabView)
///   favorites.events                  -> seznam za zavihek Saved
///
/// Lokalna kopija id-jev ostane v UserDefaults ("favoriteEventIds", isti kljuc
/// kot prej), da srcki ob zagonu ne utripajo, dokler streznik ne odgovori.
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var ids: Set<Int> = []
    @Published private(set) var events: [APIEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String? = nil
    /// true, ko je seznam vsaj enkrat prisel s streznika (loci "prazno" od "se ni nalozeno").
    @Published private(set) var loaded = false

    private let cacheKey = "favoriteEventIds"
    private var loadTask: Task<Void, Never>?

    init() {
        if let s = UserDefaults.standard.string(forKey: cacheKey),
           let arr = try? JSONDecoder().decode([Int].self, from: Data(s.utf8)) {
            ids = Set(arr)
        }
    }

    func contains(_ eventId: Int) -> Bool { ids.contains(eventId) }

    /// Nalozi s streznika. Vec socasnih klicev deli en zahtevek.
    func load(token: String) async {
        guard !token.isEmpty else { clear(); return }
        if let t = loadTask { await t.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            self.isLoading = true
            defer { self.isLoading = false }
            do {
                let r = try await APIClient.shared.fetchFavorites(token: token)
                self.ids = Set(r.ids)
                self.events = r.events
                self.loaded = true
                self.loadError = nil
                self.shraniCache()
            } catch {
                self.loadError = error.userMessage
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Optimisticno preklopi; ce streznik zavrne, vrne nazaj.
    func toggle(_ eventId: Int, token: String) {
        let novo = !ids.contains(eventId)
        if novo { ids.insert(eventId) } else { ids.remove(eventId); events.removeAll { $0.id == eventId } }
        shraniCache()
        guard !token.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await APIClient.shared.setFavorite(token: token, eventId: eventId, favorite: novo)
                // Po oznacitvi seznam Saved osvezimo, da dobi podatke dogodka.
                if novo { await self.load(token: token) }
            } catch {
                if novo { self.ids.remove(eventId) } else { self.ids.insert(eventId) }
                self.shraniCache()
                // Pri neuspesnem odznacevanju je dogodek ze izpadel iz seznama — nalozimo znova.
                if !novo { await self.load(token: token) }
            }
        }
    }

    /// Ob odjavi.
    func clear() {
        ids = []; events = []; loaded = false; loadError = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    private func shraniCache() {
        if let d = try? JSONEncoder().encode(Array(ids).sorted()), let s = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: cacheKey)
        }
    }
}
