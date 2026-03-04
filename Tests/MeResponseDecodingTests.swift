@testable import FitfluenceApp
import XCTest

final class MeResponseDecodingTests: XCTestCase {
    func testDecodesOpenAPIShape() throws {
        let json = """
        {
          "identity": {
            "sub": "user-sub-1",
            "email": "athlete@example.com",
            "avatarMediaId": "9e2f8f8d-6dad-4970-b03b-fcb08dc7c2f8"
          },
          "roles": ["ATHLETE"],
          "profiles": {
            "athleteProfile": {
              "exists": true,
              "data": {
                "userId": "1d2e3f4a-5b6c-4d7e-8f90-1234567890ab"
              }
            },
            "influencerProfile": {
              "exists": false,
              "data": null
            }
          },
          "onboarding": {
            "requiresAthleteProfile": false,
            "requiresInfluencerProfile": true
          }
        }
        """

        let me = try JSONDecoder().decode(MeResponse.self, from: Data(json.utf8))

        XCTAssertEqual(me.subject, "user-sub-1")
        XCTAssertEqual(me.email, "athlete@example.com")
        XCTAssertEqual(me.roles, ["ATHLETE"])
        XCTAssertEqual(me.athleteProfile?.id, "1d2e3f4a-5b6c-4d7e-8f90-1234567890ab")
        XCTAssertNil(me.influencerProfile)
        XCTAssertFalse(me.requiresAthleteProfile)
        XCTAssertTrue(me.requiresInfluencerProfile)
    }

    func testDecodesLegacyAndLooseShape() throws {
        let json = """
        {
          "sub": "legacy-sub",
          "email": "legacy@example.com",
          "roles": "ROLE_ATHLETE",
          "requiresAthleteProfile": "false",
          "requiresInfluencerProfile": 0,
          "athleteProfile": {
            "userId": "11111111-2222-3333-4444-555555555555"
          }
        }
        """

        let me = try JSONDecoder().decode(MeResponse.self, from: Data(json.utf8))

        XCTAssertEqual(me.subject, "legacy-sub")
        XCTAssertEqual(me.roles, ["ROLE_ATHLETE"])
        XCTAssertEqual(me.athleteProfile?.id, "11111111-2222-3333-4444-555555555555")
        XCTAssertFalse(me.requiresAthleteProfile)
        XCTAssertFalse(me.requiresInfluencerProfile)
    }
}
