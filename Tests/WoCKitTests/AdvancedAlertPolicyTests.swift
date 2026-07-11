import Foundation
import Testing
@testable import WoCKit

@Suite struct AdvancedAlertPolicyTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func rule(_ id: String, enabled: Bool = true,
                      cooldown: TimeInterval = 0) -> AdvancedAlertRuleConfiguration {
        AdvancedAlertRuleConfiguration(id: AdvancedAlertRuleID(id), isEnabled: enabled,
                                       cooldown: cooldown)
    }

    private func observe(_ policies: AdvancedAlertPolicySet,
                         state: AdvancedAlertPolicyState = .init(),
                         seconds: TimeInterval = 0,
                         population: Int? = nil,
                         quote: CryptoQuote? = nil,
                         releases: [GameRelease]? = nil) -> AdvancedAlertEvaluation {
        AdvancedAlertPolicyEngine.evaluate(
            policies: policies,
            state: state,
            observation: AdvancedAlertObservation(observedAt: start.addingTimeInterval(seconds),
                                                   population: population, quote: quote,
                                                   releases: releases))
    }

    private func quote(price: String = "0.5", oneHour: Double? = nil,
                       sixHours: Double? = nil, twentyFourHours: Double? = nil,
                       legacy24h: Double = 999) -> CryptoQuote {
        var market: [CryptoMarketTimeframe: CryptoMarketWindow] = [:]
        if let oneHour {
            market[.oneHour] = CryptoMarketWindow(changePercent: oneHour, buys: nil,
                                                  sells: nil, volumeUSD: nil)
        }
        if let sixHours {
            market[.sixHours] = CryptoMarketWindow(changePercent: sixHours, buys: nil,
                                                   sells: nil, volumeUSD: nil)
        }
        if let twentyFourHours {
            market[.twentyFourHours] = CryptoMarketWindow(changePercent: twentyFourHours,
                                                          buys: nil, sells: nil,
                                                          volumeUSD: nil)
        }
        return CryptoQuote(price: price, change24h: legacy24h, market: market)
    }

    private func release(id: Int? = nil, tag: String? = nil, name: String? = nil,
                         prerelease: Bool = false, published: TimeInterval? = nil,
                         body: String? = nil) -> GameRelease {
        GameRelease(id: id, tag: tag, name: name, body: body,
                    url: tag.flatMap { URL(string: "https://example.com/releases/\($0)") },
                    isPrerelease: prerelease,
                    publishedAt: published.map { start.addingTimeInterval($0) })
    }

    // MARK: Normalization and quiet hours

    @Test func normalizationRejectsInvalidIDsAndFloatingPointTargets() {
        #expect(AdvancedAlertRuleID("  players  ").rawValue == "players")
        #expect(!AdvancedAlertRuleID(" \n ").isValid)
        #expect(AdvancedAlertNormalization.positiveFinite(.nan) == nil)
        #expect(AdvancedAlertNormalization.positiveFinite(.infinity) == nil)
        #expect(AdvancedAlertNormalization.positiveFinite(0) == nil)
        #expect(AdvancedAlertNormalization.positiveFinite(0.1) == 0.1)
        #expect(AdvancedAlertNormalization.nonnegativeFinite(-1) == nil)
        #expect(AdvancedAlertNormalization.cooldown(-30) == 0)
        #expect(AdvancedAlertNormalization.cooldown(.infinity) == 0)
        #expect(AdvancedAlertNormalization.minuteOfDay(-60) == 1_380)
        #expect(AdvancedAlertNormalization.minuteOfDay(1_500) == 60)
        #expect(AdvancedAlertNormalization.minuteOfDay(hour: .max, minute: .min) >= 0)
        #expect(AdvancedAlertNormalization.minuteOfDay(hour: .max, minute: .min) < 1_440)
    }

    @Test func policiesNormalizeThresholdsHysteresisAndDuplicates() {
        let invalidPrice = TokenPriceTargetAlertPolicy(rule: rule("bad"), direction: .above,
                                                       target: .nan, hysteresis: 4)
        let invalidID = PopulationThresholdAlertPolicy(rule: rule(" "), direction: .above,
                                                       threshold: 3)
        let first = PopulationThresholdAlertPolicy(rule: rule("same", cooldown: -2),
                                                   direction: .above, threshold: -5,
                                                   hysteresis: -9)
        let duplicate = PopulationThresholdAlertPolicy(rule: rule("same"), direction: .below,
                                                       threshold: 20)
        let normalized = AdvancedAlertPolicySet(population: [invalidID, first, duplicate],
                                                tokenPrices: [invalidPrice]).normalized()
        #expect(normalized.population.count == 1)
        #expect(normalized.population[0].direction == .above)
        #expect(normalized.population[0].threshold == 0)
        #expect(normalized.population[0].hysteresis == 0)
        #expect(normalized.population[0].rule.cooldown == 0)
        #expect(normalized.tokenPrices.isEmpty)
    }

    @Test func daytimeQuietHoursUseStartInclusiveEndExclusiveBoundaries() throws {
        let quiet = AlertQuietHours(startHour: 9, startMinute: 30, endHour: 17,
                                    endMinute: 0, timeZone: utc)
        #expect(!quiet.contains(try date("2027-01-01T09:29:00Z")))
        #expect(quiet.contains(try date("2027-01-01T09:30:00Z")))
        #expect(quiet.contains(try date("2027-01-01T16:59:00Z")))
        #expect(!quiet.contains(try date("2027-01-01T17:00:00Z")))
    }

    @Test func overnightQuietHoursSpanMidnightAndRespectTimezone() throws {
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        let quiet = AlertQuietHours(startHour: 22, endHour: 7, timeZone: chicago)
        // January is CST: these UTC values correspond to 21:59, 22:00, 06:59, and 07:00.
        #expect(!quiet.contains(try date("2027-01-02T03:59:00Z")))
        #expect(quiet.contains(try date("2027-01-02T04:00:00Z")))
        #expect(quiet.contains(try date("2027-01-02T12:59:00Z")))
        #expect(!quiet.contains(try date("2027-01-02T13:00:00Z")))
    }

    @Test func equalQuietHoursMeanAllDayUnlessDisabled() {
        let allDay = AlertQuietHours(startHour: 8, endHour: 8, timeZone: utc)
        let disabled = AlertQuietHours(isEnabled: false, startHour: 8, endHour: 8,
                                       timeZone: utc)
        #expect(allDay.contains(start))
        #expect(!disabled.contains(start))
    }

    // MARK: Population crossings and hysteresis

    @Test func populationSeedsSilentlyThenFiresOnExactUpwardCrossing() {
        let policies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("busy"), direction: .above,
                                           threshold: 100, hysteresis: 10)
        ])
        let seeded = observe(policies, population: 99)
        #expect(seeded.decisions.isEmpty)

        let crossed = observe(policies, state: seeded.state, seconds: 1, population: 100)
        #expect(crossed.decisions == [
            AdvancedAlertDecision(ruleID: AdvancedAlertRuleID("busy"),
                                  firedAt: start.addingTimeInterval(1),
                                  payload: .population(direction: .above, count: 100,
                                                       threshold: 100))
        ])
    }

    @Test func initialTriggeredPopulationDoesNotFireUntilItRearmsAndCrossesAgain() {
        let policies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("busy"), direction: .above,
                                           threshold: 100, hysteresis: 10)
        ])
        let initial = observe(policies, population: 120)
        let stillHigh = observe(policies, state: initial.state, seconds: 1, population: 130)
        let notFarEnough = observe(policies, state: stillHigh.state, seconds: 2, population: 95)
        let recrossWithoutRearm = observe(policies, state: notFarEnough.state, seconds: 3,
                                          population: 101)
        #expect(initial.decisions.isEmpty)
        #expect(stillHigh.decisions.isEmpty)
        #expect(recrossWithoutRearm.decisions.isEmpty)

        let rearmed = observe(policies, state: recrossWithoutRearm.state, seconds: 4,
                              population: 90)
        let fired = observe(policies, state: rearmed.state, seconds: 5, population: 100)
        #expect(fired.decisions.count == 1)
    }

    @Test func firedRuleDoesNotSpamAndRequiresDeadbandBeforeRearming() {
        let policies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("busy"), direction: .above,
                                           threshold: 100, hysteresis: 10)
        ])
        let a = observe(policies, population: 80)
        let b = observe(policies, state: a.state, seconds: 1, population: 105)
        let c = observe(policies, state: b.state, seconds: 2, population: 120)
        let d = observe(policies, state: c.state, seconds: 3, population: 95)
        let e = observe(policies, state: d.state, seconds: 4, population: 110)
        let f = observe(policies, state: e.state, seconds: 5, population: 90)
        let g = observe(policies, state: f.state, seconds: 6, population: 101)
        #expect(b.decisions.count == 1)
        #expect(c.decisions.isEmpty)
        #expect(e.decisions.isEmpty)
        #expect(g.decisions.count == 1)
    }

    @Test func belowPopulationRuleUsesMirroredCrossingAndRearmSemantics() {
        let policies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("quiet"), direction: .below,
                                           threshold: 20, hysteresis: 5)
        ])
        let a = observe(policies, population: 30)
        let b = observe(policies, state: a.state, seconds: 1, population: 20)
        let c = observe(policies, state: b.state, seconds: 2, population: 24)
        let d = observe(policies, state: c.state, seconds: 3, population: 19)
        let e = observe(policies, state: d.state, seconds: 4, population: 25)
        let f = observe(policies, state: e.state, seconds: 5, population: 18)
        #expect(b.decisions.first?.payload == .population(direction: .below, count: 20,
                                                          threshold: 20))
        #expect(d.decisions.isEmpty)
        #expect(f.decisions.count == 1)
    }

    @Test func invalidPopulationObservationDoesNotMutateState() {
        let policies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("busy"), direction: .above, threshold: 10)
        ])
        let seeded = observe(policies, population: 5)
        let invalid = observe(policies, state: seeded.state, seconds: 1, population: -1)
        #expect(invalid.state == seeded.state)
        #expect(invalid.decisions.isEmpty)
        #expect(invalid.suppressed.isEmpty)
    }

    @Test func changingThresholdReseedsSilently() {
        let initialPolicies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("busy"), direction: .above, threshold: 100)
        ])
        let seeded = observe(initialPolicies, population: 80)
        let editedPolicies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("busy"), direction: .above, threshold: 70)
        ])
        let afterEdit = observe(editedPolicies, state: seeded.state, seconds: 1, population: 80)
        #expect(afterEdit.decisions.isEmpty)
    }

    // MARK: Delivery gate

    @Test func cooldownIsPerRuleAndExactExpiryIsDeliverable() {
        let policies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("a", cooldown: 60), direction: .above,
                                           threshold: 10, hysteresis: 1),
            PopulationThresholdAlertPolicy(rule: rule("b", cooldown: 60), direction: .above,
                                           threshold: 20, hysteresis: 1)
        ])
        let seeded = observe(policies, population: 0)
        let first = observe(policies, state: seeded.state, seconds: 1, population: 21)
        #expect(first.decisions.map(\.ruleID) == [AdvancedAlertRuleID("a"),
                                                 AdvancedAlertRuleID("b")])

        let rearmA = observe(policies, state: first.state, seconds: 2, population: 9)
        let suppressedA = observe(policies, state: rearmA.state, seconds: 30, population: 10)
        #expect(suppressedA.decisions.isEmpty)
        #expect(suppressedA.suppressed.first?.reason
                == .cooldown(until: start.addingTimeInterval(61)))

        // Suppression consumes the crossing. Rearm, then crossing at the exact expiry is allowed.
        let rearmAgain = observe(policies, state: suppressedA.state, seconds: 40, population: 9)
        let exactExpiry = observe(policies, state: rearmAgain.state, seconds: 61, population: 10)
        #expect(exactExpiry.decisions.map(\.ruleID) == [AdvancedAlertRuleID("a")])
    }

    @Test func quietHoursSuppressAndConsumeCrossing() throws {
        let quietDate = try date("2027-01-01T23:00:00Z")
        let base = quietDate.addingTimeInterval(-10)
        let policies = AdvancedAlertPolicySet(
            population: [PopulationThresholdAlertPolicy(rule: rule("busy"), direction: .above,
                                                         threshold: 10, hysteresis: 2)],
            quietHours: AlertQuietHours(startHour: 22, endHour: 7, timeZone: utc))
        let seeded = AdvancedAlertPolicyEngine.evaluate(
            policies: policies, state: .init(),
            observation: .init(observedAt: base, population: 5))
        let quietCrossing = AdvancedAlertPolicyEngine.evaluate(
            policies: policies, state: seeded.state,
            observation: .init(observedAt: quietDate, population: 12))
        #expect(quietCrossing.decisions.isEmpty)
        #expect(quietCrossing.suppressed.first?.reason == .quietHours)

        let afterQuiet = AdvancedAlertPolicyEngine.evaluate(
            policies: policies, state: quietCrossing.state,
            observation: .init(observedAt: try date("2027-01-02T08:00:00Z"), population: 13))
        #expect(afterQuiet.decisions.isEmpty)
    }

    @Test func disabledRulesTrackAndConsumeCrossings() {
        let off = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("busy", enabled: false), direction: .above,
                                           threshold: 10, hysteresis: 2)
        ])
        let seeded = observe(off, population: 5)
        let crossed = observe(off, state: seeded.state, seconds: 1, population: 12)
        #expect(crossed.suppressed.first?.reason == .disabled)

        let on = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("busy", enabled: true), direction: .above,
                                           threshold: 10, hysteresis: 2)
        ])
        let enabledWhileHigh = observe(on, state: crossed.state, seconds: 2, population: 15)
        #expect(enabledWhileHigh.decisions.isEmpty)
    }

    // MARK: Absolute token price

    @Test func absolutePriceSupportsAboveAndBelowTargetsIndependently() {
        let policies = AdvancedAlertPolicySet(tokenPrices: [
            TokenPriceTargetAlertPolicy(rule: rule("moon"), direction: .above,
                                        target: 1.0, hysteresis: 0.1),
            TokenPriceTargetAlertPolicy(rule: rule("dip"), direction: .below,
                                        target: 0.4, hysteresis: 0.05)
        ])
        let seeded = observe(policies, quote: quote(price: "0.5"))
        let moon = observe(policies, state: seeded.state, seconds: 1,
                           quote: quote(price: "1.0"))
        #expect(moon.decisions == [
            AdvancedAlertDecision(ruleID: AdvancedAlertRuleID("moon"),
                                  firedAt: start.addingTimeInterval(1),
                                  payload: .tokenPrice(direction: .above, price: 1, target: 1))
        ])

        let rearmBoth = observe(policies, state: moon.state, seconds: 2,
                                quote: quote(price: "0.9"))
        let dip = observe(policies, state: rearmBoth.state, seconds: 3,
                          quote: quote(price: "0.4"))
        #expect(dip.decisions.first?.payload
                == .tokenPrice(direction: .below, price: 0.4, target: 0.4))
    }

    @Test func malformedNonfiniteAndNonpositivePricesAreIgnored() {
        let policies = AdvancedAlertPolicySet(tokenPrices: [
            TokenPriceTargetAlertPolicy(rule: rule("moon"), direction: .above, target: 1)
        ])
        for price in ["nope", "nan", "inf", "0", "-1"] {
            let result = observe(policies, quote: quote(price: price))
            #expect(result.state == AdvancedAlertPolicyState())
            #expect(result.decisions.isEmpty)
        }
    }

    // MARK: Rolling-window token changes

    @Test func rollingRulesReadTheirExactRichCryptoQuoteWindows() {
        let policies = AdvancedAlertPolicySet(tokenChanges: [
            TokenRollingChangeAlertPolicy(rule: rule("h1"), window: .oneHour,
                                          direction: .gain, thresholdPercent: 10),
            TokenRollingChangeAlertPolicy(rule: rule("h6"), window: .sixHours,
                                          direction: .gain, thresholdPercent: 20),
            TokenRollingChangeAlertPolicy(rule: rule("h24"), window: .twentyFourHours,
                                          direction: .gain, thresholdPercent: 30)
        ])
        let seeded = observe(policies, quote: quote(oneHour: 9, sixHours: 19,
                                                    twentyFourHours: 29, legacy24h: 500))
        let crossed = observe(policies, state: seeded.state, seconds: 1,
                              quote: quote(price: "0.6", oneHour: 10, sixHours: 20,
                                           twentyFourHours: 30, legacy24h: -500))
        #expect(crossed.decisions.map(\.ruleID) == [AdvancedAlertRuleID("h1"),
                                                   AdvancedAlertRuleID("h6"),
                                                   AdvancedAlertRuleID("h24")])
        #expect(crossed.decisions.map(\.payload) == [
            .tokenChange(direction: .gain, window: .oneHour, changePercent: 10,
                         thresholdPercent: 10, price: 0.6),
            .tokenChange(direction: .gain, window: .sixHours, changePercent: 20,
                         thresholdPercent: 20, price: 0.6),
            .tokenChange(direction: .gain, window: .twentyFourHours, changePercent: 30,
                         thresholdPercent: 30, price: 0.6)
        ])
    }

    @Test func lossRuleUsesNegativeThresholdAndRearmsTowardZero() {
        let policies = AdvancedAlertPolicySet(tokenChanges: [
            TokenRollingChangeAlertPolicy(rule: rule("dump"), window: .oneHour,
                                          direction: .loss, thresholdPercent: 10,
                                          hysteresisPercent: 2)
        ])
        let seeded = observe(policies, quote: quote(oneHour: -5))
        let fired = observe(policies, state: seeded.state, seconds: 1,
                            quote: quote(oneHour: -10))
        let notRearmed = observe(policies, state: fired.state, seconds: 2,
                                 quote: quote(oneHour: -9))
        let recross = observe(policies, state: notRearmed.state, seconds: 3,
                              quote: quote(oneHour: -12))
        #expect(fired.decisions.first?.payload
                == .tokenChange(direction: .loss, window: .oneHour, changePercent: -10,
                                thresholdPercent: 10, price: 0.5))
        #expect(recross.decisions.isEmpty)

        let rearmed = observe(policies, state: recross.state, seconds: 4,
                              quote: quote(oneHour: -8))
        let firedAgain = observe(policies, state: rearmed.state, seconds: 5,
                                 quote: quote(oneHour: -10))
        #expect(firedAgain.decisions.count == 1)
    }

    @Test func missingOrNonfiniteWindowMetricDoesNotSeedOrMutateRule() {
        let policies = AdvancedAlertPolicySet(tokenChanges: [
            TokenRollingChangeAlertPolicy(rule: rule("h6"), window: .sixHours,
                                          direction: .gain, thresholdPercent: 10)
        ])
        let missing = observe(policies, quote: quote(oneHour: 20))
        let nonfinite = observe(policies, state: missing.state, seconds: 1,
                                quote: quote(sixHours: .infinity))
        #expect(missing.state.tokenChanges.isEmpty)
        #expect(nonfinite.state == missing.state)
    }

    // MARK: Release detection

    @Test func currentReleaseFeedSeedsSilentlyThenOnlyNewIdentityFiresOnce() {
        let policies = AdvancedAlertPolicySet(releases: [
            NewGameReleaseAlertPolicy(rule: rule("release"))
        ])
        let v1 = release(id: 1, tag: "v1", name: "One", published: 0)
        let v2 = release(id: 2, tag: "v2", name: "Two", published: 100, body: "  Notes  ")
        let seeded = observe(policies, releases: [v1])
        let next = observe(policies, state: seeded.state, seconds: 101, releases: [v2, v1])
        #expect(seeded.decisions.isEmpty)
        #expect(next.decisions == [
            AdvancedAlertDecision(
                ruleID: AdvancedAlertRuleID("release"),
                firedAt: start.addingTimeInterval(101),
                payload: .gameRelease(GameReleaseAlertPayload(
                    identity: "id:2", tag: "v2", name: "Two", summary: "Notes",
                    url: URL(string: "https://example.com/releases/v2"), isPrerelease: false,
                    publishedAt: start.addingTimeInterval(100))))
        ])
        let repeated = observe(policies, state: next.state, seconds: 102, releases: [v2, v1])
        #expect(repeated.decisions.isEmpty)
    }

    @Test func emptySuccessfulReleaseFeedAllowsFirstLaterReleaseToFire() {
        let policies = AdvancedAlertPolicySet(releases: [
            NewGameReleaseAlertPolicy(rule: rule("release"))
        ])
        let seeded = observe(policies, releases: [])
        let first = observe(policies, state: seeded.state, seconds: 1,
                            releases: [release(id: 1, tag: "v1")])
        #expect(first.decisions.count == 1)
    }

    @Test func newestOfSeveralUnseenReleasesWinsDeterministically() {
        let policies = AdvancedAlertPolicySet(releases: [
            NewGameReleaseAlertPolicy(rule: rule("release"))
        ])
        let seeded = observe(policies, releases: [])
        let v2 = release(id: 2, tag: "v2", published: 200)
        let v1 = release(id: 1, tag: "v1", published: 100)
        let result = observe(policies, state: seeded.state, seconds: 201, releases: [v1, v2])
        guard case .gameRelease(let payload) = result.decisions.first?.payload else {
            Issue.record("Expected a game release decision")
            return
        }
        #expect(payload.identity == "id:2")
    }

    @Test func prereleaseFilteringConsumesIneligibleReleaseWithoutLaterReplay() {
        let stableOnly = AdvancedAlertPolicySet(releases: [
            NewGameReleaseAlertPolicy(rule: rule("release"), includesPrereleases: false)
        ])
        let seeded = observe(stableOnly, releases: [])
        let beta = release(id: 2, tag: "v2-beta", prerelease: true, published: 1)
        let ignored = observe(stableOnly, state: seeded.state, seconds: 1, releases: [beta])
        #expect(ignored.decisions.isEmpty)

        let includeBeta = AdvancedAlertPolicySet(releases: [
            NewGameReleaseAlertPolicy(rule: rule("release"), includesPrereleases: true)
        ])
        let afterToggle = observe(includeBeta, state: ignored.state, seconds: 2, releases: [beta])
        #expect(afterToggle.decisions.isEmpty)
    }

    @Test func releaseIdentityFallsBackFromIDToTagURLPublishedDateAndName() {
        let policies = AdvancedAlertPolicySet(releases: [
            NewGameReleaseAlertPolicy(rule: rule("release"), includesPrereleases: true)
        ])
        let seeded = observe(policies, releases: [])
        let tagOnly = GameRelease(tag: "  V3  ", name: "Three")
        let a = observe(policies, state: seeded.state, seconds: 1, releases: [tagOnly])
        guard case .gameRelease(let tagPayload) = a.decisions.first?.payload else {
            Issue.record("Expected tag release")
            return
        }
        #expect(tagPayload.identity == "tag:v3")

        let publishedOnly = GameRelease(name: "  Four ", publishedAt: start.addingTimeInterval(2))
        let b = observe(policies, state: a.state, seconds: 2, releases: [publishedOnly, tagOnly])
        guard case .gameRelease(let publishedPayload) = b.decisions.first?.payload else {
            Issue.record("Expected published release")
            return
        }
        #expect(publishedPayload.identity.hasPrefix("published:"))

        let nameOnly = GameRelease(name: "  Five  ")
        let c = observe(policies, state: b.state, seconds: 3,
                        releases: [nameOnly, publishedOnly, tagOnly])
        guard case .gameRelease(let namePayload) = c.decisions.first?.payload else {
            Issue.record("Expected named release")
            return
        }
        #expect(namePayload.identity == "name:five")
    }

    @Test func identitylessReleaseIsIgnored() {
        let policies = AdvancedAlertPolicySet(releases: [
            NewGameReleaseAlertPolicy(rule: rule("release"))
        ])
        let seeded = observe(policies, releases: [])
        let result = observe(policies, state: seeded.state, seconds: 1,
                             releases: [GameRelease()])
        #expect(result.decisions.isEmpty)
    }

    @Test func releaseCooldownSuppressesAndConsumesSecondRelease() {
        let policies = AdvancedAlertPolicySet(releases: [
            NewGameReleaseAlertPolicy(rule: rule("release", cooldown: 60))
        ])
        let seeded = observe(policies, releases: [])
        let v1 = release(id: 1, tag: "v1", published: 1)
        let first = observe(policies, state: seeded.state, seconds: 1, releases: [v1])
        let v2 = release(id: 2, tag: "v2", published: 2)
        let second = observe(policies, state: first.state, seconds: 2, releases: [v2, v1])
        #expect(first.decisions.count == 1)
        #expect(second.suppressed.first?.reason
                == .cooldown(until: start.addingTimeInterval(61)))

        let afterCooldown = observe(policies, state: second.state, seconds: 61,
                                    releases: [v2, v1])
        #expect(afterCooldown.decisions.isEmpty)
    }

    @Test func noObservedFeedsLeaveAllStateUnchanged() {
        let policies = AdvancedAlertPolicySet(
            population: [PopulationThresholdAlertPolicy(rule: rule("p"), direction: .above,
                                                         threshold: 1)],
            tokenPrices: [TokenPriceTargetAlertPolicy(rule: rule("price"), direction: .above,
                                                      target: 1)],
            tokenChanges: [TokenRollingChangeAlertPolicy(rule: rule("change"), window: .oneHour,
                                                         direction: .gain, thresholdPercent: 1)],
            releases: [NewGameReleaseAlertPolicy(rule: rule("release"))])
        let result = observe(policies)
        #expect(result.state == AdvancedAlertPolicyState())
        #expect(result.decisions.isEmpty)
        #expect(result.suppressed.isEmpty)
    }

    @Test func invalidObservationTimestampIsACompleteNoOp() {
        let policies = AdvancedAlertPolicySet(population: [
            PopulationThresholdAlertPolicy(rule: rule("p"), direction: .above, threshold: 1)
        ])
        let result = AdvancedAlertPolicyEngine.evaluate(
            policies: policies, state: .init(),
            observation: .init(observedAt: Date(timeIntervalSinceReferenceDate: .nan),
                               population: 2))
        #expect(result == AdvancedAlertEvaluation(state: .init(), decisions: [], suppressed: []))
    }

    private func date(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try #require(formatter.date(from: string))
    }
}
