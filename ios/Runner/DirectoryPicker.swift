import UIKit
import Flutter

class DirectoryPicker: NSObject, UIDocumentPickerDelegate {
    private var result: FlutterResult?

    func selectDirectory(result: @escaping FlutterResult) {
        self.result = result
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        top?.present(documentPicker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            result?(url.path)
        } else {
            result?(nil)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        result?(nil)
    }
}
