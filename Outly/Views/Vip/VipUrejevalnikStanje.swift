import Foundation

/// Predmet na tlorisu v urejevalniku: orientacijski element (bar, oder ...) ali miza (`tip == "table"`).
/// Koordinate so v celicah mreze (kot na strezniku); `id` je lokalni kljuc, `streznikId` ima samo ze shranjena miza.
struct VipUrPredmet: Identifiable, Equatable {
    let id: UUID
    var tip: String
    var streznikId: Int?
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    /// Element: neobvezen napis (najvec 30 znakov). Miza: oznaka (1-20 znakov, unikatna).
    var oznaka: String
    /// Samo miza: round | rect
    var oblika: String
    /// Samo miza: 1...20
    var sedezi: Int
    /// Samo miza: cena v evrih kot besedilo ("120" ali "120.50"); v centih se pretvori ob shranjevanju.
    var cena: String

    var jeMiza: Bool { tip == VipUrStanje.tipMize }
}

/// Rezultat preverjanja pred shranjevanjem.
enum VipUrPreverjeno {
    case ok(plan: [String: Any], mize: [[String: Any]])
    case napaka(String)
}

/// Stanje urejevalnika tlorisa (vrednostni tip; urejevalnik ga drzi v @State, spremembe so primerljive z izhodiscem).
struct VipUrStanje: Equatable {
    static let tipMize = "table"
    /// Tipi elementov, ki jih strezniki sprejme (isti seznam kot backend TIPI_ELEMENTOV).
    static let tipiElementov = ["bar", "stage", "dj", "dancefloor", "entrance", "wc", "label", "wall"]
    static let mrezaMin = 8
    static let mrezaMax = 40
    static let najvecElementov = 80
    static let najvecMiz = 60
    static let najvecCenaCentov = 10_000_000
    /// Privzeta velikost ob dodajanju (w, h) v celicah.
    static func privzetaVelikost(tip: String) -> (w: Int, h: Int) {
        switch tip {
        case "bar": return (6, 2)
        case "stage": return (8, 3)
        case "dj": return (3, 2)
        case "dancefloor": return (8, 6)
        case "entrance": return (4, 1)
        case "wc": return (3, 2)
        case "label": return (6, 1)
        case "wall": return (8, 1)
        default: return (2, 2)
        }
    }

    var sirina = 24
    var visina = 16
    var predmeti: [VipUrPredmet] = []

    init() {}

    /// Iz odgovora strezniki. Brez tlorisa: privzeta mreza 24 x 16 in nic predmetov.
    init(layout: VipLayout) {
        if let plan = layout.plan {
            sirina = min(Self.mrezaMax, max(Self.mrezaMin, plan.width))
            visina = min(Self.mrezaMax, max(Self.mrezaMin, plan.height))
            for e in plan.elements {
                predmeti.append(VipUrPredmet(id: UUID(), tip: e.type, streznikId: nil, x: e.x, y: e.y, w: e.w, h: e.h,
                                             oznaka: e.label, oblika: "round", sedezi: 4, cena: ""))
            }
        }
        for m in layout.tables {
            predmeti.append(VipUrPredmet(id: UUID(), tip: Self.tipMize, streznikId: m.id, x: m.x, y: m.y, w: m.w, h: m.h,
                                         oznaka: m.label, oblika: m.shape == "rect" ? "rect" : "round",
                                         sedezi: min(20, max(1, m.seats)), cena: Self.evri(centov: m.priceCents)))
        }
        omeji()
    }

    var steviloMiz: Int { predmeti.filter { $0.jeMiza }.count }
    var steviloElementov: Int { predmeti.count - steviloMiz }

    static func evri(centov: Int) -> String {
        if centov % 100 == 0 { return String(centov / 100) }
        return String(format: "%d.%02d", centov / 100, centov % 100)
    }

    // MARK: - Urejanje

    /// Vsak predmet ostane v mrezi: velikost 1...mreza, polozaj znotraj.
    mutating func omeji() {
        for i in predmeti.indices {
            let w = min(max(predmeti[i].w, 1), sirina)
            let h = min(max(predmeti[i].h, 1), visina)
            predmeti[i].w = w
            predmeti[i].h = h
            predmeti[i].x = min(max(predmeti[i].x, 0), sirina - w)
            predmeti[i].y = min(max(predmeti[i].y, 0), visina - h)
        }
    }

    private static func prekrivanje(_ a: VipUrPredmet, x: Int, y: Int, w: Int, h: Int) -> Bool {
        a.x < x + w && x < a.x + a.w && a.y < y + h && y < a.y + a.h
    }

    /// Prvo prosto mesto za nov predmet (sicer levi zgornji kot).
    private func prostoMesto(w: Int, h: Int) -> (x: Int, y: Int) {
        guard w <= sirina, h <= visina else { return (0, 0) }
        for y in 0...(visina - h) {
            for x in 0...(sirina - w) where !predmeti.contains(where: { Self.prekrivanje($0, x: x, y: y, w: w, h: h) }) {
                return (x, y)
            }
        }
        return (0, 0)
    }

    /// Naslednja prosta oznaka mize (T1, T2 ...; velikost crk se ne razlikuje, kot na strezniku).
    private func naslednjaOznaka() -> String {
        let zasedene = Set(predmeti.filter { $0.jeMiza }.map { $0.oznaka.lowercased() })
        var n = 1
        while zasedene.contains("t\(n)") { n += 1 }
        return "T\(n)"
    }

    /// Doda predmet in vrne njegov kljuc; nil, ce je dosezena omejitev (60 miz, 80 elementov).
    mutating func dodaj(tip: String) -> UUID? {
        let jeMiza = tip == Self.tipMize
        if jeMiza, steviloMiz >= Self.najvecMiz { return nil }
        if !jeMiza, steviloElementov >= Self.najvecElementov { return nil }
        let velikost = Self.privzetaVelikost(tip: tip)
        let w = min(velikost.w, sirina)
        let h = min(velikost.h, visina)
        let mesto = prostoMesto(w: w, h: h)
        let p = VipUrPredmet(id: UUID(), tip: tip, streznikId: nil, x: mesto.x, y: mesto.y, w: w, h: h,
                             oznaka: jeMiza ? naslednjaOznaka() : "", oblika: "round", sedezi: 4, cena: jeMiza ? "0" : "")
        predmeti.append(p)
        return p.id
    }

    mutating func odstrani(id: UUID) {
        predmeti.removeAll { $0.id == id }
    }

    /// Premik za cele celice; predmet ostane v mrezi.
    mutating func premakni(id: UUID, dx: Int, dy: Int) {
        guard let i = predmeti.firstIndex(where: { $0.id == id }) else { return }
        predmeti[i].x = min(max(predmeti[i].x + dx, 0), sirina - predmeti[i].w)
        predmeti[i].y = min(max(predmeti[i].y + dy, 0), visina - predmeti[i].h)
    }

    // MARK: - Preverjanje in telo zahteve

    /// Isto preverjanje kot strezniki (PUT /business/vip): ob napaki prijazno sporocilo, sicer telo zahteve.
    /// Elementi gredo pred mizami; cena v CELIH CENTIH (Decimal prek `EventFormView.cents`, nikoli Double).
    func preveri() -> VipUrPreverjeno {
        if steviloMiz > Self.najvecMiz {
            return .napaka(String(localized: "A layout can have at most 60 tables."))
        }
        if steviloElementov > Self.najvecElementov {
            return .napaka(String(localized: "A layout can have at most 80 other items."))
        }
        var elementi: [[String: Any]] = []
        var mize: [[String: Any]] = []
        var oznake = Set<String>()
        for p in predmeti {
            if p.jeMiza {
                let oznaka = p.oznaka.trimmingCharacters(in: .whitespacesAndNewlines)
                if oznaka.isEmpty || oznaka.count > 20 {
                    return .napaka(String(localized: "Every table needs a label of 1 to 20 characters."))
                }
                if !oznake.insert(oznaka.lowercased()).inserted {
                    return .napaka(String(localized: "Table labels must be unique."))
                }
                guard let a = EventFormView.cents(from: p.cena), let centov = a, centov <= Self.najvecCenaCentov else {
                    return .napaka(String(localized: "Enter the table price as a number, e.g. 120 or 120.50."))
                }
                var miza: [String: Any] = [
                    "label": oznaka, "x": p.x, "y": p.y, "w": p.w, "h": p.h,
                    "shape": p.oblika == "rect" ? "rect" : "round",
                    "seats": min(20, max(1, p.sedezi)), "price_cents": centov
                ]
                if let id = p.streznikId { miza["id"] = id }
                mize.append(miza)
            } else {
                let napis = p.oznaka.trimmingCharacters(in: .whitespacesAndNewlines)
                if napis.count > 30 {
                    return .napaka(String(localized: "A label can have at most 30 characters."))
                }
                elementi.append(["type": p.tip, "x": p.x, "y": p.y, "w": p.w, "h": p.h, "label": napis])
            }
        }
        let plan: [String: Any] = ["width": sirina, "height": visina, "elements": elementi]
        return .ok(plan: plan, mize: mize)
    }
}
