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

    func testLyricParserReadsTimelineAndMultipleTimestamps() {
        let content = """
        [ar:王力宏]
        [00:14.72]北风毫不留情
        [00:18.73][01:20.10]把叶子吹落
        """

        let lines = LyricParser.parse(content)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].time ?? -1, 14.72, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "北风毫不留情")
        XCTAssertEqual(lines[2].time ?? -1, 80.10, accuracy: 0.001)
    }

    func testLyricParserKeepsPlainLyrics() {
        let lines = LyricParser.parse("第一句\n第二句\n第三句")

        XCTAssertEqual(lines.map(\.text), ["第一句", "第二句", "第三句"])
        XCTAssertTrue(lines.allSatisfy { $0.time == nil })
    }
}
