import AVFoundation
import UIKit
import VisionKit
import WebKit

/// Apple's live barcode scanner, laid exactly over the picklist's camera area.
/// scan.js posts {action: start|move|stop, x, y, w, h} (CSS px = points, since the page
/// fills the web view at zoom 1); every newly seen code goes back through
/// window.__nativeScanDecode([...]) and the page decides what it means.
@MainActor
final class NativeScanner: NSObject, DataScannerViewControllerDelegate, WKScriptMessageHandler {
    weak var web: WKWebView?
    private var scanner: DataScannerViewController?
    private var wanted = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    static var isSupported: Bool { DataScannerViewController.isSupported }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        let rect = CGRect(x: number(body["x"]), y: number(body["y"]), width: number(body["w"]), height: number(body["h"]))
        switch action {
        case "start": start(in: rect)
        case "move": scanner?.view.frame = rect
        case "stop": stop()
        default: break
        }
    }

    private func number(_ value: Any?) -> CGFloat {
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        return 0
    }

    private func start(in rect: CGRect) {
        wanted = true
        if let scanner {
            scanner.view.frame = rect
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted, self.wanted { self.start(in: rect) } else if !granted { self.fail("Camera blocked - allow it in Settings > Picklist > Camera, then reopen Scan.") }
                }
            }
            return
        case .denied, .restricted:
            fail("Camera blocked - allow it in Settings > Picklist > Camera, then reopen Scan.")
            return
        default:
            break
        }
        guard DataScannerViewController.isAvailable, let web else {
            fail("The iPhone scanner is not available right now - close Scan and try again.")
            return
        }
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .dataMatrix, .code128, .ean13, .ean8, .upce, .code39])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = self
        if let parent = web.window?.rootViewController {
            parent.addChild(vc)
            vc.view.frame = rect
            web.addSubview(vc.view)
            vc.didMove(toParent: parent)
        } else {
            vc.view.frame = rect
            web.addSubview(vc.view)
        }
        scanner = vc
        do {
            try vc.startScanning()
        } catch {
            stop()
            fail("The iPhone scanner could not start: \(error.localizedDescription)")
        }
    }

    private func stop() {
        wanted = false
        guard let vc = scanner else { return }
        vc.stopScanning()
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        scanner = nil
    }

    private func fail(_ message: String) {
        send("window.__nativeScanError && window.__nativeScanError(\(WebScreen.Coordinator.jsString(message)));")
    }

    private func send(_ js: String) {
        web?.evaluateJavaScript(js, completionHandler: nil)
    }

    nonisolated func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                                 allItems: [RecognizedItem]) {
        var texts: [String] = []
        for item in addedItems {
            if case .barcode(let code) = item, let text = code.payloadStringValue, !text.isEmpty {
                texts.append(text)
            }
        }
        guard !texts.isEmpty else { return }
        Task { @MainActor in
            self.haptic.impactOccurred()
            let list = texts.map { WebScreen.Coordinator.jsString($0) }.joined(separator: ",")
            self.send("window.__nativeScanDecode && window.__nativeScanDecode([\(list)]);")
        }
    }

    nonisolated func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        Task { @MainActor in
            self.stop()
            self.fail("The iPhone scanner stopped - close Scan and open it again.")
        }
    }
}
