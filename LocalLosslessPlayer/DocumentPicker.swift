import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PickedResource {
    let url: URL
    let accessStarted: Bool

    func releaseAccess() {
        if accessStarted { url.stopAccessingSecurityScopedResource() }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([PickedResource]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            .audio,
            .mp3,
            .wav,
            .aiff,
            .mpeg4Audio,
            UTType(filenameExtension: "flac") ?? .audio,
            UTType(filenameExtension: "alac") ?? .audio
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([PickedResource]) -> Void

        init(onPick: @escaping ([PickedResource]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            print("[Picker] Selected \(urls.count) file URLs")
            let resources = urls.map { url in
                let accessStarted = url.startAccessingSecurityScopedResource()
                print("[Picker] File = \(url.path), scope = \(accessStarted)")
                return PickedResource(url: url, accessStarted: accessStarted)
            }
            onPick(resources)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("[Picker] File selection cancelled")
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (PickedResource) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (PickedResource) -> Void

        init(onPick: @escaping (PickedResource) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                print("[Picker] Folder callback returned no URL")
                return
            }
            let accessStarted = url.startAccessingSecurityScopedResource()
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            print("[Picker] Folder = \(url.path), scope = \(accessStarted), exists = \(exists), directory = \(isDirectory.boolValue)")
            onPick(PickedResource(url: url, accessStarted: accessStarted))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("[Picker] Folder selection cancelled")
        }
    }
}
