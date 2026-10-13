import SwiftUI
import os

/// Pomoc: iskanje po clankih, vodic "How to use Outly" (clanki po skupinah, vsak vodi na HelpArticleView)
/// in stik. Vsebina je v aplikaciji (brez backenda), opisuje dejanske zaslone in gumbe Outlyja:
/// imena v besedilu morajo ustrezati napisom v aplikaciji (Localizable.xcstrings).
/// Model in vsebina: HelpArticle.swift, HelpArticleContent.swift.
struct HelpCenterView: View {
    @State private var search = ""

    /// Clanki po skupinah, v vrstnem redu prve pojavitve v `HelpArticle.all` (iskanje filtrira cez vse skupine).
    /// `HelpArticle.all` je racunana lastnost z ~600 iskanji prevodov, zato jo body poklice samo enkrat.
    private func groups(of all: [HelpArticle]) -> [HelpGroup] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = q.isEmpty ? all : all.filter { $0.matches(q) }
        var result: [HelpGroup] = []
        for a in filtered {
            if let i = result.firstIndex(where: { $0.name == a.group }) {
                result[i].articles.append(a)
            } else {
                result.append(HelpGroup(name: a.group, articles: [a]))
            }
        }
        return result
    }

    var body: some View {
        let skupine = groups(of: HelpArticle.all)
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    Text("Help Center")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)

                    Text("Hi, how can we help?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .center)

                    SearchBar(text: $search, placeholder: "Search help")

                    Text(LocalizedStringKey(search.isEmpty ? "How to use Outly" : "Results"))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    if skupine.isEmpty {
                        Text("Nothing found. Try another word or contact us below.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.vertical, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(skupine) { g in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(g.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.gray)
                                        .padding(.leading, 4)

                                    VStack(spacing: 12) {
                                        ForEach(g.articles) { a in
                                            NavigationLink { HelpArticleView(article: a) } label: {
                                                HelpCard(topLine: a.topic, title: a.title)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HelpContactSection()
                        .padding(.top, 12)

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// »Still need help? / Contact us« — ena vrstica za oba zaslona (Help Center in clanek). Brez modre: modra je na
/// clanku samo na gumbu »Take me there« (ena poudarjena stvar na zaslon).
private struct HelpContactSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Still need help?")
                .font(.headline)
                .foregroundColor(.white)

            Link(destination: URL(string: "mailto:luka@outly.si?subject=Outly%20support")!) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                        .foregroundColor(.white.opacity(0.8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Contact us")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                        Text("luka@outly.si — we usually reply within a day.")
                            .font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundColor(.gray)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Skupina clankov v Help Centru (naslov skupine + clanki pod njim).
private struct HelpGroup: Identifiable {
    let name: String
    var articles: [HelpArticle]
    var id: String { name }
}

/// En clanek pomoci, od zgoraj: tema + naslov + povzetek, »Where to find it«, »Steps«, »Take me there«,
/// »Good to know«, »Was this article helpful?«, »Related articles« in stik. Razdelek se pokaze samo, ce ima vsebino.
/// Brez lastnega NavigationStack (potisnjen je v stack Profila, sicer bi se skril gumb nazaj).
struct HelpArticleView: View {
    let article: HelpArticle
    /// Sorodni clanki, razreseni enkrat ob nastanku (ne v body: `HelpArticle.all` je draga).
    private let related: [HelpArticle]

    @EnvironmentObject private var session: SessionStore
    /// nil = se ni glasoval; true = v pomoc; false = ni v pomoc. Zacne iz shranjenega glasu (HelpFeedback).
    @State private var vote: Bool?

    private let dnevnik = Logger(subsystem: "si.outly.app", category: "pomoc")

    init(article: HelpArticle) {
        self.article = article
        let all = HelpArticle.all
        self.related = article.related.compactMap { id in all.first { $0.id == id } }
        _vote = State(initialValue: HelpFeedback.vote(for: article.id))
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if !article.path.isEmpty {
                        pathSection
                    }

                    if !article.steps.isEmpty {
                        stepsSection
                    }

                    if let destination = article.destination {
                        // Ena poudarjena stvar na zaslonu: edini modri gumb.
                        NavigationLink { destination.view } label: {
                            OutlyPrimaryButtonLabel(title: "Take me there")
                        }
                        .buttonStyle(.plain)
                    }

                    if !article.notes.isEmpty {
                        notesSection
                    }

                    feedbackSection

                    if !related.isEmpty {
                        relatedSection
                    }

                    HelpContactSection()

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Razdelki

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.topic)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))

            Text(article.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(article.summary)
                .font(.body)
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    /// »Where to find it«: pot kot en Text (beli elementi, sivi chevroni), da se sam prelomi.
    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where to find it")
                .font(.headline)
                .foregroundColor(.white)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundColor(.gray)
                    .padding(.top, 2)

                pathText
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    private var pathText: Text {
        let razmik = Text(verbatim: "  ")
        let chevron = Text(Image(systemName: "chevron.right")).font(.caption2).foregroundColor(.gray)
        var result = Text(verbatim: "")
        for (i, element) in article.path.enumerated() {
            if i > 0 {
                result = result + razmik + chevron + razmik
            }
            let item = Text(verbatim: element).fontWeight(.semibold).foregroundColor(.white)
            result = result + item
        }
        return result
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Steps")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(article.steps.enumerated()), id: \.offset) { i, step in
                    HelpStepRow(number: i + 1, text: step, isLast: i == article.steps.count - 1)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Good to know")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(article.notes.enumerated()), id: \.offset) { i, note in
                    if i > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.gray)
                            .padding(.top, 1)
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Was this article helpful?")
                    .font(.headline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                voteButton(helpful: true)
                voteButton(helpful: false)
            }

            if vote != nil {
                Text("Thanks for your feedback.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func voteButton(helpful: Bool) -> some View {
        let izbran = vote == helpful
        let ikona = helpful ? "hand.thumbsup" : "hand.thumbsdown"
        return Button {
            glasuj(helpful)
        } label: {
            Image(systemName: izbran ? ikona + ".fill" : ikona)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(izbran ? Color.white : Color.white.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(izbran ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(helpful ? "Helpful" : "Not helpful")))
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Related articles")
                .font(.headline)
                .foregroundColor(.white)

            VStack(spacing: 12) {
                ForEach(related) { a in
                    NavigationLink { HelpArticleView(article: a) } label: {
                        HelpCard(topLine: a.topic, title: a.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Odziv

    /// Glas se shrani na napravi takoj; streznik ga dobi v ozadju. Napaka (tudi 404 starega backenda, brez povezave)
    /// uporabniku ne gre pred oci — zahvala ostane, napaka se samo zabelezi.
    private func glasuj(_ helpful: Bool) {
        guard vote != helpful else { return }
        vote = helpful
        HelpFeedback.save(helpful, for: article.id)

        let token = session.token
        guard !token.isEmpty else { return }
        let articleId = article.id
        let dnevnik = self.dnevnik
        Task {
            do {
                try await APIClient.shared.sendHelpFeedback(token: token, article: articleId, helpful: helpful)
            } catch {
                dnevnik.debug("Odziv na clanek ni bil poslan: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Vrstica koraka: krogec s stevilko in tanka navpicna crta do naslednjega koraka (zadnji je brez crte).
private struct HelpStepRow: View {
    let number: Int
    let text: String
    let isLast: Bool

    private let krog: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(width: krog, height: krog)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))

            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 3)
        }
        .padding(.bottom, isLast ? 0 : 16)
        .background(alignment: .topLeading) {
            // Crta od spodnjega roba krogca do vrha naslednjega (vrstica vkljucuje spodnji odmik 16).
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 2)
                    .padding(.top, krog + 4)
                    .padding(.leading, krog / 2 - 1)
                    .padding(.bottom, 4)
            }
        }
    }
}
