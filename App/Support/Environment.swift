import Foundation

struct AppEnvironment: Equatable {
    let name: String
    let baseURL: URL?

    var backendBaseURL: URL? {
        baseURL
    }

    static func from(bundle: Bundle = .main) -> AppEnvironment {
        let dictionary = bundle.infoDictionary ?? [:]
        let name = (dictionary["AppEnvironmentName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBaseURL = (dictionary["BaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName = (name?.isEmpty == false ? name : nil) ?? "UNKNOWN"
        let parsedBaseURL = URL(string: rawBaseURL ?? "")

        return AppEnvironment(
            name: resolvedName,
            baseURL: parsedBaseURL,
        )
    }
}
