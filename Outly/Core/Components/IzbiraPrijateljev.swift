import SwiftUI
import UIKit

/// Cista logika izbire vec prijateljev (locena od pogleda zaradi testov). Uporabljata jo razdelitev VIP vstopnic po nakupu mize
/// (`VipRazdelitevBlok`) in povabila na guest listo (`GuestListPovabiSheet`).
enum IzbiraPrijateljev {
    /// Preklopi izbiro prijatelja. Vrstni red izbire se ohrani (VIP: prvi izbrani dobi prvo posiljano vstopnico);
    /// nov prijatelj se ob polni meji NE doda (seznam ostane nespremenjen). Odstranitev je vedno mogoca.
    static func preklopi(_ izbrani: [Int], id: Int, meja: Int) -> [Int] {
        if let i = izbrani.firstIndex(of: id) {
            var novi = izbrani
            novi.remove(at: i)
            return novi
        }
        guard izbrani.count < max(0, meja) else { return izbrani }
        return izbrani + [id]
    }

    /// Prijatelji brez izkljucenih id-jev (npr. ze povabljeni na guest listi); vrstni red ostane.
    static func razpolozljivi(_ prijatelji: [FriendUser], izkljuceni: Set<Int>) -> [FriendUser] {
        prijatelji.filter { !izkljuceni.contains($0.id) }
    }

    /// Izbira po osvezitvi seznama prijateljev: obdrzi samo se obstojece, brez podvojenih, najvec `meja`.
    static func ocisti(_ izbrani: [Int], razpolozljivi: [FriendUser], meja: Int) -> [Int] {
        let veljavni = Set(razpolozljivi.map(\.id))
        var videni = Set<Int>()
        var rezultat: [Int] = []
        for id in izbrani where veljavni.contains(id) && videni.insert(id).inserted {
            if rezultat.count >= max(0, meja) { break }
            rezultat.append(id)
        }
        return rezultat
    }

    /// Kljukica starosti se pokaze, ko je meja > 0 in je izbran vsaj en prijatelj.
    static func kazeStarost(izbranih: Int, starostnaMeja: Int) -> Bool {
        starostnaMeja > 0 && izbranih > 0
    }

    /// Gumb za posiljanje je aktiven: vsaj en izbran in (brez meje ali potrjena starost).
    static func lahkoPosljes(izbranih: Int, starostnaMeja: Int, starostPotrjena: Bool) -> Bool {
        izbranih > 0 && (starostnaMeja <= 0 || starostPotrjena)
    }
}

/// Seznam prijateljev z vecstransko izbiro (kljukice), stevcem »N of M selected« in kljukico starosti.
/// Ne nalaga podatkov in nima gumbov: klicatelj poda seznam in veze `izbrani` (id-ji v vrstnem redu izbire) in `starostPotrjena`.
/// Kljukica starosti velja za TRENUTNO izbiro: ob vsaki spremembi izbire se ponastavi (ne prenese se na drugo izbiro).
struct IzbiraPrijateljevView: View {
    let prijatelji: [FriendUser]
    @Binding var izbrani: [Int]
    /// Najvecje stevilo izbranih.
    let meja: Int
    /// Ti prijatelji se ne pokazejo (npr. ze povabljeni).
    var izkljuceni: Set<Int> = []
    /// > 0: pokaze kljukico »vsi izbrani so stari vsaj N«. 0 = brez kljukice.
    var starostnaMeja: Int = 0
    @Binding var starostPotrjena: Bool
    /// false: izbira zamrznjena (med posiljanjem).
    var omogocen: Bool = true

    private var seznam: [FriendUser] {
        IzbiraPrijateljev.razpolozljivi(prijatelji, izkljuceni: izkljuceni)
    }

    private var polna: Bool { izbrani.count >= meja }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(izbrani.count) of \(meja) selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            VStack(spacing: 8) {
                ForEach(seznam) { f in vrstica(f) }
            }
            .disabled(!omogocen)
            .opacity(omogocen ? 1 : 0.6)

            if IzbiraPrijateljev.kazeStarost(izbranih: izbrani.count, starostnaMeja: starostnaMeja) {
                StarostKljukica(starostnaMeja: starostnaMeja, potrjena: $starostPotrjena)
                    .disabled(!omogocen)
            }
        }
        // Kljukica starosti velja za eno izbiro: ob spremembi izbire se ponastavi.
        .onChange(of: izbrani) { _, _ in starostPotrjena = false }
    }

    private func vrstica(_ f: FriendUser) -> some View {
        let izbran = izbrani.contains(f.id)
        let zatemnjen = !izbran && polna
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            izbrani = IzbiraPrijateljev.preklopi(izbrani, id: f.id, meja: meja)
        } label: {
            HStack(spacing: 12) {
                OutlyAvatarView(avatarUrlString: f.avatarUrl, size: 40)
                Text(verbatim: f.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Image(systemName: izbran ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(izbran ? .white : .white.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(izbran ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(izbran ? Color.white.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .opacity(zatemnjen ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(zatemnjen)
        .accessibilityAddTraits(izbran ? .isSelected : [])
    }
}

/// Ena kljukica »vsi izbrani prijatelji so stari vsaj N«. Ni vnaprej oznacena; brez nje gumb za posiljanje ni aktiven.
struct StarostKljukica: View {
    let starostnaMeja: Int
    @Binding var potrjena: Bool

    var body: some View {
        Button { potrjena.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: potrjena ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(potrjena ? .white : .white.opacity(0.5))
                    .accessibilityHidden(true)
                Text("I confirm all selected friends are at least \(starostnaMeja) years old. They must show a valid photo ID at the door; if they are younger, the club will refuse entry.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(potrjena ? AccessibilityTraits([.isToggle, .isSelected]) : AccessibilityTraits.isToggle)
    }
}
