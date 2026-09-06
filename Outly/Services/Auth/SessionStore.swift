import Foundation
import SwiftUI
import Combine

final class SessionStore: ObservableObject {
    @AppStorage("authToken") var authToken: String = ""

    var isLoggedIn: Bool {
        !authToken.isEmpty
    }

    func logout() {
        authToken = ""
    }
}
