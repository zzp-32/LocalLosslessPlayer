import XCTest
@testable import LocalLosslessPlayer

final class StorageConfigurationTests: XCTestCase {
    func testMediaRootCanBeOverridden() {
        XCTAssertFalse(StorageConfiguration.appFolderName.isEmpty)
        XCTAssertEqual(StorageConfiguration.mediaFolderName, "Music")
    }

    func testMusicFolderLivesInDocuments() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(StorageConfiguration.mediaRootURL.deletingLastPathComponent(), documents)
        XCTAssertEqual(StorageConfiguration.mediaRootURL.lastPathComponent, "Music")
    }
}
