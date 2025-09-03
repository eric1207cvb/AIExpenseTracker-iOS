// DataScannerView.swift

import SwiftUI
import VisionKit

/// iOS 16+ 才有 DataScanner
@available(iOS 16.0, *)
struct DataScannerView: UIViewControllerRepresentable {

    // 綁定掃描結果回寫到上層
    @Binding var recognizedText: String

    // 關閉 sheet
    @Environment(\.dismiss) private var dismiss

    // 建立 UIKit 的掃描器 VC
    func makeUIViewController(context: Context) -> DataScannerViewController {
        // 先檢查是否支援（硬體／相機權限／裝置能力）
        // isSupported = 裝置是否支援
        // isAvailable = 目前環境是否可用（例如相機權限 OK）
        if !DataScannerViewController.isSupported ||
            !DataScannerViewController.isAvailable {
            // 若不可用，提供一個簡單的佔位 VC（避免崩潰）
            let vc = UIViewController()
            let label = UILabel()
            label.text = "此裝置不支援或未授權相機，無法使用掃描功能。"
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: vc.view.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(lessThanOrEqualTo: vc.view.trailingAnchor, constant: -16)
            ])
            return vc as! DataScannerViewController // 強轉避免改動上層型別；不會被使用到委派
        }

        let viewController = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        viewController.delegate = context.coordinator

        // 嘗試開始掃描（若未授權會丟錯，這裡用 try? 安全啟動）
        try? viewController.startScanning()

        return viewController
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        // 一般不需要更新；若之後要改變設定（如 recognizesMultipleItems），可在此處理
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DataScannerView

        init(parent: DataScannerView) { self.parent = parent }

        // 使用者點到辨識到的項目
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .text(let text):
                parent.recognizedText = text.transcript
                // 關閉前先停止掃描，避免相機持續佔用
                try? dataScanner.stopScanning()
                parent.dismiss()
            default:
                break
            }
        }

        // 可選：當偵測項目更新（非點擊）時，你也能在這邊取得最新文字
        // func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { ... }
    }
}

