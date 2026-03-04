import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequest {
    let path: String
    let method: HTTPMethod
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data?
    var requiresAuthorization: Bool = true
    var timeoutInterval: TimeInterval?
}

extension APIRequest {
    static func get(path: String, queryItems: [URLQueryItem] = [], requiresAuthorization: Bool = true) -> APIRequest {
        APIRequest(
            path: path,
            method: .get,
            queryItems: queryItems,
            body: nil,
            requiresAuthorization: requiresAuthorization,
            timeoutInterval: nil,
        )
    }
}
