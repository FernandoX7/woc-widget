import Foundation

/// Pure, stateless alert policy: given prior state + a new observation + settings, it returns the
/// new state and an optional `AlertDecision` — no IO. Semantics are byte-identical to the original
/// `StatusStore.evaluateAlerts`/`checkPeak`/`evaluateCryptoAlerts` (guardrail 8); this is the prime
/// alert test surface.
enum AlertEngine {

    /// Debounced realm availability policy used by the store. A down notification is emitted only
    /// after `requiredFailures` consecutive remote-outage observations. Local-network/schema
    /// failures do not move the confirmed realm state, so they can never generate a false down/up
    /// pair. A healthy response confirms recovery immediately.
    static func evaluateStatus(state: StatusAlertState,
                               observation: StatusAlertObservation,
                               requiredFailures: Int,
                               realm: String,
                               count: Int,
                               settings: AlertSettings)
    -> (state: StatusAlertState, decision: AlertDecision?) {
        switch observation {
        case .healthy:
            let decision: AlertDecision?
            if state.confirmedUp == false, state.recoveryNotificationArmed,
               settings.statusEnabled {
                decision = .statusUp(realm: realm, count: count)
            } else {
                decision = nil
            }
            return (StatusAlertState(confirmedUp: true, consecutiveRemoteFailures: 0,
                                     recoveryNotificationArmed: false), decision)

        case .failure(let countsTowardOutage):
            guard countsTowardOutage else {
                return (StatusAlertState(confirmedUp: state.confirmedUp,
                                         consecutiveRemoteFailures: 0,
                                         recoveryNotificationArmed: state.recoveryNotificationArmed), nil)
            }
            let confirmation = max(1, requiredFailures)
            let failures = min(state.consecutiveRemoteFailures + 1, confirmation)
            guard failures >= confirmation else {
                return (StatusAlertState(confirmedUp: state.confirmedUp,
                                         consecutiveRemoteFailures: failures,
                                         recoveryNotificationArmed: state.recoveryNotificationArmed), nil)
            }
            // If failure is the first state ever observed, establish a down baseline silently.
            let decision: AlertDecision? = (state.confirmedUp == true && settings.statusEnabled)
                ? .statusDown(realm: realm) : nil
            return (StatusAlertState(confirmedUp: false,
                                     consecutiveRemoteFailures: failures,
                                     recoveryNotificationArmed: decision != nil), decision)
        }
    }

    /// Realm up/down transition. `wasUp` always advances to `up`; a decision fires only on an
    /// actual transition with a prior observation and the toggle on (skip-first-observation).
    static func evaluateStatus(wasUp prev: Bool?, up: Bool, realm: String, count: Int,
                               settings: AlertSettings) -> (wasUp: Bool, decision: AlertDecision?) {
        guard let prev, prev != up, settings.statusEnabled else { return (up, nil) }
        return (up, up ? .statusUp(realm: realm, count: count) : .statusDown(realm: realm))
    }

    /// All-time peak. Peak/date advance on any strict new high; a decision fires only if there was
    /// a prior peak (not the first-ever sample) and the toggle is on.
    static func evaluatePeak(count: Int, at date: Date, currentPeak: Int, currentPeakDate: Date?,
                             realm: String, settings: AlertSettings)
    -> (peak: Int, peakDate: Date?, decision: AlertDecision?) {
        guard count > currentPeak else { return (currentPeak, currentPeakDate, nil) }
        let hadPrior = currentPeak > 0
        let decision: AlertDecision? = (hadPrior && settings.peakEnabled) ? .peak(realm: realm, count: count) : nil
        return (count, date, decision)
    }

    /// Crypto pump/dump vs. the `baseline` (last-alerted price). Price ≤ 0 → no-op. First-ever
    /// price seeds the baseline (no alert). Toggle-off freezes the baseline. On a fire the baseline
    /// updates to the current price. Percent uses `Int(round(...))`; the price string mirrors the
    /// original `"\(currentPrice)"` (the parsed Double's description) so the body is byte-identical.
    static func evaluateCrypto(currentPrice: Double, baseline: Double, thresholdPercent: Double,
                               settings: AlertSettings) -> (baseline: Double, decision: AlertDecision?) {
        guard currentPrice > 0 else { return (baseline, nil) }
        if baseline == 0.0 { return (currentPrice, nil) }     // seed on first price
        guard settings.cryptoEnabled else { return (baseline, nil) }

        let changeRatio = currentPrice / baseline
        let thresholdRatio = thresholdPercent / 100.0
        if changeRatio >= (1.0 + thresholdRatio) {
            let percent = Int(round((changeRatio - 1) * 100))
            return (currentPrice, .cryptoPump(percent: percent, price: "\(currentPrice)"))
        } else if changeRatio <= (1.0 - thresholdRatio) {
            let percent = Int(round((1 - changeRatio) * 100))
            return (currentPrice, .cryptoDump(percent: percent, price: "\(currentPrice)"))
        }
        return (baseline, nil)
    }
}

struct StatusAlertState: Sendable, Equatable {
    var confirmedUp: Bool?
    var consecutiveRemoteFailures: Int
    var recoveryNotificationArmed: Bool

    init(confirmedUp: Bool? = nil, consecutiveRemoteFailures: Int = 0,
         recoveryNotificationArmed: Bool = false) {
        self.confirmedUp = confirmedUp
        self.consecutiveRemoteFailures = max(0, consecutiveRemoteFailures)
        self.recoveryNotificationArmed = recoveryNotificationArmed
    }
}

enum StatusAlertObservation: Sendable, Equatable {
    case healthy
    case failure(countsTowardOutage: Bool)
}
