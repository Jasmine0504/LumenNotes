import Foundation
import Observation
import SwiftUI
import UIKit

enum TextRole: String, CaseIterable, Codable, Hashable, Sendable {
    case title, body, caption

    var displayName: String {
        switch self {
        case .title: "标题"
        case .body: "正文"
        case .caption: "辅助文本"
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .title: .largeTitle
        case .body: .body
        case .caption: .footnote
        }
    }

    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .title: .largeTitle
        case .body: .body
        case .caption: .footnote
        }
    }
}

enum FontFamily: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case sfPro, sfMono, newYork, georgia, palatino, pingFang

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sfPro: "SF Pro"
        case .sfMono: "SF Mono"
        case .newYork: "New York"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .pingFang: "PingFang SC"
        }
    }

    var subtitle: String {
        switch self {
        case .sfPro: "系统无衬线 · 清晰"
        case .sfMono: "等宽 · 代码与清单"
        case .newYork: "Apple 衬线 · 阅读"
        case .georgia: "经典衬线 · 手感"
        case .palatino: "人文衬线 · 优雅"
        case .pingFang: "中文黑体 · 细/常规/粗"
        }
    }

    var supportsChinese: Bool {
        switch self {
        case .sfPro, .pingFang: true
        default: false
        }
    }

    var fallbackDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .sfPro, .pingFang: .default
        case .sfMono: .monospaced
        case .newYork, .georgia, .palatino: .serif
        }
    }

    func postScriptName(for weight: FontWeightChoice) -> String {
        switch self {
        case .sfPro:
            switch weight {
            case .light: "SFProText-Light"
            case .regular: "SFProText-Regular"
            case .semibold: "SFProText-Semibold"
            case .bold: "SFProText-Bold"
            }
        case .sfMono:
            switch weight {
            case .light: "SFMono-Light"
            case .regular: "SFMono-Regular"
            case .semibold: "SFMono-Semibold"
            case .bold: "SFMono-Bold"
            }
        case .newYork:
            switch weight {
            case .light: "NewYork-Light"
            case .regular: "NewYork-Regular"
            case .semibold: "NewYork-Semibold"
            case .bold: "NewYork-Bold"
            }
        case .georgia:
            switch weight {
            case .light, .regular: "Georgia"
            case .semibold, .bold: "Georgia-Bold"
            }
        case .palatino:
            switch weight {
            case .light, .regular: "Palatino-Roman"
            case .semibold, .bold: "Palatino-Bold"
            }
        case .pingFang:
            switch weight {
            case .light: "PingFangSC-Light"
            case .regular: "PingFangSC-Regular"
            case .semibold: "PingFangSC-Semibold"
            case .bold: "PingFangSC-Semibold"
            }
        }
    }
}

enum FontWeightChoice: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case light, regular, semibold, bold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: "细"
        case .regular: "常规"
        case .semibold: "中粗"
        case .bold: "粗"
        }
    }

    var uiWeight: UIFont.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

struct NoteFontOverride: Codable, Hashable, Sendable {
    var family: FontFamily?
    var weight: FontWeightChoice?
    var titleSize: Double?
    var bodySize: Double?
    var captionSize: Double?
    var followDynamicType: Bool?

    init(
        family: FontFamily? = nil,
        weight: FontWeightChoice? = nil,
        titleSize: Double? = nil,
        bodySize: Double? = nil,
        captionSize: Double? = nil,
        followDynamicType: Bool? = nil
    ) {
        self.family = family
        self.weight = weight
        self.titleSize = titleSize
        self.bodySize = bodySize
        self.captionSize = captionSize
        self.followDynamicType = followDynamicType
    }

    var isEmpty: Bool {
        family == nil && weight == nil && titleSize == nil && bodySize == nil &&
        captionSize == nil && followDynamicType == nil
    }
}

@MainActor
@Observable
final class FontTheme {
    var family: FontFamily {
        didSet { persist() }
    }
    var weight: FontWeightChoice {
        didSet { persist() }
    }
    var titleSize: Double {
        didSet { titleSize = Self.clamp(titleSize); persist() }
    }
    var bodySize: Double {
        didSet { bodySize = Self.clamp(bodySize); persist() }
    }
    var captionSize: Double {
        didSet { captionSize = Self.clamp(captionSize); persist() }
    }
    var followDynamicType: Bool {
        didSet { persist() }
    }
    var lineSpacing: Double {
        didSet { lineSpacing = min(18, max(0, lineSpacing)); persist() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let storageKey = "lumen.fontTheme.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let snapshot = Self.load(from: defaults)
        self.family = snapshot?.family ?? .newYork
        self.weight = snapshot?.weight ?? .regular
        self.titleSize = snapshot?.titleSize ?? 28
        self.bodySize = snapshot?.bodySize ?? 17
        self.captionSize = snapshot?.captionSize ?? 13
        self.followDynamicType = snapshot?.followDynamicType ?? true
        self.lineSpacing = snapshot?.lineSpacing ?? 6
    }

    private static func clamp(_ value: Double) -> Double {
        min(32, max(12, value.rounded()))
    }

    func size(for role: TextRole, override: NoteFontOverride? = nil) -> Double {
        switch role {
        case .title: override?.titleSize ?? titleSize
        case .body: override?.bodySize ?? bodySize
        case .caption: override?.captionSize ?? captionSize
        }
    }

    func resolvedFamily(_ override: NoteFontOverride?) -> FontFamily {
        override?.family ?? family
    }

    func resolvedWeight(_ override: NoteFontOverride?) -> FontWeightChoice {
        override?.weight ?? weight
    }

    func resolvedDynamicType(_ override: NoteFontOverride?) -> Bool {
        override?.followDynamicType ?? followDynamicType
    }

    /// Every SwiftUI text style in the app goes through this function. Custom
    /// families use `Font.custom(_:size:relativeTo:)`; the Dynamic Type switch
    /// flips to `Font.custom(_:fixedSize:)` when the user wants strict sizing.
    func font(for role: TextRole, override: NoteFontOverride? = nil) -> Font {
        swiftUIFont(
            size: size(for: role, override: override),
            textStyle: role.textStyle,
            override: override
        )
    }

    func headingFont(level: Int, override: NoteFontOverride? = nil) -> Font {
        swiftUIFont(size: headingSize(level: level, override: override), textStyle: .title, override: override)
    }

    func headingUIFont(level: Int, override: NoteFontOverride? = nil) -> UIFont {
        makeUIFont(
            size: CGFloat(headingSize(level: level, override: override)),
            textStyle: .title,
            override: override
        )
    }

    func uiFont(for role: TextRole, override: NoteFontOverride? = nil) -> UIFont {
        makeUIFont(size: CGFloat(size(for: role, override: override)), textStyle: role.uiTextStyle, override: override)
    }

    private func headingSize(level: Int, override: NoteFontOverride?) -> Double {
        let base = size(for: .body, override: override)
        let title = size(for: .title, override: override)
        switch level {
        case 1: return title
        case 2: return min(32, max(12, base + 5))
        default: return min(32, max(12, base + 2))
        }
    }

    private func swiftUIFont(size: Double, textStyle: Font.TextStyle, override: NoteFontOverride?) -> Font {
        let family = resolvedFamily(override)
        let weight = resolvedWeight(override)
        let follows = resolvedDynamicType(override)
        let name = family.postScriptName(for: weight)
        if UIFont(name: name, size: CGFloat(size)) != nil {
            return follows
                ? .custom(name, size: CGFloat(size), relativeTo: textStyle)
                : .custom(name, fixedSize: CGFloat(size))
        }
        return Font(makeUIFont(size: CGFloat(size), textStyle: uiStyle(for: textStyle), override: override))
    }

    private func makeUIFont(size: CGFloat, textStyle: UIFont.TextStyle, override: NoteFontOverride?) -> UIFont {
        let family = resolvedFamily(override)
        let weight = resolvedWeight(override)
        let follows = resolvedDynamicType(override)
        let name = family.postScriptName(for: weight)

        var base: UIFont
        if let custom = UIFont(name: name, size: size) {
            base = custom
        } else {
            var descriptor = UIFont.systemFont(ofSize: size, weight: weight.uiWeight).fontDescriptor
            if let designed = descriptor.withDesign(family.fallbackDesign) {
                descriptor = designed
            }
            base = UIFont(descriptor: descriptor, size: size)
        }
        if follows {
            base = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        }
        return base
    }

    private func uiStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .body: .body
        case .footnote: .footnote
        default: .body
        }
    }

    func sampleFont(for family: FontFamily) -> Font {
        let override = NoteFontOverride(family: family, bodySize: 21, followDynamicType: false)
        return font(for: .body, override: override)
    }

    func reset() {
        family = .newYork
        weight = .regular
        titleSize = 28
        bodySize = 17
        captionSize = 13
        followDynamicType = true
        lineSpacing = 6
    }

    func makeOverride() -> NoteFontOverride {
        NoteFontOverride(
            family: family,
            weight: weight,
            titleSize: titleSize,
            bodySize: bodySize,
            captionSize: captionSize,
            followDynamicType: followDynamicType
        )
    }

    private func persist() {
        let snapshot = FontThemeSnapshot(
            family: family,
            weight: weight,
            titleSize: titleSize,
            bodySize: bodySize,
            captionSize: captionSize,
            followDynamicType: followDynamicType,
            lineSpacing: lineSpacing
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> FontThemeSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(FontThemeSnapshot.self, from: data)
    }
}

private struct FontThemeSnapshot: Codable {
    var family: FontFamily
    var weight: FontWeightChoice
    var titleSize: Double
    var bodySize: Double
    var captionSize: Double
    var followDynamicType: Bool
    var lineSpacing: Double
}
