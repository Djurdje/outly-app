import SwiftUI
import AVKit

/// Predvajalnika za video kluba (migracija 015) in za posnetek koncanega dogodka (019).
///
/// `OutlyLoopingVideo` se zazene sam (tiho, v zanki) — za EN video na zaslonu (stran kluba).
/// `OutlyRecapVideo` pokaze plakat z gumbom za predvajanje in AVPlayer ustvari **sele ob dotiku**.
/// To je razlog, da so posnetki na strani kluba omejeni na tri in se ne nalagajo vnaprej:
/// trije hkratni AVPlayerji na mobilnih podatkih so pol minute cakanja in prazna baterija.

// MARK: - Samodejni tihi video v zanki (en na zaslon)

struct OutlyLoopingVideo: View {
    let url: URL
    /// Zacne predvajati takoj, ko se pojavi. false = caka na `play`.
    var autoplay: Bool = true

    @State private var player: AVPlayer?
    @State private var muted = true
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true) // brez sistemskih kontrol; predvaja se samo
            } else {
                Rectangle().fill(Color.white.opacity(0.06))
            }

            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.5)))
                .padding(10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            muted.toggle()
            player?.isMuted = muted
        }
        .onAppear { zazeni() }
        .onDisappear { ustavi() }
    }

    private func zazeni() {
        if player == nil {
            let p = AVPlayer(url: url)
            p.isMuted = true
            p.actionAtItemEnd = .none
            player = p
        }
        if endObserver == nil, let p = player {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main
            ) { [weak p] _ in
                p?.seek(to: .zero)
                p?.play()
            }
        }
        if autoplay { player?.play() }
    }

    private func ustavi() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}

// MARK: - Posnetek koncanega dogodka: plakat + gumb, video sele ob dotiku

/// Posnetek "kako je bilo" na koncanem dogodku. Dokler uporabnik ne pritisne gumba,
/// je to navadna slika — noben video se ne prenasa.
struct OutlyRecapVideo: View {
    let url: URL
    /// Plakat dogodka kot slicica pred predvajanjem; prazno = temna ploskev.
    var posterUrl: String = ""
    /// Velikost gumba za predvajanje (kartice na strani kluba so manjse od plakata dogodka).
    var playSize: CGFloat = 54

    @State private var predvajam = false

    var body: some View {
        ZStack {
            if predvajam {
                OutlyLoopingVideo(url: url)
            } else {
                plakat
                Color.black.opacity(0.35)
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: playSize))
                        .foregroundStyle(.white, Color.black.opacity(0.35))
                    Text("See how it was")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !predvajam { predvajam = true } }
        .accessibilityLabel(Text("See how it was"))
    }

    @ViewBuilder
    private var plakat: some View {
        if !posterUrl.isEmpty, let u = URL(string: posterUrl) {
            // Past 12: scaledToFill brez okvirja raztegne zaslon.
            OutlyAsyncImage(url: u) { img in
                Color.clear.overlay(img.resizable().scaledToFill()).clipped()
            } placeholder: {
                Rectangle().fill(Color.white.opacity(0.08))
            }
        } else {
            Rectangle().fill(Color.white.opacity(0.08))
        }
    }
}
