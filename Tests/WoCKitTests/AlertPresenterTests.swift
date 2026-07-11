import Testing
import Foundation
@testable import WoCKit

/// Byte-identity of the localized alert text vs. the original inline literals. (String(localized:)
/// falls back to the `defaultValue` here since the compiled catalog isn't in the test bundle, so
/// these assert the exact English the app ships.)
@Suite struct AlertPresenterTests {
    @Test func statusUpPluralizes() {
        #expect(AlertPresenter.content(for: .statusUp(realm: "Claudemoon", count: 5)).title == "✅ Claudemoon is back")
        #expect(AlertPresenter.content(for: .statusUp(realm: "Claudemoon", count: 5)).body == "5 players online now.")
        #expect(AlertPresenter.content(for: .statusUp(realm: "X", count: 1)).body == "1 player online now.")
        #expect(AlertPresenter.content(for: .statusUp(realm: "X", count: 0)).body == "0 players online now.")
    }

    @Test func statusDown() {
        let c = AlertPresenter.content(for: .statusDown(realm: "Claudemoon"))
        #expect(c.title == "⚠️ Claudemoon looks down")
        #expect(c.body == "0 players online or the realm is unreachable.")
    }

    @Test func peak() {
        let c = AlertPresenter.content(for: .peak(realm: "Claudemoon", count: 142))
        #expect(c.title == "🏆 New peak on Claudemoon!")
        #expect(c.body == "142 players online — a new record.")
    }

    @Test func cryptoPump() {
        let c = AlertPresenter.content(for: .cryptoPump(percent: 47, price: "0.0005594"))
        #expect(c.title == "🚀 $WOC is Pumping!")
        #expect(c.body == "The price just surged 47% to $0.0005594!")
    }

    @Test func cryptoDump() {
        let c = AlertPresenter.content(for: .cryptoDump(percent: 12, price: "0.0004"))
        #expect(c.title == "📉 $WOC is Down")
        #expect(c.body == "The price dropped 12% to $0.0004.")
    }
}
