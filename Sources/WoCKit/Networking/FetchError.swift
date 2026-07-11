import Foundation

/// A typed fetch failure, split so transport blips, HTTP statuses, response bounds, and schema breaks are
/// distinguishable (the old code threw `URLError(.badServerResponse)` for non-200 and let decode
/// errors fall through untyped). Decode failures are logged under `#if DEBUG` at the throw site.
enum FetchError: Error, Sendable {
    case transport(URLError)
    case http(Int)
    case responseTooLarge(bytes: Int, maximum: Int)
    case decode
}

extension FetchError {
    /// Realm-oriented classification used by the UI and outage alert policy. This deliberately
    /// separates problems on this Mac from evidence that the remote realm may be unavailable.
    var statusFailureKind: StatusFailureKind {
        switch self {
        case .transport(let error):
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .localNetwork
            case .timedOut:
                return .timedOut
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .serverUnreachable
            default:
                return .unknown
            }
        case .http(let status):
            return (500...599).contains(status) ? .serverError : .invalidResponse
        case .responseTooLarge, .decode:
            return .invalidResponse
        }
    }

    /// User-facing message. The strings are byte-identical to what the app showed before for each
    /// scenario (transport → the URLError mapping; non-200 → "Connection error"; invalid body →
    /// "Couldn't load status"), so this typing introduces no visible change.
    var friendlyMessage: String {
        switch self {
        case .transport(let e):
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return String(localized: "error.noInternet", defaultValue: "No internet connection", table: "Localizable", bundle: .main)
            case .timedOut:
                return String(localized: "error.timedOut", defaultValue: "Server timed out", table: "Localizable", bundle: .main)
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return String(localized: "error.unreachable", defaultValue: "Can't reach server", table: "Localizable", bundle: .main)
            default:
                return String(localized: "error.connection", defaultValue: "Connection error", table: "Localizable", bundle: .main)
            }
        case .http:
            return String(localized: "error.connection", defaultValue: "Connection error", table: "Localizable", bundle: .main)
        case .responseTooLarge, .decode:
            return String(localized: "error.generic", defaultValue: "Couldn't load status", table: "Localizable", bundle: .main)
        }
    }
}

/// Store-side fallback for any error reaching the status catch block (a `FetchError` maps via its
/// `friendlyMessage`; anything else — e.g. `CancellationError` — gets the generic message, exactly
/// as the original `friendly(_:)` did).
func friendly(_ error: Error) -> String {
    (error as? FetchError)?.friendlyMessage
        ?? String(localized: "error.generic", defaultValue: "Couldn't load status", table: "Localizable", bundle: .main)
}
