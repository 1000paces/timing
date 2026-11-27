import SwiftUI
import VisionKit

// Scans the console's pairing QR (https://<hub>:3443/capture-app/?pair=<CODE>):
// the first code that gives both a hub address and a pairing code wins.
struct QRScannerView: UIViewControllerRepresentable {
    var onFound: (_ address: String, _ code: String) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String, String) -> Void
        private var done = false

        init(onFound: @escaping (String, String) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let barcode) in items {
                guard let payload = barcode.payloadStringValue, let parsed = HubAddress.parse(payload), let code = parsed.code else { continue }
                done = true
                onFound(parsed.base.absoluteString, code)
                return
            }
        }
    }
}
