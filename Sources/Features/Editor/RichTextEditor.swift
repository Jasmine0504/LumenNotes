import Observation
import SwiftUI
import UIKit

/// The block-level formatting bar needs to talk to whichever UITextView is
/// currently focused. A single context object is shared by all block editors.
@MainActor
@Observable
final class RichTextEditingContext {
    @ObservationIgnored weak var textView: UITextView?
    @ObservationIgnored var onChange: ((NSAttributedString) -> Void)?
    var isBold = false
    var isItalic = false
    var isHighlighted = false
    var hasFocus = false

    func focus(_ view: UITextView?) {
        textView = view
        hasFocus = view != nil
        refreshState()
    }

    func refreshState() {
        guard let textView else {
            isBold = false
            isItalic = false
            isHighlighted = false
            return
        }
        let attributes = selectedAttributes(in: textView)
        let font = attributes[.font] as? UIFont
        isBold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
        isItalic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
        isHighlighted = attributes[.backgroundColor] != nil
    }

    func toggleBold() {
        applyTrait(.traitBold)
    }

    func toggleItalic() {
        applyTrait(.traitItalic)
    }

    func toggleHighlight() {
        guard let textView else { return }
        let range = textView.selectedRange
        if range.length == 0 {
            var attributes = textView.typingAttributes
            if attributes[.backgroundColor] != nil {
                attributes.removeValue(forKey: .backgroundColor)
            } else {
                attributes[.backgroundColor] = UIColor.systemYellow.withAlphaComponent(0.32)
            }
            textView.typingAttributes = attributes
        } else {
            let current = textView.attributedText.attribute(.backgroundColor, at: range.location, effectiveRange: nil)
            textView.textStorage.beginEditing()
            if current != nil {
                textView.textStorage.removeAttribute(.backgroundColor, range: range)
            } else {
                textView.textStorage.addAttribute(
                    .backgroundColor,
                    value: UIColor.systemYellow.withAlphaComponent(0.32),
                    range: range
                )
            }
            textView.textStorage.endEditing()
        }
        commit(textView)
    }

    private func applyTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let textView else { return }
        let range = textView.selectedRange
        let baseFont = (textView.typingAttributes[.font] as? UIFont) ?? textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        guard range.length > 0 else {
            var traits = baseFont.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                let newFont = UIFont(descriptor: descriptor, size: baseFont.pointSize)
                var attributes = textView.typingAttributes
                attributes[.font] = newFont
                textView.typingAttributes = attributes
            }
            return
        }

        textView.textStorage.beginEditing()
        textView.textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let font = (value as? UIFont) ?? baseFont
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                textView.textStorage.addAttribute(
                    .font,
                    value: UIFont(descriptor: descriptor, size: font.pointSize),
                    range: subRange
                )
            }
        }
        textView.textStorage.endEditing()
        commit(textView)
    }

    private func commit(_ textView: UITextView) {
        refreshState()
        textView.delegate?.textViewDidChange?(textView)
        onChange?(textView.attributedText)
    }

    private func selectedAttributes(in textView: UITextView) -> [NSAttributedString.Key: Any] {
        let range = textView.selectedRange
        if range.length > 0, range.location < textView.attributedText.length {
            return textView.attributedText.attributes(at: range.location, effectiveRange: nil)
        }
        return textView.typingAttributes
    }
}

enum RichTextCoding {
    static func attributedString(from richText: RichText, font: UIFont, color: UIColor) -> NSAttributedString {
        let base: NSAttributedString
        if let rtf = richText.rtf,
           let decoded = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            base = decoded
        } else {
            base = InlineMarkup.attributed(from: richText.plain, font: font, color: color)
        }
        return restyled(base, font: font, color: color)
    }

    static func rtfData(from attributed: NSAttributedString) -> Data? {
        try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func restyled(_ attributed: NSAttributedString, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: result.length)
        result.addAttribute(.foregroundColor, value: color, range: full)
        result.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            let old = (value as? UIFont) ?? font
            var traits: UIFontDescriptor.SymbolicTraits = []
            if old.fontDescriptor.symbolicTraits.contains(.traitBold) { traits.insert(.traitBold) }
            if old.fontDescriptor.symbolicTraits.contains(.traitItalic) { traits.insert(.traitItalic) }
            var styled = font
            if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                styled = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            result.addAttribute(.font, value: styled, range: range)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        result.addAttribute(.paragraphStyle, value: paragraph, range: full)
        return result
    }
}

private enum InlineMarkup {
    static func attributed(from text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("**"), let close = text.range(of: "**", range: text.index(index, offsetBy: 2)..<text.endIndex) {
                let inner = String(text[text.index(index, offsetBy: 2)..<close.lowerBound])
                result.append(styled(inner, font: font, color: color, trait: .traitBold, highlight: false))
                index = close.upperBound
                continue
            }
            if text[index...].hasPrefix("=="), let close = text.range(of: "==", range: text.index(index, offsetBy: 2)..<text.endIndex) {
                let inner = String(text[text.index(index, offsetBy: 2)..<close.lowerBound])
                result.append(styled(inner, font: font, color: color, trait: nil, highlight: true))
                index = close.upperBound
                continue
            }
            if text[index] == "*", let close = text[text.index(after: index)...].firstIndex(of: "*"), close > text.index(after: index) {
                let inner = String(text[text.index(after: index)..<close])
                result.append(styled(inner, font: font, color: color, trait: .traitItalic, highlight: false))
                index = text.index(after: close)
                continue
            }
            let next = text.index(after: index)
            result.append(styled(String(text[index..<next]), font: font, color: color, trait: nil, highlight: false))
            index = next
        }
        return result
    }

    private static func styled(
        _ text: String,
        font: UIFont,
        color: UIColor,
        trait: UIFontDescriptor.SymbolicTraits?,
        highlight: Bool
    ) -> NSAttributedString {
        var styledFont = font
        if let trait, let descriptor = font.fontDescriptor.withSymbolicTraits(
            font.fontDescriptor.symbolicTraits.union(trait)
        ) {
            styledFont = UIFont(descriptor: descriptor, size: font.pointSize)
        }
        var attributes: [NSAttributedString.Key: Any] = [.font: styledFont, .foregroundColor: color]
        if highlight {
            attributes[.backgroundColor] = UIColor.systemYellow.withAlphaComponent(0.32)
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}

final class SelfSizingTextView: UITextView {
    private var lastMeasuredWidth: CGFloat = 0

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 48
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(30, ceil(size.height)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0, abs(bounds.width - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

struct RichTextEditor: UIViewRepresentable {
    @Binding var richText: RichText
    var font: UIFont
    var textColor: UIColor = .label
    var placeholder: String = ""
    var context: RichTextEditingContext
    var onTyping: () -> Void = {}
    var onFocus: () -> Void = {}
    var onRequestInternalLink: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context coordinator: Context) -> SelfSizingTextView {
        let view = SelfSizingTextView()
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.delegate = coordinator.coordinator
        view.text = richText.plain
        view.attributedText = RichTextCoding.attributedString(from: richText, font: font, color: textColor)
        view.typingAttributes = [.font: font, .foregroundColor: textColor]
        view.textColor = textColor
        view.tintColor = UIColor(LumenTheme.accent)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = placeholder.isEmpty ? "正文" : placeholder
        return view
    }

    func updateUIView(_ view: SelfSizingTextView, context coordinator: Context) {
        coordinator.coordinator.parent = self
        guard !coordinator.coordinator.isApplyingExternalUpdate else { return }
        let expected = RichTextCoding.attributedString(from: richText, font: font, color: textColor)
        let previousFont = coordinator.coordinator.lastFont
        let fontChanged = previousFont == nil ||
            !(previousFont?.fontDescriptor.isEqual(font.fontDescriptor) ?? false)
        let styleChanged = coordinator.coordinator.lastStyle != view.traitCollection.userInterfaceStyle
        if fontChanged || styleChanged || view.attributedText.string != expected.string {
            coordinator.coordinator.isApplyingExternalUpdate = true
            let selected = view.selectedRange
            view.attributedText = expected
            if selected.location <= view.attributedText.length {
                view.selectedRange = selected
            }
            view.typingAttributes = [.font: font, .foregroundColor: textColor]
            coordinator.coordinator.isApplyingExternalUpdate = false
            coordinator.coordinator.lastFont = font
            coordinator.coordinator.lastStyle = view.traitCollection.userInterfaceStyle
        }
        view.textColor = textColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SelfSizingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 48
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(30, ceil(size.height)))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        var isApplyingExternalUpdate = false
        var lastFont: UIFont?
        var lastStyle: UIUserInterfaceStyle?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.context.focus(textView)
            parent.onFocus()
            parent.context.onChange = { [weak self] attributed in
                self?.apply(attributed, to: textView)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.context.textView === textView {
                parent.context.onChange = nil
                parent.context.focus(nil)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if parent.context.textView === textView {
                parent.context.refreshState()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingExternalUpdate else { return }
            var text = textView.text ?? ""
            if text.hasSuffix(">>") {
                text.removeLast(2)
                textView.text = text
                parent.onRequestInternalLink()
            }
            parent.richText.plain = text
            parent.richText.rtf = RichTextCoding.rtfData(from: textView.attributedText)
            textView.invalidateIntrinsicContentSize()
            parent.onTyping()
            if parent.context.textView === textView {
                parent.context.refreshState()
            }
        }

        private func apply(_ attributed: NSAttributedString, to textView: UITextView) {
            isApplyingExternalUpdate = true
            let selected = textView.selectedRange
            textView.attributedText = attributed
            if selected.location <= attributed.length {
                textView.selectedRange = selected
            }
            isApplyingExternalUpdate = false
            parent.richText.plain = textView.text
            parent.richText.rtf = RichTextCoding.rtfData(from: textView.attributedText)
            parent.onTyping()
        }
    }
}
