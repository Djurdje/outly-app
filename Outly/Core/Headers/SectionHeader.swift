import SwiftUI

/// Naslov razdelka. Prej: zadnja crka/beseda modra; od 10. 9. cel naslov bel
/// (Martin: "odstranit modro barvo v teh naslovih"). razdeli() ostane za morebitno rabo.
struct SectionHeader: View {
    let title: String
    var size: CGFloat = 20

    var body: some View {
        Text(title)
            .foregroundColor(.white)
            .font(.system(size: size, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    /// Vrne (beli del, modri del). Presledki pred zadnjo besedo ostanejo v belem delu.
    static func razdeli(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return ("", "") }
        let besede = t.split(separator: " ", omittingEmptySubsequences: true)
        if besede.count <= 1 {
            return (String(t.dropLast()), String(t.suffix(1)))
        }
        let zadnja = String(besede.last!)
        let prvi = String(t.dropLast(zadnja.count))
        return (prvi, zadnja)
    }
}
