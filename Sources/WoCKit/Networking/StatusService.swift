import Foundation

/// Fetches the player count / realm status. Injectable into `StatusStore` for testing; the live
/// default talks to `AppConfig.API.statusURL` via `URLSession`.
protocol StatusFetching: Sendable {
    func fetchStatus() async throws -> StatusResponse
}

struct StatusService: StatusFetching {
    let http: HTTPClient
    let endpoint: URL

    init(http: HTTPClient = URLSession.shared, endpoint: URL = AppConfig.API.statusURL) {
        self.http = http
        self.endpoint = endpoint
    }

    func fetchStatus() async throws -> StatusResponse {
        try await http.fetchDecoded(StatusResponse.self, from: endpoint)
    }
}
