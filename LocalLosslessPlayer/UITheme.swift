import SwiftUI
import UIKit
import ImageIO

actor ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]

    private init() {
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(at path: String?, maxPixelSize: Int) async -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        let pixelSize = max(32, maxPixelSize)
        let key = "\(path)#\(pixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached(priority: .utility) {
            Self.decodeThumbnail(at: path, maxPixelSize: pixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        guard let image else { return nil }
        let pixels = image.size.width * image.size.height
        cache.setObject(image, forKey: key, cost: Int(pixels * 4))
        return image
    }

    func removeAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        cache.removeAllObjects()
    }

    private nonisolated static func decodeThumbnail(at path: String, maxPixelSize: Int) -> UIImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

enum PlayerPalette {
    static let background = Color(red: 0.025, green: 0.031, blue: 0.029)
    static let surface = Color(red: 0.07, green: 0.08, blue: 0.075)
    static let raised = Color(red: 0.11, green: 0.12, blue: 0.115)
    static let line = Color.white.opacity(0.10)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.56)
    static let green = Color(red: 0.61, green: 0.91, blue: 0.24)
    static let coral = Color(red: 0.94, green: 0.34, blue: 0.31)
    static let cyan = Color(red: 0.25, green: 0.72, blue: 0.78)
    static let gold = Color(red: 0.95, green: 0.69, blue: 0.24)
}

struct ArtworkTile: View {
    let title: String
    let size: CGFloat
    var large = false
    var artworkPath: String? = nil
    var circular = false
    @State private var artworkImage: UIImage?

    private var color: Color {
        let colors = [PlayerPalette.green, PlayerPalette.coral, PlayerPalette.cyan, PlayerPalette.gold]
        return colors[title.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }]
    }

    var body: some View {
        ZStack {
            PlayerPalette.raised
            if let image = artworkImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(color.opacity(0.78)).frame(width: size * 0.67, height: size * 0.67).rotationEffect(.degrees(large ? 12 : 8))
                Circle().fill(PlayerPalette.background).frame(width: size * 0.34, height: size * 0.34)
                Circle().fill(color).frame(width: size * 0.10, height: size * 0.10)
                Image(systemName: "waveform").font(.system(size: large ? 30 : 12, weight: .bold)).foregroundStyle(PlayerPalette.primary.opacity(0.9)).offset(y: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: large ? 8 : 6)))
        .overlay {
            if circular {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: large ? 8 : 6).stroke(Color.white.opacity(0.08))
            }
        }
        .task(id: artworkTaskID) {
            guard let artworkPath else {
                artworkImage = nil
                return
            }
            let scale = UIScreen.main.scale
            let requestedSize = Int(ceil(size * scale * (large ? 1.5 : 1)))
            let image = await ArtworkImageCache.shared.image(at: artworkPath, maxPixelSize: requestedSize)
            guard !Task.isCancelled else { return }
            artworkImage = image
        }
    }

    private var artworkTaskID: String { "\(artworkPath ?? "")#\(size)#\(large)" }
}

/// The full-size artwork on the now-playing screen behaves like a slow record.
/// TimelineView keeps the animation local to this view, so playback progress does
/// not cause the surrounding player page to redraw at display rate.
struct RotatingArtworkTile: View {
    let title: String
    let size: CGFloat
    let artworkPath: String?
    let isPlaying: Bool
    private let rotationDuration: TimeInterval = 24
    @State private var accumulatedRotation = 0.0
    @State private var startedAt: Date?
    @State private var rotationKey = ""

    private var artworkID: String { "\(artworkPath ?? "")#\(title)" }

    var body: some View {
        Group {
            if isPlaying {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    artworkView(rotation: rotation(at: context.date))
                }
            } else {
                artworkView(rotation: accumulatedRotation)
            }
        }
        .onAppear {
            rotationKey = artworkID
            startedAt = isPlaying ? Date() : nil
        }
        .onChange(of: isPlaying) { playing in
            syncRotation(at: Date(), isPlaying: playing)
        }
        .onChange(of: artworkID) { newID in
            guard newID != rotationKey else { return }
            rotationKey = newID
            accumulatedRotation = 0
            startedAt = isPlaying ? Date() : nil
        }
    }

    private func artworkView(rotation: Double) -> some View {
        ArtworkTile(
            title: title,
            size: size,
            large: true,
            artworkPath: artworkPath,
            circular: true
        )
        .rotationEffect(.degrees(rotation))
    }

    private func rotation(at date: Date) -> Double {
        guard let startedAt else { return accumulatedRotation }
        return accumulatedRotation + date.timeIntervalSince(startedAt) * 360 / rotationDuration
    }

    private func syncRotation(at date: Date, isPlaying playing: Bool) {
        if playing {
            // Preserve the current angle when playback resumes.
            startedAt = date
        } else {
            accumulatedRotation = rotation(at: date).truncatingRemainder(dividingBy: 360)
            startedAt = nil
        }
    }
}

func timeText(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}

extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension String {
    var fileExtensionLabel: String {
        let value = (self as NSString).pathExtension.uppercased()
        return value.isEmpty ? "AUDIO" : value
    }
}
