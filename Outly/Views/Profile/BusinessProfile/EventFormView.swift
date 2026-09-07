import SwiftUI
import PhotosUI

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
    @State private var ticketUrl = ""
    @State private var posterUrl = ""
    @State private var isPublished = true

    @State private var allGenres: [String] = []
    @State private var selectedGenres: Set<String> = []

    @State private var pickedPoster: PhotosPickerItem?
    @State private var isUploadingPoster = false

    @State private var isSaving = false
    @State private var message: String?
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { existing != nil }

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
                        TextField("free", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    TextField("External ticket link (optional)", text: $ticketUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Poster") {
                    HStack(spacing: 12) {
                        if let url = URL(string: posterUrl), !posterUrl.isEmpty {
                            AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.08) }
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        PhotosPicker(selection: $pickedPoster, matching: .images) {
                            HStack(spacing: 8) {
                                if isUploadingPoster { ProgressView() }
                                Text(posterUrl.isEmpty ? "Choose poster" : "Change poster")
                            }
                        }
                        .disabled(isUploadingPoster)
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
            .navigationTitle(isEditing ? "Edit event" : "New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") { Task { await save() } }
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
            .task { await loadGenres() }
            .onAppear(perform: prefill)
        }
        .preferredColorScheme(.dark)
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
        ticketUrl = e.ticketUrl ?? ""
        posterUrl = e.posterUrl
        isPublished = (e.status == "published")
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
        guard !cleanTitle.isEmpty else { message = "Enter a title."; return }
        guard let centsOpt = Self.cents(from: priceText) else {
            message = "Enter the price as a number, e.g. 12.50."
            return
        }
        if hasEnd, endAt < startAt { message = "End time must be after start time."; return }
        let url = ticketUrl.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty, !(url.hasPrefix("http://") || url.hasPrefix("https://")) {
            message = "Ticket link must start with http:// or https://."
            return
        }

        let draft = APIClient.EventDraft(
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

        isSaving = true
        defer { isSaving = false }
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
