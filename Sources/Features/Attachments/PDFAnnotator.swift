import PDFKit
import PencilKit
import SwiftUI
import UIKit

struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}

/// A PDF page with a transparent PencilKit annotation layer. Read mode leaves
/// PDF scrolling/zoom enabled; annotation mode pins the page and sends touches
/// to the canvas.
struct PDFAnnotatorView: UIViewControllerRepresentable {
    let data: Data
    @Binding var annotationData: Data?
    var isAnnotating: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PDFAnnotatorController {
        let controller = PDFAnnotatorController(pdfData: data, annotationData: annotationData)
        controller.onDrawingChanged = { value in
            annotationData = value
        }
        controller.isAnnotating = isAnnotating
        return controller
    }

    func updateUIViewController(_ controller: PDFAnnotatorController, context: Context) {
        controller.isAnnotating = isAnnotating
        if controller.annotationData != annotationData {
            controller.setAnnotationData(annotationData)
        }
    }

    @MainActor
    final class Coordinator {
        var parent: PDFAnnotatorView
        init(_ parent: PDFAnnotatorView) { self.parent = parent }
    }
}

@MainActor
final class PDFAnnotatorController: UIViewController {
    private let pdfView = PDFView()
    private let canvas = PKCanvasView()
    private let pdfData: Data
    private(set) var annotationData: Data?
    var onDrawingChanged: ((Data?) -> Void)?

    var isAnnotating: Bool = false {
        didSet {
            canvas.isUserInteractionEnabled = isAnnotating
            pdfView.isUserInteractionEnabled = !isAnnotating
            canvas.alpha = isAnnotating ? 1 : 0.96
        }
    }

    init(pdfData: Data, annotationData: Data?) {
        self.pdfData = pdfData
        self.annotationData = annotationData
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .clear
        pdfView.frame = root.bounds
        pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        pdfView.document = PDFDocument(data: pdfData)
        root.addSubview(pdfView)

        canvas.frame = root.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.isScrollEnabled = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.tool = PKInkingTool(.pen, color: .systemBlue, width: 3)
        canvas.delegate = self
        if let annotationData, let drawing = try? PKDrawing(data: annotationData) {
            canvas.drawing = drawing
        }
        root.addSubview(canvas)
        view = root
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isAnnotating {
            canvas.becomeFirstResponder()
        }
    }

    func setAnnotationData(_ data: Data?) {
        annotationData = data
        guard let data, let drawing = try? PKDrawing(data: data) else {
            canvas.drawing = PKDrawing()
            return
        }
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvas.drawing = drawing
        }
    }
}

extension PDFAnnotatorController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        let value = canvasView.drawing.strokes.isEmpty ? nil : canvasView.drawing.dataRepresentation()
        annotationData = value
        onDrawingChanged?(value)
    }
}
