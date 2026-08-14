import Foundation

struct FLACMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var lyrics: String?
    var artworkData: Data?
    var artworkMIMEType: String?
    var duration: Double = 0
}

enum FLACMetadataReader {
    enum ReaderError: LocalizedError {
        case invalidSignature
        case truncatedBlock
        case invalidVorbisComment
        case invalidPicture

        var errorDescription: String? {
            switch self {
            case .invalidSignature: return "Not a FLAC file"
            case .truncatedBlock: return "Truncated FLAC metadata block"
            case .invalidVorbisComment: return "Invalid FLAC Vorbis Comment"
            case .invalidPicture: return "Invalid FLAC picture block"
            }
        }
    }

    static func read(from url: URL) throws -> FLACMetadata {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let signature = try handle.read(upToCount: 4), signature == Data("fLaC".utf8) else { throw ReaderError.invalidSignature }

        var result = FLACMetadata()
        var isLast = false
        while !isLast {
            guard let header = try handle.read(upToCount: 4), header.count == 4 else { throw ReaderError.truncatedBlock }
            isLast = header[0] & 0x80 != 0
            let type = header[0] & 0x7f
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            guard let block = try handle.read(upToCount: length), block.count == length else { throw ReaderError.truncatedBlock }
            switch type {
            case 0: readStreamInfo(block, into: &result)
            case 4: try readVorbisComment(block, into: &result)
            case 6 where result.artworkData == nil: try readPicture(block, into: &result)
            default: break
            }
        }
        return result
    }

    private static func readStreamInfo(_ data: Data, into result: inout FLACMetadata) {
        guard data.count >= 18 else { return }
        let packed = data[10..<18].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let sampleRate = packed >> 44
        let totalSamples = packed & 0x0fffffffff
        if sampleRate > 0 { result.duration = Double(totalSamples) / Double(sampleRate) }
    }

    private static func readVorbisComment(_ data: Data, into result: inout FLACMetadata) throws {
        var cursor = 0
        let vendorLength = try readUInt32LE(data, cursor: &cursor)
        guard cursor + Int(vendorLength) <= data.count else { throw ReaderError.invalidVorbisComment }
        cursor += Int(vendorLength)
        let count = try readUInt32LE(data, cursor: &cursor)
        for _ in 0..<count {
            let length = try readUInt32LE(data, cursor: &cursor)
            guard cursor + Int(length) <= data.count,
                  let entry = String(data: data[cursor..<cursor + Int(length)], encoding: .utf8) else { throw ReaderError.invalidVorbisComment }
            cursor += Int(length)
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = entry[..<separator].uppercased()
            let value = String(entry[entry.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "TITLE": result.title = value
            case "ARTIST": result.artist = value
            case "ALBUM": result.album = value
            case "LYRICS", "UNSYNCEDLYRICS", "SYNCEDLYRICS": result.lyrics = value
            default: break
            }
        }
    }

    private static func readPicture(_ data: Data, into result: inout FLACMetadata) throws {
        var cursor = 0
        _ = try readUInt32BE(data, cursor: &cursor)
        let mimeLength = try readUInt32BE(data, cursor: &cursor)
        guard cursor + Int(mimeLength) <= data.count else { throw ReaderError.invalidPicture }
        result.artworkMIMEType = String(data: data[cursor..<cursor + Int(mimeLength)], encoding: .utf8)
        cursor += Int(mimeLength)
        let descriptionLength = try readUInt32BE(data, cursor: &cursor)
        guard cursor + Int(descriptionLength) <= data.count else { throw ReaderError.invalidPicture }
        cursor += Int(descriptionLength)
        for _ in 0..<4 { _ = try readUInt32BE(data, cursor: &cursor) }
        let pictureLength = try readUInt32BE(data, cursor: &cursor)
        guard pictureLength > 0, cursor + Int(pictureLength) <= data.count else { throw ReaderError.invalidPicture }
        result.artworkData = Data(data[cursor..<cursor + Int(pictureLength)])
    }

    private static func readUInt32LE(_ data: Data, cursor: inout Int) throws -> UInt32 {
        guard cursor + 4 <= data.count else { throw ReaderError.truncatedBlock }
        let value = UInt32(data[cursor]) | UInt32(data[cursor + 1]) << 8 | UInt32(data[cursor + 2]) << 16 | UInt32(data[cursor + 3]) << 24
        cursor += 4
        return value
    }

    private static func readUInt32BE(_ data: Data, cursor: inout Int) throws -> UInt32 {
        guard cursor + 4 <= data.count else { throw ReaderError.truncatedBlock }
        let value = UInt32(data[cursor]) << 24 | UInt32(data[cursor + 1]) << 16 | UInt32(data[cursor + 2]) << 8 | UInt32(data[cursor + 3])
        cursor += 4
        return value
    }
}
