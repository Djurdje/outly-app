# Kako spraviti iOS projekt na GitHub in ga prevesti brez Maca

## 1. Enkrat: objava repozitorija

Ta mapa (`outly app`) je git repozitorij brez oddaljenega. Najlažje:

1. Namesti **GitHub Desktop** (desktop.github.com), prijavi se kot `Djurdje`.
2. *File → Add local repository* → izberi mapo `outly app`.
3. *Publish repository* → ime `outly-ios`, **Keep this code private** obkljukano.

Od takrat naprej: vsak commit → *Push origin* v GitHub Desktopu.

## 2. Kaj se zgodi ob vsakem potisku

`.github/workflows/gradnja.yml` požene macOS runner, ki:

– prevede projekt (če pade, so napake v zavihku **Actions → zadnji zagon → Prevedi za simulator**),
– naredi nepodpisan `Outly-nepodpisan.ipa` (artefakt spodaj na strani zagona).

## 3. Zagon na iPhonu brez razvijalskega računa

1. Na Windows namesti **AltServer** (altstore.io) in iTunes/iCloud z Applove strani (ne iz Microsoft Store).
2. iPhone priklopi s kablom, v AltServerju *Install AltStore → tvoj iPhone*, prijava z Apple ID-jem.
3. Prenesi `Outly-nepodpisan.ipa` iz GitHub Actions na telefon (AirDrop ni na Windowsu — pošlji si po mailu ali prek iCloud Drive).
4. V AltStore na telefonu: *My Apps → + → izberi .ipa*.

Omejitve brezplačnega Apple ID-ja: aplikacija velja **7 dni** (AltStore jo osvežuje, ko je telefon v istem omrežju kot računalnik z AltServerjem), največ 3 aplikacije hkrati.

## 4. Za App Store / TestFlight

Potreben je razvijalski račun (99 USD/leto) in podpisni certifikat. To pride v workflow pozneje (fastlane match ali ročno naloženi certifikati kot GitHub secrets — ključev NE dajaj v repozitorij).
