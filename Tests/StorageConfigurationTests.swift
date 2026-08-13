import XCTest
@testable import LocalLosslessPlayer

final class StorageConfigurationTests: XCTestCase {
    func testMediaRootCanBeOverridden() {
        XCTAssertFalse(StorageConfiguration.appFolderName.isEmpty)
        XCTAssertEqual(StorageConfiguration.mediaFolderName, "Music")
    }
}
