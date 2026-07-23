import Foundation
import Sparkle
import SwiftUI

enum SomeIMUpdateConfiguration {
    nonisolated static let appID = "qecho"
    nonisolated static let platform = "macos"
    nonisolated static let channel = "stable"
    nonisolated static let appcastServiceBaseURL = "https://some.im"

    nonisolated static var feedURL: URL? {
        var components = URLComponents(string: appcastServiceBaseURL)
        components?.path = "/api/v1/public/app-updates/appcast.xml"
        components?.queryItems = [
            URLQueryItem(name: "app_id", value: appID),
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "channel", value: channel),
        ]
        return components?.url
    }
}

@MainActor
final class SomeIMUpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = SomeIMUpdateController()

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var hasStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard !hasStarted, !Self.isRunningTests else { return }
        updaterController.startUpdater()
        hasStarted = true
    }

    func checkForUpdates() {
        guard !Self.isRunningTests else { return }
        start()
        updaterController.checkForUpdates(nil)
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        SomeIMUpdateConfiguration.feedURL?.absoluteString
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

struct SomeIMUpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(String(localized: "someim.update.check", defaultValue: "Check for Updates…")) {
                SomeIMUpdateController.shared.checkForUpdates()
            }
            .focusable(false)
        }
    }
}
