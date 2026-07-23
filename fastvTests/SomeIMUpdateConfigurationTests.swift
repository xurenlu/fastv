import Foundation
import Testing
@testable import musetype

struct SomeIMUpdateConfigurationTests {
    @Test
    func stableAppcastURLMatchesMuchtokenContract() throws {
        let url = try #require(SomeIMUpdateConfiguration.feedURL)

        #expect(SomeIMUpdateConfiguration.appcastServiceBaseURL == "https://some.im")
        #expect(url.scheme == "https")
        #expect(url.host == "some.im")
        #expect(url.path == "/api/v1/public/app-updates/appcast.xml")
        #expect(url.query?.contains("app_id=qecho") == true)
        #expect(url.query?.contains("platform=macos") == true)
        #expect(url.query?.contains("channel=stable") == true)
        #expect(url.absoluteString == "https://some.im/api/v1/public/app-updates/appcast.xml?app_id=qecho&platform=macos&channel=stable")
    }
}
