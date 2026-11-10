import Foundation
import PDFKit
import PencilKit
import SwiftUI
import UIKit
import Vision
import VisionKit

enum OCRError: LocalizedError {
    case noImage
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noImage: "无法读取图像"
        case .failed(let message): "文字识别失败：\(message)"
        }
    }
}

enum OCRService {
    static func recognize(image: UIImage, languages: [String] = ["zh-Hans", "en-US"]) async throws -> String {
        guard let cgImage = image.cgImage else { throw OCRError.noImage }
        return try await recognize(cgImage: cgImage, languages: languages)
    }

    static func recognize(cgImage: CGImage, languages: [String] = ["zh-Hans", "en-US"]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            do {
                return try perform(cgImage: cgImage, languages: languages)
            } catch {
                return try perform(cgImage: cgImage, languages: ["en-US"])
            }
        }.value
    }

    static func pdfText(data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        var pieces: [String] = []
        for index in 0..<document.pageCount {
            if let text = document.page(at: index)?.string, !text.isEmpty {
                pieces.append(text)
            }
        }
        return pieces.joined(separator: "\n")
    }

    static func drawingText(data: Data) async -> String {
        guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return "" }
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        let image = drawing.image(from: bounds, scale: 2)
        return (try? await recognize(image: image)) ?? ""
    }

    private nonisolated static func perform(cgImage: CGImage, languages: [String]) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { lhs, rhs in
            if abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY) > 0.02 {
                return lhs.boundingBox.maxY > rhs.boundingBox.maxY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

enum PDFBuilder {
    static func makePDF(images: [UIImage]) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            for image in images {
                context.beginPage()
                let inset: CGFloat = 24
                let available = pageRect.insetBy(dx: inset, dy: inset)
                let scale = min(available.width / max(1, image.size.width), available.height / max(1, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let origin = CGPoint(
                    x: available.midX - size.width / 2,
                    y: available.midY - size.height / 2
                )
                image.draw(in: CGRect(origin: origin, size: size))
            }
        }
    }
}

@MainActor
enum AttachmentFactory {
    static func photo(data: Data, fileName: String = "照片.jpg") -> Attachment {
        Attachment(kind: .photo, fileName: fileName, data: data)
    }

    static func pdf(data: Data, fileName: String) -> Attachment {
        let text = OCRService.pdfText(data: data)
        return Attachment(kind: .pdf, fileName: fileName, data: data, ocrText: text)
    }

    static func scan(images: [UIImage]) async -> Attachment {
        let pdf = PDFBuilder.makePDF(images: images)
        var textPieces: [String] = []
        for image in images {
            if let text = try? await OCRService.recognize(image: image), !text.isEmpty {
                textPieces.append(text)
            }
        }
        return Attachment(
            kind: .scan,
            fileName: "扫描文稿.pdf",
            data: pdf,
            ocrText: textPieces.joined(separator: "\n"),
            metadata: AttachmentMetadata(pageCount: images.count)
        )
    }

    static func audio(data: Data, duration: Double, transcript: String) -> Attachment {
        Attachment(
            kind: .audio,
            fileName: "录音.caf",
            data: data,
            ocrText: transcript,
            metadata: AttachmentMetadata(durationSeconds: duration)
        )
    }

    static func link(url: URL, title: String) -> Attachment {
        Attachment(
            kind: .link,
            fileName: title.isEmpty ? url.host ?? url.absoluteString : title,
            data: Data(url.absoluteString.utf8),
            ocrText: url.absoluteString,
            metadata: AttachmentMetadata(
                linkURL: url.absoluteString,
                linkTitle: title,
                linkHost: url.host
            )
        )
    }

    static func map(title: String, latitude: Double, longitude: Double) -> Attachment {
        let payload = "\(title)\n\(latitude),\(longitude)"
        return Attachment(
            kind: .map,
            fileName: title,
            data: Data(payload.utf8),
            ocrText: "\(title) \(latitude) \(longitude)",
            metadata: AttachmentMetadata(latitude: latitude, longitude: longitude, mapTitle: title)
        )
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    var onComplete: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onComplete: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [UIImage] = []
            for index in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: index))
            }
            onComplete(images)
            controller.dismiss(animated: true)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
            controller.dismiss(animated: true)
        }
    }
}
