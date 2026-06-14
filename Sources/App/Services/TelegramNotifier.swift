//
// Copyright 2026 Mikhail Kasianov
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import Vapor

/// Sends short operational alerts to a Telegram chat through the Bot API.
///
/// The notifier is built from the environment and is absent when
/// `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` are unset, so development and the
/// test suite never reach the network. Errors arrive with sound; routine
/// milestones (a clean startup) arrive silently.
///
struct TelegramNotifier: Sendable {
    let token: String
    let chatID: String
    let client: any Client
    let logger: Logger

    /// Builds a notifier from the environment, or `nil` when the bot
    /// credentials are unset or empty — Compose passes an absent `${VAR:-}` as
    /// an empty string, which must read as "not configured", not a broken token.
    ///
    static func fromEnvironment(client: any Client, logger: Logger) -> TelegramNotifier? {
        guard let token = Environment.get("TELEGRAM_BOT_TOKEN"), token.count > 0, let chatID = Environment.get("TELEGRAM_CHAT_ID"), chatID.count > 0 else {
            return nil
        }
        return TelegramNotifier(token: token, chatID: chatID, client: client, logger: logger)
    }

    /// Delivers a single HTML message. Never throws: a failed alert must not
    /// take down the request or the boot sequence that triggered it.
    ///
    func send(_ text: String, silent: Bool) async {
        let uri = URI(string: "https://api.telegram.org/bot\(token)/sendMessage")
        let payload = Payload(
            chatID: chatID,
            text: text,
            parseMode: "HTML",
            disableWebPagePreview: true,
            disableNotification: silent
        )
        do {
            let response = try await client.post(uri) { request in
                try request.content.encode(payload, as: .json)
            }
            if response.status.code >= 400 {
                logger.warning("Telegram sendMessage failed: \(response.status)")
            }
        } catch {
            logger.report(error: error)
        }
    }

    private struct Payload: Content {
        let chatID: String
        let text: String
        let parseMode: String
        let disableWebPagePreview: Bool
        let disableNotification: Bool

        enum CodingKeys: String, CodingKey {
            case chatID = "chat_id"
            case text
            case parseMode = "parse_mode"
            case disableWebPagePreview = "disable_web_page_preview"
            case disableNotification = "disable_notification"
        }
    }
}

// MARK: - Messages

extension TelegramNotifier {

    /// Silent heartbeat sent once the server finishes booting. Repeated "up"
    /// messages in quick succession are themselves the signal of a crash loop.
    ///
    func serverDidStart() async {
        await send("<b>🟢 scout-server — up</b>", silent: true)
    }

    /// Loud alert sent when boot or the run loop fails — most often the
    /// database being unreachable, which aborts `autoMigrate()` before the
    /// server can serve.
    ///
    func serverDidFail(_ error: any Error) async {
        let reason = Self.htmlEscaped(String(describing: error))
        await send("<b>🔴 scout-server — down</b>\n<pre>\(reason)</pre>", silent: false)
    }

    private static func htmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Application storage

extension Application {
    private struct TelegramNotifierKey: StorageKey {
        typealias Value = TelegramNotifier
    }

    var telegramNotifier: TelegramNotifier? {
        get { storage[TelegramNotifierKey.self] }
        set { storage[TelegramNotifierKey.self] = newValue }
    }
}
