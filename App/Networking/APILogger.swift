import Foundation

enum APILogger {
    static func log(
        requestID: UUID,
        method: String,
        url: URL,
        statusCode: Int?,
        durationMs: Int,
        error: APIError?,
    ) {
        #if DEBUG
        let statusPart = statusCode.map(String.init) ?? "-"
        let errorPart = error.map { " error=\($0)" } ?? ""
        FFLog
            .info(
                "[API] id=\(requestID.uuidString) method=\(method) url=\(url.absoluteString) status=\(statusPart) durationMs=\(durationMs)\(errorPart)",
            )
        #endif
    }
}
