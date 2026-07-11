import Foundation

// MARK: - Configuration

/// A stable caller-owned identity for one alert rule. The identifier is included in every
/// decision so the app can map it back to settings and build a stable notification category.
struct AdvancedAlertRuleID: RawRepresentable, Hashable, Codable, Sendable, Equatable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    var isValid: Bool { !rawValue.isEmpty && rawValue.count <= 128 }
}

enum AlertThresholdDirection: String, Codable, CaseIterable, Sendable, Equatable {
    case above
    case below
}

/// Settings shared by every Alerts 2.0 rule. Cooldowns are measured from the last delivered
/// decision, not from a suppressed event. A disabled rule still observes crossings so enabling it
/// cannot replay an event that happened while it was off.
struct AdvancedAlertRuleConfiguration: Sendable, Equatable {
    let id: AdvancedAlertRuleID
    let isEnabled: Bool
    let cooldown: TimeInterval

    init(id: AdvancedAlertRuleID, isEnabled: Bool = true, cooldown: TimeInterval = 0) {
        self.id = id
        self.isEnabled = isEnabled
        self.cooldown = cooldown
    }

    /// Returns a safe configuration suitable for evaluation, or `nil` for an unusable ID.
    func normalized() -> Self? {
        guard id.isValid else { return nil }
        return Self(id: id, isEnabled: isEnabled,
                    cooldown: AdvancedAlertNormalization.cooldown(cooldown))
    }
}

struct PopulationThresholdAlertPolicy: Sendable, Equatable {
    let rule: AdvancedAlertRuleConfiguration
    let direction: AlertThresholdDirection
    let threshold: Int
    let hysteresis: Int

    init(rule: AdvancedAlertRuleConfiguration, direction: AlertThresholdDirection,
         threshold: Int, hysteresis: Int = 1) {
        self.rule = rule
        self.direction = direction
        self.threshold = threshold
        self.hysteresis = hysteresis
    }

    func normalized() -> Self? {
        guard let rule = rule.normalized() else { return nil }
        let threshold = AdvancedAlertNormalization.nonnegative(threshold)
        let hysteresis = AdvancedAlertNormalization.nonnegative(hysteresis)
        // An above rule cannot rearm below zero, so a larger deadband has no useful meaning.
        let boundedHysteresis = direction == .above ? min(hysteresis, threshold) : hysteresis
        return Self(rule: rule, direction: direction, threshold: threshold,
                    hysteresis: boundedHysteresis)
    }
}

struct TokenPriceTargetAlertPolicy: Sendable, Equatable {
    let rule: AdvancedAlertRuleConfiguration
    let direction: AlertThresholdDirection
    let target: Double
    let hysteresis: Double

    init(rule: AdvancedAlertRuleConfiguration, direction: AlertThresholdDirection,
         target: Double, hysteresis: Double = 0) {
        self.rule = rule
        self.direction = direction
        self.target = target
        self.hysteresis = hysteresis
    }

    func normalized() -> Self? {
        guard let rule = rule.normalized(),
              let target = AdvancedAlertNormalization.positiveFinite(target) else { return nil }
        let hysteresis = AdvancedAlertNormalization.nonnegativeFinite(hysteresis) ?? 0
        let boundedHysteresis = direction == .above ? min(hysteresis, target) : hysteresis
        return Self(rule: rule, direction: direction, target: target,
                    hysteresis: boundedHysteresis)
    }
}

/// Only windows DexScreener exposes as meaningful user-facing rolling changes are supported.
/// Five-minute market data is intentionally excluded from Alerts 2.0 to avoid noisy alerts.
enum TokenChangeAlertWindow: String, Codable, CaseIterable, Sendable, Equatable {
    case oneHour
    case sixHours
    case twentyFourHours

    var marketTimeframe: CryptoMarketTimeframe {
        switch self {
        case .oneHour: return .oneHour
        case .sixHours: return .sixHours
        case .twentyFourHours: return .twentyFourHours
        }
    }
}

enum TokenChangeAlertDirection: String, Codable, CaseIterable, Sendable, Equatable {
    case gain
    case loss
}

struct TokenRollingChangeAlertPolicy: Sendable, Equatable {
    let rule: AdvancedAlertRuleConfiguration
    let window: TokenChangeAlertWindow
    let direction: TokenChangeAlertDirection
    /// Positive magnitude. A loss rule with `10` fires when the rolling change crosses -10%.
    let thresholdPercent: Double
    /// Deadband toward zero required before a fired rule can rearm.
    let hysteresisPercent: Double

    init(rule: AdvancedAlertRuleConfiguration, window: TokenChangeAlertWindow,
         direction: TokenChangeAlertDirection, thresholdPercent: Double,
         hysteresisPercent: Double = 1) {
        self.rule = rule
        self.window = window
        self.direction = direction
        self.thresholdPercent = thresholdPercent
        self.hysteresisPercent = hysteresisPercent
    }

    func normalized() -> Self? {
        guard let rule = rule.normalized(),
              let threshold = AdvancedAlertNormalization.positiveFinite(thresholdPercent)
        else { return nil }
        let hysteresis = min(AdvancedAlertNormalization.nonnegativeFinite(hysteresisPercent) ?? 0,
                             threshold)
        return Self(rule: rule, window: window, direction: direction,
                    thresholdPercent: threshold, hysteresisPercent: hysteresis)
    }
}

struct NewGameReleaseAlertPolicy: Sendable, Equatable {
    let rule: AdvancedAlertRuleConfiguration
    let includesPrereleases: Bool

    init(rule: AdvancedAlertRuleConfiguration, includesPrereleases: Bool = false) {
        self.rule = rule
        self.includesPrereleases = includesPrereleases
    }

    func normalized() -> Self? {
        guard let rule = rule.normalized() else { return nil }
        return Self(rule: rule, includesPrereleases: includesPrereleases)
    }
}

/// An optional daily quiet period evaluated in an explicit timezone. The interval is start-
/// inclusive and end-exclusive. Equal start/end values mean all day when enabled; use
/// `isEnabled == false` for no quiet period.
struct AlertQuietHours: Sendable, Equatable {
    let isEnabled: Bool
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
    let timeZone: TimeZone

    init(isEnabled: Bool = true, startMinuteOfDay: Int, endMinuteOfDay: Int,
         timeZone: TimeZone) {
        self.isEnabled = isEnabled
        self.startMinuteOfDay = AdvancedAlertNormalization.minuteOfDay(startMinuteOfDay)
        self.endMinuteOfDay = AdvancedAlertNormalization.minuteOfDay(endMinuteOfDay)
        self.timeZone = timeZone
    }

    init(isEnabled: Bool = true, startHour: Int, startMinute: Int = 0,
         endHour: Int, endMinute: Int = 0, timeZone: TimeZone) {
        self.init(isEnabled: isEnabled,
                  startMinuteOfDay: AdvancedAlertNormalization.minuteOfDay(
                    hour: startHour, minute: startMinute),
                  endMinuteOfDay: AdvancedAlertNormalization.minuteOfDay(
                    hour: endHour, minute: endMinute),
                  timeZone: timeZone)
    }

    func contains(_ date: Date) -> Bool {
        guard isEnabled else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let value = hour * 60 + minute

        if startMinuteOfDay == endMinuteOfDay { return true }
        if startMinuteOfDay < endMinuteOfDay {
            return value >= startMinuteOfDay && value < endMinuteOfDay
        }
        // Overnight, for example 22:00–07:00.
        return value >= startMinuteOfDay || value < endMinuteOfDay
    }
}

struct AdvancedAlertPolicySet: Sendable, Equatable {
    var population: [PopulationThresholdAlertPolicy]
    var tokenPrices: [TokenPriceTargetAlertPolicy]
    var tokenChanges: [TokenRollingChangeAlertPolicy]
    var releases: [NewGameReleaseAlertPolicy]
    var quietHours: AlertQuietHours?

    init(population: [PopulationThresholdAlertPolicy] = [],
         tokenPrices: [TokenPriceTargetAlertPolicy] = [],
         tokenChanges: [TokenRollingChangeAlertPolicy] = [],
         releases: [NewGameReleaseAlertPolicy] = [],
         quietHours: AlertQuietHours? = nil) {
        self.population = population
        self.tokenPrices = tokenPrices
        self.tokenChanges = tokenChanges
        self.releases = releases
        self.quietHours = quietHours
    }

    /// Normalizes values, removes invalid rules, and deterministically keeps the first duplicate
    /// ID in each rule family. IDs may be reused across different families.
    func normalized() -> Self {
        Self(population: Self.unique(population.compactMap { $0.normalized() }, id: { $0.rule.id }),
             tokenPrices: Self.unique(tokenPrices.compactMap { $0.normalized() }, id: { $0.rule.id }),
             tokenChanges: Self.unique(tokenChanges.compactMap { $0.normalized() }, id: { $0.rule.id }),
             releases: Self.unique(releases.compactMap { $0.normalized() }, id: { $0.rule.id }),
             quietHours: quietHours)
    }

    private static func unique<Value>(_ values: [Value],
                                      id: (Value) -> AdvancedAlertRuleID) -> [Value] {
        var seen = Set<AdvancedAlertRuleID>()
        return values.filter { seen.insert(id($0)).inserted }
    }
}

/// Small, reusable normalization helpers for values loaded from user defaults or text fields.
/// Invalid floating-point alert targets are rejected instead of being silently made meaningful.
enum AdvancedAlertNormalization {
    static func cooldown(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    static func nonnegative(_ value: Int) -> Int { max(0, value) }

    static func positiveFinite(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    static func nonnegativeFinite(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }

    static func minuteOfDay(_ value: Int) -> Int {
        // Floor-mod keeps negative values useful: -60 normalizes to 23:00.
        ((value % 1_440) + 1_440) % 1_440
    }

    static func minuteOfDay(hour: Int, minute: Int) -> Int {
        // Reduce before multiplying/adding so even malformed persisted Int.max values cannot trap.
        minuteOfDay((hour % 24) * 60 + (minute % 1_440))
    }
}

// MARK: - Observation, decisions, and state

/// One immutable snapshot supplied by the caller. `nil` means that feed was not observed in this
/// cycle, while an empty release array is a successful observation with no releases.
struct AdvancedAlertObservation: Sendable, Equatable {
    let observedAt: Date
    let population: Int?
    let quote: CryptoQuote?
    let releases: [GameRelease]?

    init(observedAt: Date, population: Int? = nil, quote: CryptoQuote? = nil,
         releases: [GameRelease]? = nil) {
        self.observedAt = observedAt
        self.population = population
        self.quote = quote
        self.releases = releases
    }
}

struct GameReleaseAlertPayload: Sendable, Equatable {
    let identity: String
    let tag: String?
    let name: String?
    let summary: String?
    let url: URL?
    let isPrerelease: Bool
    let publishedAt: Date?
}

enum AdvancedAlertPayload: Sendable, Equatable {
    case population(direction: AlertThresholdDirection, count: Int, threshold: Int)
    case tokenPrice(direction: AlertThresholdDirection, price: Double, target: Double)
    case tokenChange(direction: TokenChangeAlertDirection, window: TokenChangeAlertWindow,
                     changePercent: Double, thresholdPercent: Double, price: Double)
    case gameRelease(GameReleaseAlertPayload)
}

struct AdvancedAlertDecision: Sendable, Equatable {
    let ruleID: AdvancedAlertRuleID
    let firedAt: Date
    let payload: AdvancedAlertPayload
}

enum AdvancedAlertSuppressionReason: Sendable, Equatable {
    case disabled
    case quietHours
    case cooldown(until: Date)
}

/// Shared pure delivery decision for every alert family. Threshold/release reducers and the
/// baseline-safe realm/record reducers use the same quiet-hours, cooldown, and enabled semantics.
enum AdvancedAlertDeliveryGate {
    static func suppressionReason(
        rule: AdvancedAlertRuleConfiguration,
        at date: Date,
        quietHours: AlertQuietHours?,
        lastDeliveredAt: Date?
    ) -> AdvancedAlertSuppressionReason? {
        if !rule.isEnabled { return .disabled }
        if quietHours?.contains(date) == true { return .quietHours }
        if let lastDeliveredAt {
            let until = lastDeliveredAt.addingTimeInterval(rule.cooldown)
            if date < until { return .cooldown(until: until) }
        }
        return nil
    }
}

struct SuppressedAdvancedAlert: Sendable, Equatable {
    let ruleID: AdvancedAlertRuleID
    let occurredAt: Date
    let payload: AdvancedAlertPayload
    let reason: AdvancedAlertSuppressionReason
}

struct AdvancedThresholdRuleState: Sendable, Equatable {
    fileprivate var signature: ThresholdSignature?
    fileprivate var hasObservation: Bool
    fileprivate var isArmed: Bool
    fileprivate var lastValue: Double?
    fileprivate var lastDeliveredAt: Date?

    init() {
        signature = nil
        hasObservation = false
        isArmed = false
        lastValue = nil
        lastDeliveredAt = nil
    }
}

struct AdvancedReleaseRuleState: Sendable, Equatable {
    fileprivate var hasObservation: Bool
    fileprivate var observedIdentities: Set<String>
    fileprivate var lastDeliveredAt: Date?

    init() {
        hasObservation = false
        observedIdentities = []
        lastDeliveredAt = nil
    }
}

struct AdvancedAlertPolicyState: Sendable, Equatable {
    var population: [AdvancedAlertRuleID: AdvancedThresholdRuleState]
    var tokenPrices: [AdvancedAlertRuleID: AdvancedThresholdRuleState]
    var tokenChanges: [AdvancedAlertRuleID: AdvancedThresholdRuleState]
    var releases: [AdvancedAlertRuleID: AdvancedReleaseRuleState]

    init(population: [AdvancedAlertRuleID: AdvancedThresholdRuleState] = [:],
         tokenPrices: [AdvancedAlertRuleID: AdvancedThresholdRuleState] = [:],
         tokenChanges: [AdvancedAlertRuleID: AdvancedThresholdRuleState] = [:],
         releases: [AdvancedAlertRuleID: AdvancedReleaseRuleState] = [:]) {
        self.population = population
        self.tokenPrices = tokenPrices
        self.tokenChanges = tokenChanges
        self.releases = releases
    }
}

struct AdvancedAlertEvaluation: Sendable, Equatable {
    let state: AdvancedAlertPolicyState
    let decisions: [AdvancedAlertDecision]
    /// Candidate crossings consumed because delivery was disabled, quiet, or cooling down.
    let suppressed: [SuppressedAdvancedAlert]
}

// MARK: - Pure engine

/// Pure Alerts 2.0 reducer. The caller owns state and provides the timestamp; evaluation performs
/// no IO and never reads the wall clock. Policy changes reset that rule's baseline silently.
enum AdvancedAlertPolicyEngine {
    static func evaluate(policies rawPolicies: AdvancedAlertPolicySet,
                         state initialState: AdvancedAlertPolicyState,
                         observation: AdvancedAlertObservation) -> AdvancedAlertEvaluation {
        guard observation.observedAt.timeIntervalSinceReferenceDate.isFinite else {
            return AdvancedAlertEvaluation(state: initialState, decisions: [], suppressed: [])
        }
        let policies = rawPolicies.normalized()
        var state = initialState
        var decisions: [AdvancedAlertDecision] = []
        var suppressed: [SuppressedAdvancedAlert] = []

        if let population = observation.population, population >= 0 {
            for policy in policies.population {
                let signature = ThresholdSignature(direction: policy.direction,
                                                   threshold: Double(policy.threshold),
                                                   hysteresis: Double(policy.hysteresis),
                                                   discriminator: "population")
                let payload = AdvancedAlertPayload.population(direction: policy.direction,
                                                               count: population,
                                                               threshold: policy.threshold)
                reduceThreshold(rule: policy.rule, signature: signature, value: Double(population),
                                payload: payload, at: observation.observedAt,
                                quietHours: policies.quietHours,
                                state: &state.population[policy.rule.id],
                                decisions: &decisions, suppressed: &suppressed)
            }
        }

        if let quote = observation.quote,
           let price = AdvancedAlertNormalization.positiveFinite(Double(quote.price) ?? .nan) {
            for policy in policies.tokenPrices {
                let signature = ThresholdSignature(direction: policy.direction,
                                                   threshold: policy.target,
                                                   hysteresis: policy.hysteresis,
                                                   discriminator: "token-price")
                let payload = AdvancedAlertPayload.tokenPrice(direction: policy.direction,
                                                               price: price, target: policy.target)
                reduceThreshold(rule: policy.rule, signature: signature, value: price,
                                payload: payload, at: observation.observedAt,
                                quietHours: policies.quietHours,
                                state: &state.tokenPrices[policy.rule.id],
                                decisions: &decisions, suppressed: &suppressed)
            }
        }

        if let quote = observation.quote,
           let price = AdvancedAlertNormalization.positiveFinite(Double(quote.price) ?? .nan) {
            for policy in policies.tokenChanges {
                guard let rawChange = quote.metrics(for: policy.window.marketTimeframe)?.changePercent,
                      rawChange.isFinite else { continue }
                let direction: AlertThresholdDirection = policy.direction == .gain ? .above : .below
                let signedThreshold = policy.direction == .gain
                    ? policy.thresholdPercent : -policy.thresholdPercent
                let signature = ThresholdSignature(direction: direction,
                                                   threshold: signedThreshold,
                                                   hysteresis: policy.hysteresisPercent,
                                                   discriminator: "token-change-\(policy.window.rawValue)")
                let payload = AdvancedAlertPayload.tokenChange(
                    direction: policy.direction, window: policy.window,
                    changePercent: rawChange, thresholdPercent: policy.thresholdPercent,
                    price: price)
                reduceThreshold(rule: policy.rule, signature: signature, value: rawChange,
                                payload: payload, at: observation.observedAt,
                                quietHours: policies.quietHours,
                                state: &state.tokenChanges[policy.rule.id],
                                decisions: &decisions, suppressed: &suppressed)
            }
        }

        if let releases = observation.releases {
            for policy in policies.releases {
                reduceReleases(policy: policy, releases: releases, at: observation.observedAt,
                               quietHours: policies.quietHours,
                               state: &state.releases[policy.rule.id], decisions: &decisions,
                               suppressed: &suppressed)
            }
        }

        return AdvancedAlertEvaluation(state: state, decisions: decisions, suppressed: suppressed)
    }

    private static func reduceThreshold(rule: AdvancedAlertRuleConfiguration,
                                        signature: ThresholdSignature, value: Double,
                                        payload: AdvancedAlertPayload, at date: Date,
                                        quietHours: AlertQuietHours?,
                                        state optionalState: inout AdvancedThresholdRuleState?,
                                        decisions: inout [AdvancedAlertDecision],
                                        suppressed: inout [SuppressedAdvancedAlert]) {
        var state = optionalState ?? AdvancedThresholdRuleState()
        if state.signature != signature {
            let delivered = state.lastDeliveredAt
            state = AdvancedThresholdRuleState()
            state.signature = signature
            // Preserve the per-rule delivery clock across target/deadband edits.
            state.lastDeliveredAt = delivered
        }

        guard state.hasObservation, let prior = state.lastValue else {
            state.hasObservation = true
            state.lastValue = value
            state.isArmed = !signature.isTriggered(value)
            optionalState = state
            return
        }

        let crossed = state.isArmed && signature.crossed(from: prior, to: value)
        if crossed {
            state.isArmed = false
            deliver(rule: rule, payload: payload, at: date, quietHours: quietHours,
                    lastDeliveredAt: &state.lastDeliveredAt,
                    decisions: &decisions, suppressed: &suppressed)
        } else if !state.isArmed && signature.isInRearmRegion(value) {
            state.isArmed = true
        }
        state.lastValue = value
        optionalState = state
    }

    private static func reduceReleases(policy: NewGameReleaseAlertPolicy,
                                       releases: [GameRelease], at date: Date,
                                       quietHours: AlertQuietHours?,
                                       state optionalState: inout AdvancedReleaseRuleState?,
                                       decisions: inout [AdvancedAlertDecision],
                                       suppressed: inout [SuppressedAdvancedAlert]) {
        var state = optionalState ?? AdvancedReleaseRuleState()
        let identified = releases.compactMap { release -> (String, GameRelease)? in
            guard let identity = releaseIdentity(release) else { return nil }
            return (identity, release)
        }
        let allIdentities = Set(identified.map(\.0))

        guard state.hasObservation else {
            state.hasObservation = true
            state.observedIdentities.formUnion(allIdentities)
            optionalState = state
            return
        }

        let newEligible = identified.filter { identity, release in
            !state.observedIdentities.contains(identity)
                && (policy.includesPrereleases || !release.isPrerelease)
        }
        // Consume everything seen, including ineligible prereleases and suppressed releases, so a
        // later settings change or quiet-hours exit never replays old news.
        state.observedIdentities.formUnion(allIdentities)

        if let candidate = newestRelease(in: newEligible) {
            let payload = AdvancedAlertPayload.gameRelease(releasePayload(identity: candidate.0,
                                                                           release: candidate.1))
            deliver(rule: policy.rule, payload: payload, at: date, quietHours: quietHours,
                    lastDeliveredAt: &state.lastDeliveredAt,
                    decisions: &decisions, suppressed: &suppressed)
        }
        optionalState = state
    }

    private static func deliver(rule: AdvancedAlertRuleConfiguration,
                                payload: AdvancedAlertPayload, at date: Date,
                                quietHours: AlertQuietHours?, lastDeliveredAt: inout Date?,
                                decisions: inout [AdvancedAlertDecision],
                                suppressed: inout [SuppressedAdvancedAlert]) {
        let reason = AdvancedAlertDeliveryGate.suppressionReason(
            rule: rule, at: date, quietHours: quietHours,
            lastDeliveredAt: lastDeliveredAt)

        if let reason {
            suppressed.append(SuppressedAdvancedAlert(ruleID: rule.id, occurredAt: date,
                                                       payload: payload, reason: reason))
        } else {
            lastDeliveredAt = date
            decisions.append(AdvancedAlertDecision(ruleID: rule.id, firedAt: date,
                                                    payload: payload))
        }
    }

    private static func releaseIdentity(_ release: GameRelease) -> String? {
        if let id = release.id { return "id:\(id)" }
        if let tag = normalizedText(release.tag) { return "tag:\(tag.lowercased())" }
        if let url = release.url { return "url:\(url.absoluteString)" }
        if let publishedAt = release.publishedAt {
            let title = normalizedText(release.name)?.lowercased() ?? "untitled"
            return "published:\(publishedAt.timeIntervalSince1970):\(title)"
        }
        if let name = normalizedText(release.name) { return "name:\(name.lowercased())" }
        return nil
    }

    private static func newestRelease(in values: [(String, GameRelease)])
    -> (String, GameRelease)? {
        values.enumerated().max { lhs, rhs in
            let left = lhs.element.1.publishedAt ?? .distantPast
            let right = rhs.element.1.publishedAt ?? .distantPast
            if left == right { return lhs.offset > rhs.offset }
            return left < right
        }?.element
    }

    private static func releasePayload(identity: String,
                                       release: GameRelease) -> GameReleaseAlertPayload {
        GameReleaseAlertPayload(identity: identity, tag: normalizedText(release.tag),
                                name: normalizedText(release.name),
                                summary: releaseSummary(release.body), url: release.url,
                                isPrerelease: release.isPrerelease,
                                publishedAt: release.publishedAt)
    }

    private static func releaseSummary(_ value: String?) -> String? {
        guard let text = normalizedText(value) else { return nil }
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > 240 else { return collapsed }
        return String(collapsed.prefix(239)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private struct ThresholdSignature: Sendable, Equatable {
    let direction: AlertThresholdDirection
    let threshold: Double
    let hysteresis: Double
    let discriminator: String

    func isTriggered(_ value: Double) -> Bool {
        direction == .above ? value >= threshold : value <= threshold
    }

    func crossed(from oldValue: Double, to newValue: Double) -> Bool {
        switch direction {
        case .above: return oldValue < threshold && newValue >= threshold
        case .below: return oldValue > threshold && newValue <= threshold
        }
    }

    func isInRearmRegion(_ value: Double) -> Bool {
        switch direction {
        case .above:
            return !isTriggered(value) && value <= threshold - hysteresis
        case .below:
            return !isTriggered(value) && value >= threshold + hysteresis
        }
    }
}
