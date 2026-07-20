import Foundation
import Testing
@testable import musetype

struct SomeIMUpdateConfigurationTests {
    @Test
    func stableAppcastURLMatchesMuchtokenContract() {
        #expect(
            SomeIMUpdateConfiguration.feedURL?.absoluteString ==
                "https://some.im/api/v1/public/app-updates/appcast.xml?app_id=qecho&platform=macos&channel=stable"
        )
    }
}
