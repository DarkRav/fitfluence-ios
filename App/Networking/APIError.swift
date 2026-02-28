import Foundation

enum APIError: Error, Equatable {
    case offline
    case timeout
    case cancelled
    case invalidURL
    case transportError(URLError)
    case httpError(statusCode: Int, bodySnippet: String?)
    case decodingError
    case unauthorized
    case forbidden
    case serverError(statusCode: Int, bodySnippet: String?)
    case unknown

    static func from(statusCode: Int, data: Data) -> APIError? {
        guard !(200 ... 299).contains(statusCode) else {
            return nil
        }

        let snippet = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 500 ... 599:
            return .serverError(statusCode: statusCode, bodySnippet: snippet)
        default:
            return .httpError(statusCode: statusCode, bodySnippet: snippet)
        }
    }

    static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .notConnectedToInternet:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .transportError(urlError)
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.offline, .offline),
             (.timeout, .timeout),
             (.cancelled, .cancelled),
             (.invalidURL, .invalidURL),
             (.decodingError, .decodingError),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.unknown, .unknown):
            return true
        case let (.transportError(left), .transportError(right)):
            return left.code == right.code
        case let (.httpError(lStatus, lSnippet), .httpError(rStatus, rSnippet)):
            return lStatus == rStatus && lSnippet == rSnippet
        case let (.serverError(lStatus, lSnippet), .serverError(rStatus, rSnippet)):
            return lStatus == rStatus && lSnippet == rSnippet
        default:
            return false
        }
    }
}
