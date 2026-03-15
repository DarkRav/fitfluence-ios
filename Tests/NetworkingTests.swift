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
            _ = try await client.send(APIRequest.get(
                path: "/v1/programs/published/search",
                requiresAuthorization: false,
            ))
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
            _ = try await client.send(APIRequest.get(
                path: "/v1/programs/published/search",
                requiresAuthorization: false,
            ))
            XCTFail("Expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStatusCode401MapsToUnauthorized() async {
        MockURLProtocol.requestHandler = { request in
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil,
            )!
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
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil,
            )!
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
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil,
            )!
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
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )!
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

    func testStatsSummaryDecodingSupportsWrappedPayloadAndLossyNumbers() throws {
        let json = """
        {
          "data": {
            "streakDays": "5",
            "workouts7d": "3",
            "totalWorkouts": "42",
            "totalMinutes7d": "155",
            "lastWorkoutAt": "2026-03-02T10:15:00Z"
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AthleteStatsSummaryResponse.self, from: json)

        XCTAssertEqual(decoded.streakDays, 5)
        XCTAssertEqual(decoded.workouts7d, 3)
        XCTAssertEqual(decoded.totalWorkouts, 42)
        XCTAssertEqual(decoded.totalMinutes7d, 155)
        XCTAssertEqual(decoded.lastWorkoutAt, "2026-03-02T10:15:00Z")
    }

    func testExerciseHistoryDecodingMapsAlternativeDateField() throws {
        let json = """
        {
          "records": [
            {
              "id": "entry-1",
              "workoutInstanceId": "workout-1",
              "completedAt": "2026-03-01T08:30:00Z",
              "weight": 80,
              "reps": 5,
              "volume": 400
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AthleteExerciseHistoryResponse.self, from: json)

        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries.first?.id, "entry-1")
        XCTAssertEqual(decoded.entries.first?.performedAt, "2026-03-01T08:30:00Z")
        XCTAssertEqual(decoded.entries.first?.volume, 400)
    }

    func testActiveEnrollmentProgress404MapsToEmptyProgress() async {
        MockURLProtocol.requestHandler = { request in
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil,
            )!
            return (response, Data("{}".utf8))
        }

        let apiClient = APIClient(httpClient: makeHTTPClient())
        let result = await apiClient.activeEnrollmentProgress()

        switch result {
        case let .success(progress):
            XCTAssertEqual(progress, .empty)
        case let .failure(error):
            XCTFail("Expected empty progress, got error: \(error)")
        }
    }

    func testActiveEnrollmentProgressEmptyListMapsToEmptyProgress() async {
        MockURLProtocol.requestHandler = { request in
            let response = try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )!
            return (response, Data("[]".utf8))
        }

        let apiClient = APIClient(httpClient: makeHTTPClient())
        let result = await apiClient.activeEnrollmentProgress()

        switch result {
        case let .success(progress):
            XCTAssertEqual(progress, .empty)
        case let .failure(error):
            XCTFail("Expected empty progress, got error: \(error)")
        }
    }

    func testAthleteWorkoutDetailsMappingPreservesExerciseDetails() {
        let media = ContentMedia(
            id: "media-1",
            type: .video,
            url: "/media/pull-up.mp4",
            mimeType: "video/mp4",
            tags: nil,
            createdAt: nil,
            ownerType: nil,
            ownerId: nil,
            ownerDisplayName: nil,
        )
        let response = AthleteWorkoutDetailsResponse(
            workout: AthleteWorkoutInstance(
                id: "workout-1",
                enrollmentId: nil,
                workoutTemplateId: nil,
                title: "Workout",
                status: .planned,
                source: .program,
                scheduledDate: nil,
                startedAt: nil,
                completedAt: nil,
                durationSeconds: nil,
                notes: nil,
                programId: nil,
            ),
            exercises: [
                AthleteExerciseExecution(
                    id: "exec-1",
                    workoutInstanceId: "workout-1",
                    exerciseTemplateId: nil,
                    workoutPlanId: nil,
                    exerciseId: "exercise-1",
                    orderIndex: 0,
                    notes: nil,
                    plannedSets: 3,
                    plannedRepsMin: 8,
                    plannedRepsMax: 10,
                    plannedTargetRpe: nil,
                    plannedRestSeconds: 90,
                    plannedNotes: nil,
                    progressionPolicyId: nil,
                    exercise: AthleteExerciseBrief(
                        id: "exercise-1",
                        code: "pull-up",
                        name: "Подтягивания",
                        description: "Держите корпус стабильно и тянитесь грудью к перекладине.",
                        isBodyweight: true,
                        media: [media],
                    ),
                    sets: nil,
                ),
            ],
        )

        let mapped = response.asWorkoutDetailsModel()

        XCTAssertEqual(mapped.exercises.first?.isBodyweight, true)
        XCTAssertEqual(mapped.exercises.first?.description, "Держите корпус стабильно и тянитесь грудью к перекладине.")
        XCTAssertEqual(mapped.exercises.first?.media?.first?.id, "media-1")
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
