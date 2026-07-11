import Foundation

/// Minimal transport seam so the services can be unit-tested with a fake. The live default is
/// `URLSession`. (Kept low-level; the higher-level `StatusFetching`/`CryptoFetching` sit on top.)
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

extension HTTPClient {
    /// Build the request (shared timeout + cache policy), perform it, enforce HTTP 200, and decode —
    /// mapping every failure onto a typed `FetchError`. Decode failures are logged under `#if DEBUG`.
    func fetchDecoded<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.cachePolicy = AppConfig.API.cachePolicy
        request.timeoutInterval = AppConfig.API.requestTimeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw FetchError.transport(error)
        }
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else { throw FetchError.http(-1) }
        guard http.statusCode == 200 else { throw FetchError.http(http.statusCode) }
        guard data.count <= AppConfig.API.maximumResponseBytes else {
            throw FetchError.responseTooLarge(
                bytes: data.count, maximum: AppConfig.API.maximumResponseBytes)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[WoCKit] decode \(T.self) failed: \(error)")
            #endif
            throw FetchError.decode
        }
    }
}
