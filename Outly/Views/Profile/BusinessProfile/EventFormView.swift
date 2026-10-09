import SwiftUI
import PhotosUI
import CoreLocation

/// Obrazec za nov dogodek (POST /events) ali urejanje (PATCH /events/:id).
/// Cena se vnese v evrih, poslje pa se v CENTIH kot celo stevilo (Decimal, ne Double).
@MainActor
struct EventFormView: View {
    let clubId: Int
    let existing: APIEvent?
    var onSaved: (APIEvent?) -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var startAt = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var hasEnd = false
    @State private var endAt = Date().addingTimeInterval(7 * 24 * 3600 + 5 * 3600)
    @State private var minAge = 18
    @State private var priceText = ""
    @State private var capacityText = ""
    @State private var ticketUrl = ""
    @State private var posterUrl = ""
    @State private var isPublished = true

    // Prizorisce (backend 037): obvezno, ce klub organizira dogodke brez lastnega prizorisca
    // (`isOrganizer`). Klub z Outlyja (venueClubId) ali prosto vpisana lokacija (ime, naslov, mesto).
    private enum NacinPrizorisca: Hashable { case outly, custom }
    @State private var isOrganizer = false
    @State private var nacinPrizorisca: NacinPrizorisca = .outly
    @State private var venueClubId: Int?
    @State private var venueClubName = ""
    @State private var venueName = ""
    @State private var venueAddress = ""
    @State private var venueCity = ""

    @State private var allGenres: [String] = []
    @State private var selectedGenres: Set<String> = []

    @State private var pickedPoster: PhotosPickerItem?
    @State private var isUploadingPoster = false

    // Posnetek koncanega dogodka (backend migracija 019): video NAMESTO plakata na strani
    // kluba. Streznik ga sprejme samo na koncanem dogodku, ki je med TREMI najbolj
    // popularnimi dogodki kluba — `existing.recapAllowed` je njegov odgovor na to vprasanje.
    @State private var recapVideoUrl = ""
    @State private var pickedRecap: PhotosPickerItem?
    @State private var isUploadingRecap = false

    @State private var isSaving = false
    @State private var message: String?
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { existing != nil }

    /// Obrazec se razlikuje od shranjenega dogodka. Razdelek VIP (kopija gostitelja, urejevalnik) dela na SHRANJENEM
    /// dogodku, zato je do shranjevanja onemogocen. Novega dogodka ni (razdelek je takrat samo namig).
    private var imaNeshranjeneSpremembe: Bool {
        guard let e = existing else { return false }
        func minute(_ a: Date, _ b: Date?) -> Bool { b == nil || abs(a.timeIntervalSince(b!)) >= 60 }
        if title != e.title || description != e.description || minAge != e.minAge { return true }
        if minute(startAt, e.startDate) { return true }
        if hasEnd != (e.endDate != nil) { return true }
        if hasEnd, let k = e.endDate, minute(endAt, k) { return true }
        if Set(selectedGenres) != Set(e.genres) { return true }
        if priceText != (e.ticketPriceCents.map { Self.euros(fromCents: $0) } ?? "") { return true }
        if capacityText != (e.capacity.map { String($0) } ?? "") { return true }
        if ticketUrl != (e.ticketUrl ?? "") || posterUrl != e.posterUrl { return true }
        if e.status != "cancelled", isPublished != (e.status == "published") { return true }
        if isOrganizer {
            let novoId: Int? = nacinPrizorisca == .outly ? venueClubId : nil
            if novoId != e.venueClubId { return true }
            if nacinPrizorisca == .custom, e.venueClubId == nil,
               venueName != e.venueName || venueAddress != e.venueAddress || venueCity != e.venueCity { return true }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("When") {
                    DatePicker("Starts", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle("Has end time", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ends", selection: $endAt, in: startAt..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if isOrganizer {
                    prizoriscaSection
                }

                Section("Who") {
                    Stepper("Minimum age: \(minAge)", value: $minAge, in: 0...99)
                    if allGenres.isEmpty {
                        Text("Loading genres...").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                            ForEach(allGenres, id: \.self) { g in
                                let on = selectedGenres.contains(g)
                                Button {
                                    if on { selectedGenres.remove(g) } else { selectedGenres.insert(g) }
                                } label: {
                                    Text(GenreNames.display(g))
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(on ? Color.outlyBlue : Color.white.opacity(0.08))
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Tickets") {
                    HStack {
                        Text("Price (EUR)")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    Text("Leave empty if tickets are not sold on Outly. 0 = free entry.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text("Capacity")
                        Spacer()
                        TextField("unlimited", text: $capacityText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    Text("Number of tickets available. Shows “N left” and “Sold out” to guests.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("External ticket link (optional)", text: $ticketUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                // VIP mize organizatorja (backend 039): vir razporeda miz za ta dogodek. Pri novem dogodku samo namig.
                if isOrganizer {
                    VipRazporedOddelek(clubId: clubId, eventId: existing?.id, neshranjeno: imaNeshranjeneSpremembe)
                }

                Section("Poster") {
                    HStack(spacing: 12) {
                        if let url = URL(string: posterUrl), !posterUrl.isEmpty {
                            OutlyAsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.08) }
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        PhotosPicker(selection: $pickedPoster, matching: .images) {
                            HStack(spacing: 8) {
                                if isUploadingPoster { ProgressView() }
                                Text(LocalizedStringKey(posterUrl.isEmpty ? "Choose poster" : "Change poster"))
                            }
                        }
                        .disabled(isUploadingPoster)
                    }
                }

                if let e = existing, e.hasEnded {
                    Section("Event video") {
                        if e.recapAllowed {
                            HStack(spacing: 12) {
                                if !recapVideoUrl.isEmpty {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.outlyBlue)
                                }
                                PhotosPicker(selection: $pickedRecap, matching: .videos) {
                                    HStack(spacing: 8) {
                                        if isUploadingRecap { ProgressView() }
                                        Text(LocalizedStringKey(recapVideoUrl.isEmpty ? "Upload video" : "Replace video"))
                                    }
                                }
                                .disabled(isUploadingRecap)
                            }
                            Text("Guests see this video instead of the poster on your club page, so they can see how it was. Up to 100 MB.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !recapVideoUrl.isEmpty {
                                Button("Remove video", role: .destructive) { Task { await shraniPosnetek("") } }
                            }
                        } else {
                            Text("Only your three most popular past events can have a video. This keeps your club page fast to open.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Visibility") {
                    Toggle("Published (visible to everyone)", isOn: $isPublished)
                    if existing?.status == "cancelled" {
                        Text("This event is cancelled.").foregroundStyle(.red)
                    }
                }

                if let message {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }

                if isEditing {
                    Section {
                        Button("Cancel or delete event", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(LocalizedStringKey(isEditing ? "Edit event" : "New event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(LocalizedStringKey(isSaving ? "Saving..." : "Save"))
                    }
                    .disabled(isSaving || isUploadingPoster || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Remove this event?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete event", role: .destructive) { Task { await deleteEvent() } }
                Button("Keep event", role: .cancel) {}
            } message: {
                Text("If tickets were already sold, the event will be cancelled instead of deleted so buyers keep proof of purchase.")
            }
            .onChange(of: pickedPoster) { _, item in
                if let item { Task { await uploadPoster(item) } }
            }
            .onChange(of: pickedRecap) { _, item in
                if let item { Task { await uploadRecap(item) } }
            }
            .task { await loadGenres() }
            .task { await loadOrganizer() }
            .onAppear(perform: prefill)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - prizorisce

    private var prizoriscaSection: some View {
        Section("Venue") {
            Picker("Venue", selection: $nacinPrizorisca) {
                Text("On Outly").tag(NacinPrizorisca.outly)
                Text("Custom").tag(NacinPrizorisca.custom)
            }
            .pickerStyle(.segmented)

            if nacinPrizorisca == .outly {
                NavigationLink {
                    VenueClubPickerView(excludeClubId: clubId) { club in
                        venueClubId = club.id
                        venueClubName = club.name
                    }
                } label: {
                    HStack {
                        Text("Club")
                        Spacer()
                        if venueClubId != nil {
                            Text(venueClubName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Choose a club").foregroundStyle(.secondary)
                        }
                    }
                }
                Text("The event shows on this club's page too, but only your team can scan tickets.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                TextField("Venue name", text: $venueName)
                TextField("Address", text: $venueAddress)
                TextField("City", text: $venueCity)
                Text("Address and city put the event on the map.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Ali klub organizira brez lastnega prizorisca (javni GET /clubs/:id). Tiho ob napaki:
    /// obrazec ostane brez razdelka, streznik pri organizatorju brez prizorisca vrne 400.
    private func loadOrganizer() async {
        guard let c = try? await APIClient.shared.fetchClub(id: clubId) else { return }
        isOrganizer = c.isOrganizer
    }

    /// Naslov prizorisca -> koordinate (kot pri klubu, CLGeocoder). Neuspeh ni usoden: dogodek se shrani
    /// brez zemljevida. Nespremenjen naslov obdrzi koordinate obstojecega dogodka.
    private func koordinatePrizorisca() async -> (Double, Double)? {
        let naslov = venueAddress.trimmingCharacters(in: .whitespaces)
        let mesto = venueCity.trimmingCharacters(in: .whitespaces)
        if let e = existing, e.venueClubId == nil,
           e.venueAddress == naslov, e.venueCity == mesto,
           let lat = e.venueLat, let lng = e.venueLng {
            return (lat, lng)
        }
        let poizvedba = [naslov, mesto].filter { !$0.isEmpty }.joined(separator: ", ")
        guard !poizvedba.isEmpty else { return nil }
        guard let loc = try? await CLGeocoder().geocodeAddressString(poizvedba).first?.location else { return nil }
        return (loc.coordinate.latitude, loc.coordinate.longitude)
    }

    // MARK: - podatki

    private func prefill() {
        guard let e = existing, title.isEmpty else { return }
        title = e.title
        description = e.description
        startAt = e.startDate ?? startAt
        if let end = e.endDate { hasEnd = true; endAt = end }
        minAge = e.minAge
        selectedGenres = Set(e.genres)
        if let c = e.ticketPriceCents { priceText = Self.euros(fromCents: c) }
        if let cap = e.capacity { capacityText = String(cap) }
        ticketUrl = e.ticketUrl ?? ""
        posterUrl = e.posterUrl
        recapVideoUrl = e.recapVideoUrl
        isPublished = (e.status == "published")
        if let vid = e.venueClubId {
            nacinPrizorisca = .outly
            venueClubId = vid
            venueClubName = e.imePrizorisca
        } else if e.imaPrizorisce {
            nacinPrizorisca = .custom
            venueName = e.venueName
            venueAddress = e.venueAddress
            venueCity = e.venueCity
        }
    }

    private func loadGenres() async {
        do { allGenres = try await APIClient.shared.fetchGenres() }
        catch { allGenres = [] }
    }

    /// "12,50" ali "12.50" -> 1250. Decimal, da 0.1 + 0.2 ne postane 0.30000000000000004.
    static func cents(from text: String) -> Int?? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return .some(nil) }   // prazno = brez cene (prikaze se "FREE")
        // Decimal(string:) sprejme "12.5abc" kot 12.5, zato obliko preverimo sami.
        guard t.range(of: #"^\d{1,6}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let d = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")), d >= 0 else { return nil }
        var scaled = d * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard let n = Int(exactly: NSDecimalNumber(decimal: rounded)) else { return nil }
        return .some(n)
    }

    static func euros(fromCents c: Int) -> String {
        String(format: "%d.%02d", c / 100, c % 100)
    }

    private func save() async {
        message = nil
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { message = String(localized: "Enter a title."); return }
        guard let centsOpt = Self.cents(from: priceText) else {
            message = String(localized: "Enter the price as a number, e.g. 12.50.")
            return
        }
        if hasEnd, endAt < startAt { message = String(localized: "End time must be after start time."); return }
        let url = ticketUrl.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty, !(url.hasPrefix("http://") || url.hasPrefix("https://")) {
            message = String(localized: "Ticket link must start with http:// or https://.")
            return
        }

        let capTrim = capacityText.trimmingCharacters(in: .whitespaces)
        var capacity: Int? = nil
        if !capTrim.isEmpty {
            guard let c = Int(capTrim), c >= 1, c <= 100000 else {
                message = String(localized: "Capacity must be a whole number between 1 and 100000.")
                return
            }
            capacity = c
        }

        // Organizator brez lastnega prizorisca: dogodek mora povedati, kje je (streznik sicer 400).
        let imePrizorisca = venueName.trimmingCharacters(in: .whitespaces)
        let mestoPrizorisca = venueCity.trimmingCharacters(in: .whitespaces)
        if isOrganizer {
            if nacinPrizorisca == .outly, venueClubId == nil {
                message = String(localized: "Choose the venue for this event.")
                return
            }
            if nacinPrizorisca == .custom, imePrizorisca.isEmpty || mestoPrizorisca.isEmpty {
                message = String(localized: "Enter the venue name and city.")
                return
            }
        }

        var draft = APIClient.EventDraft(
            title: cleanTitle,
            description: description,
            startAt: startAt,
            endAt: hasEnd ? endAt : nil,
            minAge: minAge,
            genres: allGenres.filter { selectedGenres.contains($0) },
            ticketPriceCents: centsOpt,
            ticketUrl: url,
            posterUrl: posterUrl,
            status: existing?.status == "cancelled" ? "cancelled" : (isPublished ? "published" : "draft")
        )
        draft.capacity = capacity

        isSaving = true
        defer { isSaving = false }
        if isOrganizer {
            draft.posljiPrizorisce = true
            if nacinPrizorisca == .outly {
                draft.venueClubId = venueClubId
            } else {
                draft.venueName = imePrizorisca
                draft.venueAddress = venueAddress.trimmingCharacters(in: .whitespaces)
                draft.venueCity = mestoPrizorisca
                if let (lat, lng) = await koordinatePrizorisca() {
                    draft.venueLat = lat
                    draft.venueLng = lng
                }
            }
        }
        do {
            let saved: APIEvent
            if let e = existing {
                saved = try await APIClient.shared.updateEvent(token: session.token, id: e.id, draft: draft)
            } else {
                saved = try await APIClient.shared.createEvent(token: session.token, clubId: clubId, draft: draft)
            }
            onSaved(saved)
            dismiss()
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            message = api.userMessage
        } catch {
            message = error.userMessage
        }
    }

    private func deleteEvent() async {
        guard let e = existing else { return }
        message = nil
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await APIClient.shared.deleteEvent(token: session.token, id: e.id)
            onSaved(nil)
            dismiss()
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            message = api.userMessage
        } catch {
            message = error.userMessage
        }
    }

    /// Posnetek se shrani TAKOJ (loceno od gumba Save), ker gre skozi svoje preverjanje
    /// na strezniku: dogodek mora biti koncan in med prvimi tremi. Tako uporabnik napako
    /// vidi zdaj in ne sele ob shranjevanju celega obrazca.
    private func shraniPosnetek(_ url: String) async {
        guard let e = existing else { return }
        message = nil
        do {
            let posodobljen = try await APIClient.shared.setRecapVideo(token: session.token, eventId: e.id, url: url)
            recapVideoUrl = posodobljen.recapVideoUrl
            onSaved(posodobljen)
        } catch let api as APIError {
            if case let .requestFailed(code, _) = api, code == 401 { session.logout(); return }
            message = api.userMessage
        } catch {
            message = error.userMessage
        }
    }

    private func uploadRecap(_ item: PhotosPickerItem) async {
        message = nil
        isUploadingRecap = true
        defer { isUploadingRecap = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            // Cloudinary (brezplacni paket) sprejme videe do 100 MB — isto kot video kluba.
            if data.count > 100 * 1024 * 1024 {
                message = String(localized: "The video is larger than 100 MB. Please pick a shorter one.")
                return
            }
            let sig = try await APIClient.shared.fetchCloudinarySignature(token: session.token)
            let url = try await APIClient.shared.uploadVideoToCloudinary(videoData: data, fileName: "event_recap.mp4", signature: sig)
            await shraniPosnetek(url)
        } catch {
            message = error.userMessage
        }
    }

    private func uploadPoster(_ item: PhotosPickerItem) async {
        message = nil
        isUploadingPoster = true
        defer { isUploadingPoster = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let sig = try await APIClient.shared.fetchCloudinarySignature(token: session.token)
            let url = try await APIClient.shared.uploadImageToCloudinary(imageData: data, fileName: "poster.jpg", signature: sig)
            posterUrl = url
        } catch {
            message = error.userMessage
        }
    }
}
