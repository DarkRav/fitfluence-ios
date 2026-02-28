@testable import FitfluenceApp
import XCTest

final class NetworkingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.error = nil
        super.tearDown()
    }

    func testURLErrorOfflineMapsToOffline() async {
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        let client = makeHTTPClient()

        do {
            _ = try await client.send(APIRequest.get(path: "/actuator/health", requiresAuthorization: false))
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testURLErrorTimeoutMapsToTimeout() async {
        MockURLProtocol.error = URLError(.timedOut)
        let client = makeHTTPClient()

        do {
            _ = try await client.send(APIRequest.get(path: "/actuator/health", requiresAuthorization: false))
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStatusCode401MapsToUnauthorized() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let client = makeHTTPClient()

        do {
            _ = try await client.send(APIRequest.get(path: "/v1/me"))
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStatusCode403MapsToForbidden() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let client = makeHTTPClient()

        do {
            _ = try await client.send(APIRequest.get(path: "/v1/me"))
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStatusCode500MapsToServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data("service unavailable".utf8))
        }

        let client = makeHTTPClient()

        do {
            _ = try await client.send(APIRequest.get(path: "/v1/me"))
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .serverError(statusCode: 503, bodySnippet: "service unavailable"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDecodingFailureMapsToDecodingError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"unexpected\": true}".utf8))
        }

        let apiClient = APIClient(httpClient: makeHTTPClient())
        let result = await apiClient.healthCheck()

        switch result {
        case .success:
            XCTFail("Expected decoding error")
        case let .failure(error):
            XCTAssertEqual(error, .decodingError)
        }
    }

    private func makeHTTPClient() -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        return HTTPClient(
            baseURL: URL(string: "https://example.com")!,
            session: session,
            tokenProvider: NoAuthTokenProvider(),
        )
    }
}
