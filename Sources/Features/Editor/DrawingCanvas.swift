import PencilKit
import SwiftUI
import UIKit

enum DrawingBackground: String, CaseIterable, Identifiable {
    case blank, grid, lines

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: "空白"
        case .grid: "网格"
        case .lines: "横线"
        }
    }

    var symbolName: String {
        switch self {
        case .blank: "square"
        case .grid: "grid"
        case .lines: "line.3.horizontal"
        }
    }
}

enum DrawingRenderer {
    static func image(from data: Data?, maxSize: CGSize = CGSize(width: 900, height: 900)) -> UIImage? {
        guard let data, let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -18, dy: -18)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(maxSize.width / bounds.width, maxSize.height / bounds.height, 2)
        return drawing.image(from: bounds, scale: max(1, scale))
    }
}

struct DrawingCanvas: UIViewRepresentable {
    @Binding var data: Data?
    var background: DrawingBackground = .grid
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        if let data, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }
        context.coordinator.canvas = canvas
        DispatchQueue.main.async {
            guard canvas.window != nil else { return }
            let picker = PKToolPicker()
            picker.setVisible(true, forFirstResponder: canvas)
            picker.addObserver(canvas)
            context.coordinator.picker = picker
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.isUserInteractionEnabled = isEditable
        guard let data else {
            if !canvas.drawing.strokes.isEmpty { canvas.drawing = PKDrawing() }
            return
        }
        if let drawing = try? PKDrawing(data: data),
           canvas.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvas.drawing = drawing
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        weak var canvas: PKCanvasView?
        var picker: PKToolPicker?

        init(_ parent: DrawingCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let value = canvasView.drawing.strokes.isEmpty ? nil : canvasView.drawing.dataRepresentation()
            if parent.data != value {
                parent.data = value
            }
        }
    }
}

struct DrawingPaper: View {
    var background: DrawingBackground
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let paper = colorScheme == .dark ? Color(red: 0.10, green: 0.105, blue: 0.12) : Color(red: 0.995, green: 0.99, blue: 0.975)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
            let lineColor = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
            switch background {
            case .blank:
                break
            case .grid:
                var path = Path()
                let step: CGFloat = 28
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(lineColor), lineWidth: 0.6)
            case .lines:
                var path = Path()
                var y: CGFloat = 44
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += 44
                }
                context.stroke(path, with: .color(lineColor), lineWidth: 0.7)
            }
        }
        .overlay(
            Rectangle().stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
        )
    }
}

struct DrawingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var drawingData: Data?
    @State private var draft: Data?
    @State private var background: DrawingBackground = .grid

    var body: some View {
        NavigationStack {
            ZStack {
                DrawingPaper(background: background)
                DrawingCanvas(data: $draft, background: background)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(14)
            .navigationTitle("速绘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        drawingData = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    ForEach(DrawingBackground.allCases) { item in
                        Button {
                            background = item
                        } label: {
                            Label(item.displayName, systemImage: item.symbolName)
                        }
                        .tint(background == item ? LumenTheme.accent : .secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        draft = nil
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                }
            }
            .onAppear { draft = drawingData }
        }
    }
}
