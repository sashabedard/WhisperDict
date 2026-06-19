import Foundation

/// Maps the frontmost application to an Enhance style, so dictation is polished
/// to fit where it lands: email tone in mail clients, code style in editors and
/// terminals, plain faithful in chat. Unmapped apps fall back to the user's
/// chosen default style.
enum AppContext {
    static func resolvedStyle(userDefault: EnhanceStyle, bundleID: String?) -> EnhanceStyle {
        guard let id = bundleID?.lowercased() else { return userDefault }
        if email.contains(where: id.contains)  { return .email }
        if code.contains(where: id.contains)   { return .code }
        if casual.contains(where: id.contains) { return .faithful }
        return userDefault
    }

    // Substring matches, so vendor-prefixed and versioned bundle IDs are covered
    // (e.g. Cursor's "com.todesktop.230313mzl4w4u92", any "com.jetbrains.*").
    private static let email = [
        "com.apple.mail", "readdle.smartemail", "com.microsoft.outlook",
        "com.airmailapp", "com.sparkmailapp", "com.superhuman",
    ]
    private static let code = [
        "com.microsoft.vscode", "com.visualstudio.code.oss", "com.todesktop",
        "com.apple.dt.xcode", "com.jetbrains", "dev.zed.zed",
        "com.googlecode.iterm2", "com.apple.terminal", "com.sublimetext",
        "com.github.atom", "io.neovim", "org.vim",
    ]
    private static let casual = [
        "com.tinyspeck.slackmacgap", "com.apple.mobilesms", "net.whatsapp.whatsapp",
        "com.hnc.discord", "ru.keepcoder.telegram", "com.facebook.messenger",
    ]
    private static let notes = [
        "notion.id", "net.shinyfrog.bear", "md.obsidian", "com.apple.notes",
    ]

    /// True when the frontmost app renders `- ` bullet lists usefully (editors,
    /// note apps, chat, mail) rather than single-line plain-text fields.
    static func supportsRichLists(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return (email + code + casual + notes).contains(where: id.contains)
    }
}
