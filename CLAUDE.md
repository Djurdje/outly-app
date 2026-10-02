# Outly iOS — navodila za agente

SwiftUI aplikacija (iOS 17+), Xcode 16 format s **sinhronizirano mapo** (`objectVersion 77`): vse v `Outly/` se prevaja.
Odgovarjaj v slovenščini, kratko. Skupni možgani so v repozitoriju `outly-backend`: `docs/DECISIONS.md`, `docs/STATE.md`,
`docs/ARCHITECTURE.md` — preberi jih (ali zahtevaj vsebino), preden spreminjaš karkoli, kar se dotika API-ja, vlog ali plačil.

## Kako pride gradnja na telefon (ni Maca!) — TestFlight od 16. 9. 2026

- Veja `master` = izvor gradenj. Vsak potisk v `master` sproži GitHub Actions `Gradnja iOS` (`.github/workflows/gradnja.yml`,
  runner `macos-26` = Xcode 26 / iOS 26 SDK, ~8–10 min): (1) prevod za simulator brez podpisa → artefakt `Outly-simulator-app`
  (appetize.io), (2) **podpisan arhiv in upload na TestFlight**: razvojni certifikat iz GitHub secrets `IOS_DEV_CERT_P12`
  (base64 .p12) + `IOS_DEV_CERT_PASSWORD` se uvozi v začasen keychain, profil in distribucijski podpis uredi Xcode prek App Store
  Connect API ključa (`APPLE_TEAM_ID`, `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`); nič se ne hrani v repu. Brez `.p12` je Xcode
  na vsakem runnerju ustvaril nov certifikat in zadel Applovo omejitev (od 20. 9. 2026, glej backend `docs/INCIDENTI.md`).
  Če certifikat poteče ali ga kdo prekliče, TestFlight korak pade — nov `.p12` v secrets. Številka gradnje = številka zagona workflowa.
- Na **pull request** teče prevod za simulator + testi (Debug) in vzporedno job `Release prevod (PR)` (iphoneos, Release, `-O`, brez podpisa;
  ujame napake prevajalnika, ki se pokažejo samo z optimizacijo, incident 2. 10. 2026). TestFlight se preskoči — rdeč PR se ne sme združiti.
  Release prevod je dogovor (rdeča lučka), ne tehnična zapora: rulesets na zasebnem brezplačnem repu ne delujejo, zato pred merge-om preveri, da je zelen.
- Bundle ID `si.outly.app`, aplikacija v App Store Connect »Outly - Nightlife« (ime »Outly« je zasedeno), Martinov Individual
  Apple Developer račun; pozneje App Transfer na NEXT DIMENSIONS. `DEVELOPMENT_TEAM` je v projektu prazen — poda ga CI.
- Testerji dobijo build prek TestFlighta (~5–15 min po zelenem Actions). **Vsak merge v master = nov build pri testerjih.**
  Zato v `master` samo, kar je preverjeno; polovične stvari ostanejo na veji.
- »Dela« pomeni: zelen Actions **in** Martin preveril na napravi. Dokler tega ni, piši »preverjeno s parse + pregledom tipov, na napravi ne«.
- Nikoli ne potiskaj neposredno v `master` — veja + PR + zelen Actions (prevod) + `type-checker` → **PR sam mergaj**
  (squash prek GitHub MCP orodja `merge_pull_request` (gh CLI v oblaku ni) in pobriši vejo; odločeno 16. 9. 2026, človeka vmes ni). Merge sproži TestFlight build – v PR opis napiši,
  kaj naj Martin preveri na telefonu. (GitHub zaščite na tem zasebnem repu ne uveljavlja tehnično — to je dogovor, ne varovalo.)
- **Oznaka `odobril-martin`** (workflow `Zascita`, od 1. 10. 2026): PR, ki spremeni `.github/workflows/**`, `CLAUDE.md`,
  `.claude/**`, `Outly.xcodeproj/project.pbxproj` ali `Outly/PrivacyInfo.xcprivacy`, je rdeč brez te oznake. Oznako doda
  **Martin**; agent si je ne sme dodati sam. Ker GitHub tu merge-a ne ustavi, pred vsakim merge-om preveri **oba** checka
  (`Gradnja iOS` in `Zascita`): rdeč `Zascita` = ne mergaj, povej Martinu in počakaj.
- Ne spreminjaj `runs-on: macos-26`, `MARKETING_VERSION` ali podpisovanja brez Martina. Apple od aprila 2026 sprejema samo iOS 26 SDK.

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
3. Slike: **vedno** `Color.clear.overlay(img.resizable().scaledToFill()).clipped()` — slika + `scaledToFill()` brez okvirja raztegne zaslon.
   Nalaganje slik **samo prek `OutlyAsyncImage`** (isti klici kot `AsyncImage`), nikoli `AsyncImage` — ta dekodira plakat v polni
   ločljivosti na glavni niti ob vsakem pojavu in zatika drsenje (outly-app #33).
4. Potisnjeni pogledi **brez lastnega `NavigationStack`** (skrije gumb nazaj). Vsaka kartica mora nekam voditi (`NavigationLink`).
5. `shuffled()`/naključje samo enkrat ob nalaganju, ne v računani lastnosti.
   Vrednosti, ki se spreminjajo vsak frame (odmik drsenja, okvirji iz GeometryReaderja), ne v `@State` velikega pogleda — vsak frame
   bi znova izračunal cel zaslon. Prehod Home → Search/Profile: raste živa vsebina (samo skala, brez animirane prosojnosti); posnetki zaslona so
   videz pokvarili (#34–#38) — glej backend `docs/STATE.md`, pasti 29. 9. Animacij ne spreminjaj brez Martinovega posnetka zaslona.
6. Zasloni rabijo spodnji odmik (~40) zaradi plavajoče spodnje vrstice.
7. Vloge (`user | business | admin`, v klubu `owner | manager | doorman`) odloča strežnik; aplikacija samo kaže drug obraz (`Me.isBusiness`, `canManageClub`).
8. Info.plist se generira: dovoljenja kot `INFOPLIST_KEY_…` v `project.pbxproj` (oba konfiga).
9. Zneski v centih, prikaz prek `Denar.evri`. Cena `nil` ≠ Free (Free samo pri 0).
10. Kode iz maila (Supabase OTP) sprejmi 6–10 števk.

## Oblikovanje

Figma `XeVmPgY0LDGkNcQGBkNDbg` (stran »App«) je merodajna za postavitev, ne 1:1. Temna tema, `Color.outlyBlue` (#4C76FF) samo na glavnem gumbu,
brez vijoličnih prelivov, brez emojijev kot ikon, SF Symbols, 8-pt mreža, ena poudarjena stvar na zaslon. Figma MCP ima dnevno omejitev —
ogled prek figma.com (`node-id` v URL). Kar Figma predvideva in je odločeno drugače (denarnica, vnos kartice, $), se ne gradi — glej DECISIONS.md.
