# Outly iOS — navodila za agente

SwiftUI aplikacija (iOS 17+), Xcode 16 format s **sinhronizirano mapo** (`objectVersion 77`): vse v `Outly/` se prevaja.
Odgovarjaj v slovenščini, kratko. Skupni možgani so v repozitoriju `outly-backend`: `docs/DECISIONS.md`, `docs/STATE.md`,
`docs/ARCHITECTURE.md` — preberi jih (ali zahtevaj vsebino), preden spreminjaš karkoli, kar se dotika API-ja, vlog ali plačil.

## Kako pride gradnja na telefon (ni Maca!)

- Veja `master` = izvor gradenj. Potisk sproži GitHub Actions `Gradnja iOS` (`.github/workflows/gradnja.yml`, macOS runner, ~3 min):
  prevede, arhivira, priloži `Outly-nepodpisan.ipa` in `Outly-simulator-app`. **Rdeč Actions = napake prevajalnika.** Ne vsiljuj različice Xcoda.
- »Dela« pomeni: zelen Actions **in** Martin preveril na napravi. Dokler tega ni, piši »preverjeno s parse + pregledom tipov, na napravi ne«.
- Nikoli ne potiskaj neposredno v `master` — veja + PR + zelen Actions + merge.
- Cilj: TestFlight (Apple Developer račun obstaja od 16. 9. 2026; ASC API ključ kot GitHub secrets vpiše Martin).

## Pred vsakim PR-jem (obvezno, ker ni Xcoda)

1. `swiftc -parse` na vsaki spremenjeni datoteki (Swift za Linux, npr. 6.1.2 z download.swift.org).
2. Neodvisen pregled tipov: subagent dobi podpise obstoječih tipov (`APIClient`, modeli, `SessionStore`) in nove datoteke; išče
   neujemanja imen, opcijskosti, manjkajoče `import`, napačne inicializatorje. Ta dva koraka sta doslej ujela vse napake.
3. Sporočilo commita: slovenščina, brez šumnikov, »Preverjeno: swiftc -parse, pregled tipov; na napravi NE«.

## Struktura

```
Outly/
  App/AuthGate, MainTabView (Home 0, Search 1, Map 2, Profile 3)
  Services/APIClient.swift + APIClient+Account/+Events/+Discover/+Business/+Creator/+Orders/+Team/+Invites
  Services/Auth/SupabaseAuth.swift   tanek REST odjemalec za GoTrue (NE supabase-swift)
  Services/SessionStore              zetona v Keychainu (na simulatorju UserDefaults), refreshMe()
  Core/Components/                   SettingsCards, Buttons, WalletTicketCard, QRCodeView ...
  Views/Home, Search, Map, Profile (UserProfile / BusinessProfile), EventDetailView, ClubDetailView, BuyTicketsView, BarPricesView, QRScannerView
  PrivacyInfo.xcprivacy
_staro/                              odlozena koda (NI v Outly/, se ne prevaja)
```

## Trda pravila

1. **Vsi klici na backend gredo skozi `APIClient.send()`**; napake prek `APIErrorMessages` / `userMessage`. Brez `URLSession` po zaslonih.
2. Nova polja v API modelih vedno z **privzeto vrednostjo** (star backend ne sme podreti dekodiranja); pg BIGINT pride kot niz — backend to rešuje, a preveri pri novih poljih.
3. Slike: **vedno** `Color.clear.overlay(img.resizable().scaledToFill()).clipped()` — `AsyncImage` + `scaledToFill()` brez okvirja raztegne zaslon.
4. Potisnjeni pogledi **brez lastnega `NavigationStack`** (skrije gumb nazaj). Vsaka kartica mora nekam voditi (`NavigationLink`).
5. `shuffled()`/naključje samo enkrat ob nalaganju, ne v računani lastnosti.
6. Zasloni rabijo spodnji odmik (~40) zaradi plavajoče spodnje vrstice.
7. Vloge (`user | business | admin`, v klubu `owner | manager | doorman`) odloča strežnik; aplikacija samo kaže drug obraz (`Me.isBusiness`, `canManageClub`).
8. Info.plist se generira: dovoljenja kot `INFOPLIST_KEY_…` v `project.pbxproj` (oba konfiga).
9. Zneski v centih, prikaz prek `Denar.evri`. Cena `nil` ≠ Free (Free samo pri 0).
10. Kode iz maila (Supabase OTP) sprejmi 6–10 števk.

## Oblikovanje

Figma `XeVmPgY0LDGkNcQGBkNDbg` (stran »App«) je merodajna za postavitev, ne 1:1. Temna tema, `Color.outlyBlue` (#4C76FF) samo na glavnem gumbu,
brez vijoličnih prelivov, brez emojijev kot ikon, SF Symbols, 8-pt mreža, ena poudarjena stvar na zaslon. Figma MCP ima dnevno omejitev —
ogled prek figma.com (`node-id` v URL). Kar Figma predvideva in je odločeno drugače (denarnica, vnos kartice, $), se ne gradi — glej DECISIONS.md.
