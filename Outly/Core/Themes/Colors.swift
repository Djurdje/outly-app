import SwiftUI

// Edino mesto za barve blagovne znamke. Vrednosti so iz Figme
// (datoteka XeVmPgY0LDGkNcQGBkNDbg): modra #4C76FF, ozadje #111111, kartica #242323.
// Prej je bila modra v kodi #5478FA (napaka), v Figmi pa #4C76FF.
extension Color {
    /// Glavna modra (#4C76FF) — gumbi, poudarki, aktivni zavihek.
    static let outlyBlue = Color(red: 76/255, green: 118/255, blue: 255/255)

    /// Ozadje zaslonov (#111111).
    static let outlyBackground = Color(red: 17/255, green: 17/255, blue: 17/255)

    /// Ozadje kartic/modalnih oken (#242323).
    static let outlyCard = Color(red: 36/255, green: 35/255, blue: 35/255)

    /// Sivo besedilo (#9D9D9D).
    static let outlyMuted = Color(red: 157/255, green: 157/255, blue: 157/255)

    /// Mornarski preliv kartice HitCard (Figma 237:1070), od leve proti desni: #000E3D, #19358E, #2E4799.
    /// Namerno temnejsi od outlyBlue; definiran samo tu, da HitCard ne nosi trdo kodiranih vrednosti.
    static let outlyHitStart = Color(red: 0/255, green: 14/255, blue: 61/255)
    static let outlyHitMid = Color(red: 25/255, green: 53/255, blue: 142/255)
    static let outlyHitEnd = Color(red: 46/255, green: 71/255, blue: 153/255)

    /// Staro ime, ki ga uporablja obstojeca koda. Kaze na isto modro.
    /// Ime je zavajajoce ("black"), zato v novi kodi uporabljaj .outlyBlue.
    static let blackColor = outlyBlue
}
