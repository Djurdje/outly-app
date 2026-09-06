import SwiftUI

struct PasswordSecurityView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {

                    // TITLE
                    Text("Password and security")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    // MARK: - Login
                    VStack(alignment: .leading, spacing: 12) {
                        OutlyInfoCardButton(
                            icon: "lock",
                            title: "Password",
                            value: "Change password",
                            description: "You can change your password at any time.",
                            actionTitle: "Edit"
                        ) {
                            // change password
                        }
                    }

                    // MARK: - Two-step verification
                    VStack(alignment: .leading, spacing: 12) {
                        OutlyInfoCardButton(
                            icon: "shield",
                            title: "Two-step verification",
                            value: "Two-step verification",
                            description: "This adds extra security through email and social account verification.",
                            actionTitle: "Turn on"
                        ) {
                            // enable 2FA
                        }
                    }

                    // MARK: - Other login options
                    VStack(alignment: .leading, spacing: 12) {
                        OutlyInfoCardButton(
                            icon: "apple.logo",
                            title: "Other login options",
                            value: "Apple",
                            description: "We will not use your social account for anything else without your permission.",
                            actionTitle: "Link"
                        ) {
                            // link apple
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarBackButtonHidden(false) // sistemski back
        }
        .preferredColorScheme(.dark)
    }
}
