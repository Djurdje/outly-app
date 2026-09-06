//
//  BusinessTeamView.swift
//  Outly
//
//  Created by Luka Rakusa Djurdjevic on 11. 1. 26.
//

import SwiftUI

private struct TeamMember: Identifiable {
    let id = UUID()
    let name: String
    let email: String
    let role: String
    let badge: String
    let color: Color
}

struct BusinessTeamView: View {
    @State private var searchText = ""
    @State private var inviteUserId = ""
    @State private var selectedRole = "Manager"

    private let roles = ["Manager", "Scanner"]

    private let members: [TeamMember] = [
        .init(name: "Gorisek", email: "gorisek@gmail.com", role: "OWNER", badge: "G", color: .red),
        .init(name: "Klemen", email: "klemen@gmail.com", role: "Manager", badge: "K", color: .blue),
        .init(name: "Matic", email: "matic@gmail.com", role: "Manager", badge: "M", color: .pink),
        .init(name: "Lon", email: "lon@gmail.com", role: "Scanner", badge: "L", color: .green)
    ]

    private var filteredMembers: [TeamMember] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return members
        }
        return members.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cirkus Team")
                    .font(.title.bold())

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.6))
                    TextField("Search", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 12) {
                    ForEach(filteredMembers) { member in
                        TeamMemberRow(member: member)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                inviteSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.black.opacity(0.98))
        .preferredColorScheme(.dark)
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invite member")
                .font(.title3.bold())

            TextField("Enter user ID", text: $inviteUserId)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Role")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(roles, id: \.self) { role in
                    Button {
                        selectedRole = role
                    } label: {
                        Text(role)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedRole == role ? Color.blackColor : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(selectedRole == role ? 0 : 0.4), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            Button("Send invite") {}
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blackColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct TeamMemberRow: View {
    let member: TeamMember

    var body: some View {
        HStack(spacing: 12) {
            Text(member.badge)
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(member.color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.headline)
                Text(member.email)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Text(member.role)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.blackColor)
        }
        .padding(12)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
