import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ImportPickerMode: String, Identifiable {
    case songs
    case folder

    var id: String { rawValue }

    var contentTypes: [UTType] {
        switch self {
        case .songs:
            return [
                .audio,
                .mp3,
                .wav,
                .aiff,
                .mpeg4Audio,
                UTType(filenameExtension: "flac") ?? .audio,
                UTType(filenameExtension: "alac") ?? .audio
            ]
        case .folder:
            return [.folder]
        }
    }

    var allowsMultipleSelection: Bool { self == .songs }
}

struct PickedResource {
    let url: URL
    let isDirectory: Bool
    let accessStarted: Bool
    let bookmarkData: Data?
    let bookmarkError: String?

    func releaseAccess() {
        if accessStarted { url.stopAccessingSecurityScopedResource() }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let mode: ImportPickerMode
    let onPick: ([PickedResource]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        print("[Picker] Picker opened, mode = \(mode.rawValue)")
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: mode.contentTypes,
            asCopy: false
        )
        picker.allowsMultipleSelection = mode.allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        print("[Picker] Delegate installed = \(picker.delegate != nil)")
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([PickedResource]) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping ([PickedResource]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            print("[Picker] Selection callback received")
            print("[Picker] Callback URL count = \(urls.count)")

            let resources = urls.map { url -> PickedResource in
                print("[Picker] Selected URL = \(url.absoluteString)")

                let isDirectory: Bool
                do {
                    isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                    print("[Picker] URL isDirectory = \(isDirectory)")
                } catch {
                    isDirectory = false
                    print("[Picker] URL isDirectory = false, check failed: \(error.localizedDescription)")
                }

                let accessStarted = url.startAccessingSecurityScopedResource()
                print("[Picker] startAccessing = \(accessStarted)")

                let bookmarkData: Data?
                let bookmarkError: String?
                do {
                    bookmarkData = try SourceReference.bookmark(for: url)
                    bookmarkError = nil
                    print("[Picker] Bookmark created = true")
                } catch {
                    bookmarkData = nil
                    bookmarkError = error.localizedDescription
                    print("[Picker] Bookmark created = false, error = \(error.localizedDescription)")
                }

                return PickedResource(
                    url: url,
                    isDirectory: isDirectory,
                    accessStarted: accessStarted,
                    bookmarkData: bookmarkData,
                    bookmarkError: bookmarkError
                )
            }

            onPick(resources)
            controller.dismiss(animated: true)
        }

        // Kept for providers that still invoke the pre-iOS 11 single-URL delegate callback.
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
            print("[Picker] Legacy selection callback received")
            documentPicker(controller, didPickDocumentsAt: [url])
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("[Picker] Picker cancelled")
            onCancel()
            controller.dismiss(animated: true)
        }
    }
}
