import Testing
import Foundation
@testable import WoCKit

@Suite struct AlertEngineTests {
    let allOn = AlertSettings(statusEnabled: true, peakEnabled: true, cryptoEnabled: true)
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: status up/down

    @Test func statusSkipsFirstObservationButAdvancesState() {
        let r = AlertEngine.evaluateStatus(wasUp: nil, up: true, realm: "R", count: 5, settings: allOn)
        #expect(r.wasUp == true)
        #expect(r.decision == nil)
    }

    @Test func statusNoAlertWhenUnchanged() {
        let r = AlertEngine.evaluateStatus(wasUp: true, up: true, realm: "R", count: 5, settings: allOn)
        #expect(r.decision == nil)
    }

    @Test func statusFiresUpAndDownOnTransition() {
        let down = AlertEngine.evaluateStatus(wasUp: true, up: false, realm: "R", count: 0, settings: allOn)
        #expect(down == (false, .statusDown(realm: "R")))
        let up = AlertEngine.evaluateStatus(wasUp: false, up: true, realm: "R", count: 9, settings: allOn)
        #expect(up == (true, .statusUp(realm: "R", count: 9)))
    }

    @Test func statusToggleOffSuppressesButStillAdvances() {
        let off = AlertSettings(statusEnabled: false, peakEnabled: true, cryptoEnabled: true)
        let r = AlertEngine.evaluateStatus(wasUp: true, up: false, realm: "R", count: 0, settings: off)
        #expect(r.wasUp == false)        // state still advances
        #expect(r.decision == nil)       // but no alert
    }

    @Test func debouncedStatusRequiresTwoRemoteFailures() {
        let seeded = StatusAlertState(confirmedUp: true)
        let first = AlertEngine.evaluateStatus(
            state: seeded, observation: .failure(countsTowardOutage: true),
            requiredFailures: 2, realm: "R", count: 0, settings: allOn)
        #expect(first.state.confirmedUp == true)
        #expect(first.state.consecutiveRemoteFailures == 1)
        #expect(first.decision == nil)

        let second = AlertEngine.evaluateStatus(
            state: first.state, observation: .failure(countsTowardOutage: true),
            requiredFailures: 2, realm: "R", count: 0, settings: allOn)
        #expect(second.state.confirmedUp == false)
        #expect(second.decision == .statusDown(realm: "R"))
    }

    @Test func localFailureDoesNotAdvanceOrTransitionConfirmedStatus() {
        let seeded = StatusAlertState(confirmedUp: true, consecutiveRemoteFailures: 1)
        let result = AlertEngine.evaluateStatus(
            state: seeded, observation: .failure(countsTowardOutage: false),
            requiredFailures: 2, realm: "R", count: 0, settings: allOn)
        #expect(result.state == StatusAlertState(confirmedUp: true,
                                                consecutiveRemoteFailures: 0))
        #expect(result.decision == nil)
    }

    @Test func healthyZeroPlayerResponseIsARecovery() {
        let down = StatusAlertState(confirmedUp: false, consecutiveRemoteFailures: 2,
                                    recoveryNotificationArmed: true)
        let result = AlertEngine.evaluateStatus(
            state: down, observation: .healthy, requiredFailures: 2,
            realm: "R", count: 0, settings: allOn)
        #expect(result.state.confirmedUp == true)
        #expect(result.decision == .statusUp(realm: "R", count: 0))
    }

    @Test func recoveryIsSilentWhenDownTransitionWasSuppressed() {
        let down = StatusAlertState(confirmedUp: false, consecutiveRemoteFailures: 2,
                                    recoveryNotificationArmed: false)
        let result = AlertEngine.evaluateStatus(
            state: down, observation: .healthy, requiredFailures: 2,
            realm: "R", count: 3, settings: allOn)
        #expect(result.state.confirmedUp == true)
        #expect(result.decision == nil)
    }

    // MARK: peak

    @Test func peakNoAlertOnFirstEverSample() {
        let r = AlertEngine.evaluatePeak(count: 5, at: date, currentPeak: 0, currentPeakDate: nil, realm: "R", settings: allOn)
        #expect(r.peak == 5)
        #expect(r.peakDate == date)
        #expect(r.decision == nil)       // hadPrior == false
    }

    @Test func peakFiresOnNewHighWithPrior() {
        let r = AlertEngine.evaluatePeak(count: 10, at: date, currentPeak: 5, currentPeakDate: nil, realm: "R", settings: allOn)
        #expect(r.peak == 10)
        #expect(r.decision == .peak(realm: "R", count: 10))
    }

    @Test func peakUnchangedWhenNotAHigh() {
        let prior = date.addingTimeInterval(-100)
        let r = AlertEngine.evaluatePeak(count: 3, at: date, currentPeak: 5, currentPeakDate: prior, realm: "R", settings: allOn)
        #expect(r.peak == 5)
        #expect(r.peakDate == prior)
        #expect(r.decision == nil)
    }

    @Test func peakAdvancesButSilentWhenToggleOff() {
        let off = AlertSettings(statusEnabled: true, peakEnabled: false, cryptoEnabled: true)
        let r = AlertEngine.evaluatePeak(count: 10, at: date, currentPeak: 5, currentPeakDate: nil, realm: "R", settings: off)
        #expect(r.peak == 10)            // record still advances
        #expect(r.decision == nil)
    }

    // MARK: crypto

    @Test func cryptoIgnoresNonPositivePrice() {
        let r = AlertEngine.evaluateCrypto(currentPrice: 0, baseline: 1.0, thresholdPercent: 10, settings: allOn)
        #expect(r == (1.0, nil))
    }

    @Test func cryptoSeedsBaselineWithoutAlerting() {
        let r = AlertEngine.evaluateCrypto(currentPrice: 1.5, baseline: 0.0, thresholdPercent: 10, settings: allOn)
        #expect(r.baseline == 1.5)
        #expect(r.decision == nil)
    }

    @Test func cryptoPumpAndDumpAndBaselineUpdate() {
        let pump = AlertEngine.evaluateCrypto(currentPrice: 2.0, baseline: 1.0, thresholdPercent: 10, settings: allOn)
        #expect(pump == (2.0, .cryptoPump(percent: 100, price: "2.0")))
        let dump = AlertEngine.evaluateCrypto(currentPrice: 0.5, baseline: 1.0, thresholdPercent: 10, settings: allOn)
        #expect(dump == (0.5, .cryptoDump(percent: 50, price: "0.5")))
    }

    @Test func cryptoBaselineFrozenWhenToggleOff() {
        let off = AlertSettings(statusEnabled: true, peakEnabled: true, cryptoEnabled: false)
        let r = AlertEngine.evaluateCrypto(currentPrice: 2.0, baseline: 1.0, thresholdPercent: 10, settings: off)
        #expect(r == (1.0, nil))         // baseline NOT updated, no alert
    }

    @Test func cryptoNoFireWithinThreshold() {
        let r = AlertEngine.evaluateCrypto(currentPrice: 1.05, baseline: 1.0, thresholdPercent: 10, settings: allOn)
        #expect(r == (1.0, nil))
    }

    @Test func cryptoFiresAtExactThresholdBoundaryNotJustBeyond() {
        // Pins the `>=` / `<=` boundary (a regression to strict `>` would silently miss exact moves).
        #expect(AlertEngine.evaluateCrypto(currentPrice: 1.10, baseline: 1.0, thresholdPercent: 10, settings: allOn).decision
                == .cryptoPump(percent: 10, price: "1.1"))
        #expect(AlertEngine.evaluateCrypto(currentPrice: 1.099, baseline: 1.0, thresholdPercent: 10, settings: allOn).decision == nil)
        #expect(AlertEngine.evaluateCrypto(currentPrice: 0.90, baseline: 1.0, thresholdPercent: 10, settings: allOn).decision
                == .cryptoDump(percent: 10, price: "0.9"))
        #expect(AlertEngine.evaluateCrypto(currentPrice: 0.901, baseline: 1.0, thresholdPercent: 10, settings: allOn).decision == nil)
    }

    // MARK: ids

    @Test func requestIDAppendsTimestamp() {
        let now = Date(timeIntervalSince1970: 1234.5)
        #expect(AlertKind.status.requestID(now: { now }) == "status-1234.5")
        #expect(AlertKind.cryptoPump.requestID(now: { now }) == "crypto_pump-1234.5")
    }
}
