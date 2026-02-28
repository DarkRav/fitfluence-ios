import Foundation

struct HTTPResponse {
    let data: Data
    let statusCode: Int
    let requestID: UUID
    let durationMs: Int
}

protocol HTTPClientProtocol {
    func send(_ request: APIRequest) async throws -> HTTPResponse
}

final class HTTPClient: HTTPClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: AuthTokenProvider

    init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenProvider: AuthTokenProvider = NoAuthTokenProvider()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func send(_ request: APIRequest) async throws -> HTTPResponse {
        let requestID = UUID()
        let start = Date()

        let urlRequest: URLRequest
        do {
            urlRequest = try await buildURLRequest(from: request)
        } catch {
            APILogger.log(
                requestID: requestID,
                method: request.method.rawValue,
                url: baseURL,
                statusCode: nil,
                durationMs: elapsedMs(since: start),
                error: .invalidURL
            )
            throw APIError.invalidURL
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                APILogger.log(
                    requestID: requestID,
                    method: request.method.rawValue,
                    url: urlRequest.url ?? baseURL,
                    statusCode: nil,
                    durationMs: elapsedMs(since: start),
                    error: .unknown
                )
                throw APIError.unknown
            }

            if let statusError = APIError.from(statusCode: httpResponse.statusCode, data: data) {
                APILogger.log(
                    requestID: requestID,
                    method: request.method.rawValue,
                    url: urlRequest.url ?? baseURL,
                    statusCode: httpResponse.statusCode,
                    durationMs: elapsedMs(since: start),
                    error: statusError
                )
                throw statusError
            }

            let duration = elapsedMs(since: start)
            APILogger.log(
                requestID: requestID,
                method: request.method.rawValue,
                url: urlRequest.url ?? baseURL,
                statusCode: httpResponse.statusCode,
                durationMs: duration,
                error: nil
            )

            return HTTPResponse(
                data: data,
                statusCode: httpResponse.statusCode,
                requestID: requestID,
                durationMs: duration
            )
        } catch let urlError as URLError {
            let apiError = APIError.from(urlError: urlError)
            APILogger.log(
                requestID: requestID,
                method: request.method.rawValue,
                url: urlRequest.url ?? baseURL,
                statusCode: nil,
                durationMs: elapsedMs(since: start),
                error: apiError
            )
            throw apiError
        } catch let apiError as APIError {
            throw apiError
        } catch {
            APILogger.log(
                requestID: requestID,
                method: request.method.rawValue,
                url: urlRequest.url ?? baseURL,
                statusCode: nil,
                durationMs: elapsedMs(since: start),
                error: .unknown
            )
            throw APIError.unknown
        }
    }

    private func buildURLRequest(from request: APIRequest) async throws -> URLRequest {
        let sanitizedPath = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(sanitizedPath),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeoutInterval ?? 20

        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if request.requiresAuthorization, let token = await tokenProvider.accessToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return urlRequest
    }

    private func elapsedMs(since startDate: Date) -> Int {
        Int(Date().timeIntervalSince(startDate) * 1000)
    }
}
