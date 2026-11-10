import SwiftUI
import UIKit

enum LumenTheme {
    static let accent = Color(red: 0.29, green: 0.42, blue: 0.98)
    static let accentSecondary = Color(red: 0.53, green: 0.36, blue: 0.98)
    static let warm = Color(red: 0.98, green: 0.72, blue: 0.28)

    static func contentBackground(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.065, blue: 0.095),
                    Color(red: 0.08, green: 0.075, blue: 0.12),
                    Color(red: 0.045, green: 0.05, blue: 0.075)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.985, green: 0.975, blue: 0.955),
                Color(red: 0.965, green: 0.972, blue: 0.995),
                Color(red: 0.985, green: 0.965, blue: 0.945)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let cardRadius: CGFloat = 22
}

struct LumenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LumenTheme.contentBackground(for: colorScheme)
            Circle()
                .fill(LumenTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -160, y: -260)
            Circle()
                .fill(LumenTheme.warm.opacity(colorScheme == .dark ? 0.10 : 0.13))
                .frame(width: 280, height: 280)
                .blur(radius: 100)
                .offset(x: 170, y: 300)
        }
        .ignoresSafeArea()
    }
}

/// A content surface. Deliberately *not* glass: rows, editor paper, attachment
/// cards and tables must remain opaque for legibility.
struct ContentSurface: ViewModifier {
    var radius: CGFloat = LumenTheme.cardRadius
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.55), lineWidth: 0.5)
            )
    }
}

extension View {
    func contentSurface(radius: CGFloat = LumenTheme.cardRadius, padding: CGFloat = 16) -> some View {
        modifier(ContentSurface(radius: radius, padding: padding))
    }

    func lumenContentPadding() -> some View {
        padding(.horizontal, 20)
    }
}

@MainActor
struct TagChip: View {
    @Environment(FontTheme.self) private var theme
    let name: String
    var isSelected = false

    var body: some View {
        Text("#\(name)")
            .font(theme.font(for: .caption).weight(.medium))
            .foregroundStyle(isSelected ? Color.white : LumenTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? LumenTheme.accent : LumenTheme.accent.opacity(0.11))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(LumenTheme.accent.opacity(isSelected ? 0 : 0.20), lineWidth: 0.5)
            )
    }
}

struct AttachmentGlyph: View {
    let kind: AttachmentKind

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(LumenTheme.accent)
            .frame(width: 22, height: 22)
            .background(LumenTheme.accent.opacity(0.12), in: Circle())
    }
}

extension Date {
    var lumenRelative: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return self.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(self) { return "昨天" }
        if let days = calendar.dateComponents([.day], from: self, to: .now).day, days < 7 {
            return "\(days) 天前"
        }
        return self.formatted(date: .abbreviated, time: .omitted)
    }
}
