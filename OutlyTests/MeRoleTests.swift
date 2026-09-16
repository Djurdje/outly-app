import XCTest
import Foundation
@testable import Outly

/// `Me.isBusiness` / `canManageClub` / `canSeeTeam` glede na glavno vlogo (user/business/admin)
/// in `club_role` (owner/manager/doorman) -- vlogo odloca streznik, aplikacija samo kaze
/// drug obraz (CLAUDE.md pravilo #7).
final class MeRoleTests: XCTestCase {

    private func makeMe(role: String? = nil, clubId: Int? = nil, clubRole: String? = nil) throws -> Me {
        func strJSON(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        let roleField = role.map { ",\"role\": \"\($0)\"" } ?? ""
        let json = """
        {
            "id": 1,
            "email": "test@outly.si",
            "username": "tester"
            \(roleField),
            "club_id": \(clubId.map { "\($0)" } ?? "null"),
            "club_role": \(strJSON(clubRole))
        }
        """
        return try JSONDecoder().decode(Me.self, from: Data(json.utf8))
    }

    // MARK: - Navaden uporabnik

    func testPlainUserWithoutClubIsNotBusiness() throws {
        let me = try makeMe(role: "user", clubRole: nil)
        XCTAssertFalse(me.isBusiness)
        XCTAssertFalse(me.canManageClub)
        XCTAssertFalse(me.canSeeTeam)
    }

    func testUserWhoIsClubOwnerIsBusinessAndCanManage() throws {
        let me = try makeMe(role: "user", clubId: 5, clubRole: "owner")
        XCTAssertTrue(me.isBusiness)
        XCTAssertTrue(me.canManageClub)
        XCTAssertTrue(me.canSeeTeam)
        XCTAssertEqual(me.clubRoleLabel, "Owner")
    }

    func testUserWhoIsClubManagerCanManageAndSeeTeam() throws {
        let me = try makeMe(role: "user", clubId: 5, clubRole: "manager")
        XCTAssertTrue(me.isBusiness)
        XCTAssertTrue(me.canManageClub)
        XCTAssertTrue(me.canSeeTeam)
        XCTAssertEqual(me.clubRoleLabel, "Manager")
    }

    /// Vratar je "poslovni obraz" (je del ekipe), a NE sme urejati kluba ali ekipe.
    func testUserWhoIsDoormanCannotManageClubOrTeam() throws {
        let me = try makeMe(role: "user", clubId: 5, clubRole: "doorman")
        XCTAssertTrue(me.isBusiness)
        XCTAssertFalse(me.canManageClub)
        XCTAssertFalse(me.canSeeTeam)
        XCTAssertEqual(me.clubRoleLabel, "Door staff")
    }

    // MARK: - Poslovni racun (lastnik brez zapisanega club_role)

    /// Lastnik kluba ima role "business", tudi ce (se) nima club_role zapisa.
    func testBusinessRoleWithoutClubRoleCanManageButNotSeeTeam() throws {
        let me = try makeMe(role: "business", clubRole: nil)
        XCTAssertTrue(me.isBusiness)
        XCTAssertTrue(me.canManageClub)
        // canSeeTeam preverja izrecno "owner"/"manager" club_role, ne role == business.
        XCTAssertFalse(me.canSeeTeam)
        XCTAssertNil(me.clubRoleLabel)
    }

    // MARK: - Admin

    /// Admin brez kluba: role ni "business" in club_role je nil -> ni "poslovni obraz".
    func testAdminWithoutClubIsNotBusinessFace() throws {
        let me = try makeMe(role: "admin", clubRole: nil)
        XCTAssertFalse(me.isBusiness)
        XCTAssertFalse(me.canManageClub)
        XCTAssertFalse(me.canSeeTeam)
    }

    func testAdminWithClubOwnerRoleCanManage() throws {
        let me = try makeMe(role: "admin", clubId: 9, clubRole: "owner")
        XCTAssertTrue(me.isBusiness)
        XCTAssertTrue(me.canManageClub)
        XCTAssertTrue(me.canSeeTeam)
    }

    // MARK: - Privzete vrednosti / obrambno dekodiranje (migracija 003, 009, 013)

    func testDecodesWithOnlyRequiredFields() throws {
        let json = #"{"id": 1, "email": "a@b.si", "username": "u"}"#
        let me = try JSONDecoder().decode(Me.self, from: Data(json.utf8))
        XCTAssertEqual(me.role, "user")
        XCTAssertEqual(me.genres, [])
        XCTAssertEqual(me.pendingInvites, 0)
        XCTAssertNil(me.clubId)
        XCTAssertNil(me.clubRole)
        XCTAssertNil(me.avatarUrl)
        XCTAssertFalse(me.isOnboarded)
        XCTAssertNil(me.age)
    }

    func testIsOnboardedReflectsOnboardedAt() throws {
        let json = #"{"id": 1, "email": "a@b.si", "username": "u", "onboarded_at": "2026-01-01T00:00:00.000Z"}"#
        let me = try JSONDecoder().decode(Me.self, from: Data(json.utf8))
        XCTAssertTrue(me.isOnboarded)
    }

    /// Postgres DATE lahko pride kot cist "YYYY-MM-DD" ali kot ISO-cas -- obdrzi prvih 10 znakov.
    func testDateOfBirthKeepsOnlyDatePartFromISOTimestamp() throws {
        let json = #"{"id": 1, "email": "a@b.si", "username": "u", "date_of_birth": "2000-05-20T00:00:00.000Z"}"#
        let me = try JSONDecoder().decode(Me.self, from: Data(json.utf8))
        XCTAssertEqual(me.dateOfBirth, "2000-05-20")
    }

    func testPendingInvitesDecodesWhenPresent() throws {
        let json = #"{"id": 1, "email": "a@b.si", "username": "u", "pending_invites": 3}"#
        let me = try JSONDecoder().decode(Me.self, from: Data(json.utf8))
        XCTAssertEqual(me.pendingInvites, 3)
    }
}
