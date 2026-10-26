import SwiftUI

// Cenik bara (migracija 014, Martin 14. 9. 2026).
// BarPricesView: kar vidi gost (sheet z zaslona dogodka).
// BarPricesEditorView: kar ureja klub (Club info -> Bar prices).

/// Postavke, zdruzene po kategoriji v vrstnem redu, kot jih je klub vnesel.
/// Postavke brez kategorije gredo v skupino "Other" na koncu.
private func skupine(_ items: [BarPriceItem]) -> [(naslov: String, postavke: [BarPriceItem])] {
    var vrstniRed: [String] = []
    var poSkupinah: [String: [BarPriceItem]] = [:]
    for p in items {
        let k = p.category ?? ""
        if poSkupinah[k] == nil { vrstniRed.append(k); poSkupinah[k] = [] }
        poSkupinah[k]!.append(p)
    }
    let zKategorijo: [(naslov: String, postavke: [BarPriceItem])] =
        vrstniRed.filter { !$0.isEmpty }.map { (naslov: $0, postavke: poSkupinah[$0]!) }
    // Brez kategorije: "Other" (ce klub sam uporablja "Other", se spoji v isto skupino).
    guard let brezKategorije = poSkupinah[""] else { return zKategorijo }
    if zKategorijo.isEmpty { return [(naslov: "", postavke: brezKategorije)] }
    if let i = zKategorijo.firstIndex(where: { $0.naslov.caseInsensitiveCompare("Other") == .orderedSame }) {
        var kopija = zKategorijo
        kopija[i].postavke += brezKategorije
        return kopija
    }
    return zKategorijo + [(naslov: String(localized: "Other"), postavke: brezKategorije)]
}

struct BarPricesView: View {
    let clubName: String
    let items: [BarPriceItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if items.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "wineglass")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.35))
                            Text("No bar prices yet")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("\(clubName) hasn't shared its bar prices in Outly yet.")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(skupine(items), id: \.naslov) { skupina in
                            VStack(alignment: .leading, spacing: 8) {
                                if !skupina.naslov.isEmpty {
                                    Text(skupina.naslov.uppercased())
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1.2)
                                        .foregroundStyle(.white.opacity(0.5))
                                        .padding(.horizontal, 4)
                                }
                                VStack(spacing: 0) {
                                    ForEach(Array(skupina.postavke.enumerated()), id: \.offset) { i, p in
                                        HStack {
                                            Text(p.name)
                                                .font(.system(size: 16))
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text(Denar.evri(p.priceCents))
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 13)
                                        if i < skupina.postavke.count - 1 {
                                            Divider().background(Color.white.opacity(0.08)).padding(.leading, 16)
                                        }
                                    }
                                }
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                        Text("Prices are set by the club and may change.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(Color.outlyBackground.ignoresSafeArea())
            .navigationTitle("Bar prices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Urejanje (klub)

/// Klub ureja cel seznam in ga shrani naenkrat (PATCH /business/clubs/me { bar_prices }).
/// Cena se vnasa v evrih z vejico ali piko, shrani se v centih (celo stevilo).
@MainActor
struct BarPricesEditorView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    /// Vrstica v urejanju: besedila, ne stevila — uporabnik tipka "4,50".
    struct Vrstica: Identifiable {
        let id = UUID()
        var name: String
        var price: String
        var category: String
    }

    @State private var vrstice: [Vrstica]
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let onSaved: ([BarPriceItem]) -> Void

    static let najvecPostavk = 60

    init(items: [BarPriceItem], onSaved: @escaping ([BarPriceItem]) -> Void) {
        _vrstice = State(initialValue: items.map {
            Vrstica(name: $0.name, price: Self.evriBesedilo($0.priceCents), category: $0.category ?? "")
        })
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Guests see this list on every event of your club. Category is optional (e.g. Beer, Cocktails).")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach($vrstice) { $v in
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Item (e.g. Beer 0.5 l)", text: $v.name)
                                .textInputAutocapitalization(.sentences)
                            TextField("0,00", text: $v.price)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 84)
                            Text("€").foregroundStyle(.white.opacity(0.6))
                        }
                        HStack(spacing: 8) {
                            TextField("Category (optional)", text: $v.category)
                                .textInputAutocapitalization(.words)
                                .font(.system(size: 14))
                            Spacer()
                            Button(role: .destructive) {
                                vrstice.removeAll { $0.id == v.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle().inset(by: -6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Delete item"))
                            .accessibilityValue(Text(verbatim: v.name))
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if vrstice.count < Self.najvecPostavk {
                    Button {
                        let zadnjaKategorija = vrstice.last?.category ?? ""
                        vrstice.append(Vrstica(name: "", price: "", category: zadnjaKategorija))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add item")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.outlyBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                OutlyPrimaryButton(title: "Save", isLoading: isSaving) {
                    Task { await save() }
                }
                .disabled(isSaving)
                .padding(.top, 6)

                Spacer(minLength: 30)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .outlyOzadje()
        .navigationTitle("Bar prices")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    // MARK: - Pretvorbe

    static func evriBesedilo(_ centi: Int) -> String {
        centi % 100 == 0 ? "\(centi / 100)" : String(format: "%d,%02d", centi / 100, centi % 100)
    }

    /// "4", "4,5", "4.50", " 4,50 € " -> 450. nil = neveljavno.
    static func centi(iz besedilo: String) -> Int? {
        var t = besedilo.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
        t = t.replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let d = Double(t), d >= 0, d <= 1000 else { return nil }
        return Int((d * 100).rounded())
    }

    private struct VnosNapaka: Error { let msg: String }

    private func sestavi() throws -> [BarPriceItem] {
        var items: [BarPriceItem] = []
        for (i, v) in vrstice.enumerated() {
            let name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cat = v.category.trimmingCharacters(in: .whitespacesAndNewlines)
            // Prazna vrstica (brez imena in cene) se preskoci.
            if name.isEmpty && v.price.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if name.isEmpty { throw VnosNapaka(msg: String(localized: "Item \(i + 1): name is missing.")) }
            if name.count > 60 { throw VnosNapaka(msg: String(localized: "Item \(i + 1): name is too long (max 60).")) }
            guard let c = Self.centi(iz: v.price) else { throw VnosNapaka(msg: String(localized: "Item \(i + 1) (\(name)): enter a price like 4,50.")) }
            items.append(BarPriceItem(name: name, priceCents: c, category: cat.isEmpty ? nil : String(cat.prefix(30))))
        }
        return items
    }

    private func save() async {
        errorMessage = nil
        let items: [BarPriceItem]
        do {
            items = try sestavi()
        } catch let e as VnosNapaka {
            errorMessage = e.msg
            return
        } catch {
            errorMessage = error.userMessage
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let club = try await APIClient.shared.updateMyBusinessClub(
                token: session.token,
                fields: ["bar_prices": items.map { $0.json }]
            )
            onSaved(club.barPrices)
            dismiss()
        } catch {
            errorMessage = error.userMessage
        }
    }
}
