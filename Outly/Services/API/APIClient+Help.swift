import Foundation

// Odziv na clanke pomoci (outly-backend, nova pot, gradi jo backend-dev vzporedno z aplikacijo):
//   POST /help/feedback { article: "<id clanka>", helpful: Bool }  -> 204 (requireAuth)
// Star backend poti se nima (404), omrezje lahko manjka: klicatelj (HelpArticleView) napake NE pokaze
// uporabniku — zahvala ostane, napaka se samo tiho zabelezi. Odziv je zato "najboljse mozno".

extension APIClient {

    /// POST /help/feedback. `article` je `HelpArticle.id` (stabilen, v anglescini, ne prevedeno besedilo).
    func sendHelpFeedback(token: String, article: String, helpful: Bool) async throws {
        _ = try await send(path: "help/feedback", method: "POST", token: token,
                           json: ["article": article, "helpful": helpful])
    }
}
