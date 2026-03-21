import Foundation
@testable import livlogios
import Testing

// Mirrors the decoding struct used in BackendService for 429 responses
private struct RateLimitResponse: Decodable {
    let details: RateLimitDetails?
    struct RateLimitDetails: Decodable {
        let retryAfter: Int?
        let limitType: String?
        enum CodingKeys: String, CodingKey {
            case retryAfter = "retry_after"
            case limitType = "limit_type"
        }
    }
}

struct AuthErrorTests {

    // MARK: - rateLimitExceeded error descriptions

    @Test func testDeviceLimitWithRetryAfter() {
        let error = AuthError.rateLimitExceeded(retryAfter: 60, limitType: "device_limit")
        #expect(error.errorDescription == "Too many sign-in attempts. Please wait 60 seconds")
    }

    @Test func testDeviceLimitWithoutRetryAfter() {
        let error = AuthError.rateLimitExceeded(retryAfter: nil, limitType: "device_limit")
        #expect(error.errorDescription == "Too many sign-in attempts. Please try again later")
    }

    @Test func testEmailCooldownWithRetryAfter() {
        let error = AuthError.rateLimitExceeded(retryAfter: 30, limitType: "email_cooldown")
        #expect(error.errorDescription == "Code already sent. Please wait 30 seconds")
    }

    @Test func testEmailCooldownWithoutRetryAfter() {
        let error = AuthError.rateLimitExceeded(retryAfter: nil, limitType: "email_cooldown")
        #expect(error.errorDescription == "Code already sent. Please try again later")
    }

    // "hourly_limit" intentionally falls into the generic "Code already sent" branch
    @Test func testHourlyLimitWithRetryAfter() {
        let error = AuthError.rateLimitExceeded(retryAfter: 3600, limitType: "hourly_limit")
        #expect(error.errorDescription == "Code already sent. Please wait 3600 seconds")
    }

    @Test func testNilLimitTypeWithRetryAfter() {
        let error = AuthError.rateLimitExceeded(retryAfter: 10, limitType: nil)
        #expect(error.errorDescription == "Code already sent. Please wait 10 seconds")
    }

    @Test func testNilLimitTypeWithoutRetryAfter() {
        let error = AuthError.rateLimitExceeded(retryAfter: nil, limitType: nil)
        #expect(error.errorDescription == "Code already sent. Please try again later")
    }

    // MARK: - RateLimitResponse decoding (simulates BackendService 429 parsing)

    @Test func testRateLimitResponseDecoding() throws {
        let json = """
        {
            "error": "RATE_LIMIT_EXCEEDED",
            "message": "Please wait before requesting another code",
            "details": {
                "retry_after": 25,
                "limit_type": "email_cooldown"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RateLimitResponse.self, from: data)
        #expect(decoded.details?.retryAfter == 25)
        #expect(decoded.details?.limitType == "email_cooldown")
    }

    @Test func testRateLimitResponseDecodingDeviceLimit() throws {
        let json = """
        {
            "error": "RATE_LIMIT_EXCEEDED",
            "message": "Please wait before requesting another code",
            "details": {
                "retry_after": 90,
                "limit_type": "device_limit"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RateLimitResponse.self, from: data)
        #expect(decoded.details?.retryAfter == 90)
        #expect(decoded.details?.limitType == "device_limit")
    }

    @Test func testRateLimitResponseDecodingWithoutDetails() throws {
        let json = """
        {
            "error": "RATE_LIMIT_EXCEEDED",
            "message": "Please wait"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RateLimitResponse.self, from: data)
        #expect(decoded.details == nil)
    }
}
