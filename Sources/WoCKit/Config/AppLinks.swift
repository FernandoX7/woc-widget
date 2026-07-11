import Foundation

/// Canonical destinations surfaced by quick actions. Keeping them named here prevents view code
/// from accumulating URL literals and makes link changes independently reviewable.
enum AppLinks {
    static let play = URL(string: "https://worldofclaudecraft.com/")!
    static let wiki = URL(string: "https://worldofclaudecraft.com/wiki/")!
    static let highScores = URL(string: "https://worldofclaudecraft.com/#highscores")!
    static let discord = URL(string: "https://discord.com/invite/GjhnUsBtw")!
    static let gameRepository = URL(string:
        "https://github.com/levy-street/world-of-claudecraft")!
    static let appRepository = URL(string: "https://github.com/FernandoX7/woc-widget")!
    static let appPrivacy = appRepository.appendingPathComponent("blob/main/PRIVACY.md")
    static let appLicense = appRepository.appendingPathComponent("blob/main/LICENSE")
    static let appSupport = appRepository.appendingPathComponent("issues")
    static let market = URL(string:
        "https://dexscreener.com/\(AppConfig.API.dexChain)/\(AppConfig.API.dexPairAddress)")!
    static let geckoTerminal = URL(string:
        "https://www.geckoterminal.com/\(AppConfig.API.geckoNetwork)/pools/\(AppConfig.API.geckoPool)")!
    static let notificationSettings = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
    static let loginItemsSettings = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
    static let tokenContract = AppConfig.API.dexTokenAddress
}
