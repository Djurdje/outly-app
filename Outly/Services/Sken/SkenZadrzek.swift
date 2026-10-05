import Foundation

// Po »Next« ostane gostova koda se nekaj trenutkov v kadru. Brez zadrzka bi jo skener takoj prebral znova in pokazal rdece
// »ALREADY SCANNED« za gosta, ki je pravkar vstopil. Zato isto kodo `trajanje` sekund po »Next« ignoriramo; druga koda gre takoj.

struct SkenZadrzek {
    static let trajanje: TimeInterval = 3

    private(set) var koda = ""
    private(set) var doCasa = Date.distantPast

    /// Klice se ob »Next« z zadnjo prebrano kodo.
    mutating func zadrzi(_ koda: String, zdaj: Date = Date()) {
        self.koda = koda
        doCasa = zdaj.addingTimeInterval(Self.trajanje)
    }

    /// true: to kodo zdaj spreglej.
    func ignoriraj(_ koda: String, zdaj: Date = Date()) -> Bool {
        !koda.isEmpty && koda == self.koda && zdaj < doCasa
    }

    mutating func pocisti() {
        koda = ""
        doCasa = .distantPast
    }
}
