import SwiftUI
import UIKit

/// Wraps neighbouring glass controls so they can blend/morph. On iOS 26 this is
/// a real `GlassEffectContainer`; on older SDKs it is a transparent passthrough.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

struct GlassSurfaceModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @Environment(\.accessibilityContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else if contrast == .increased {
            content
                .background(Color(uiColor: .secondarySystemBackground), in: shape)
                .overlay(shape.stroke(Color(uiColor: .separator), lineWidth: 0.5))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color(uiColor: .separator), lineWidth: 0.5))
        }
    }
}

extension View {
    /// Apply only to navigation / control surfaces, never to content.
    func lumenGlass<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, interactive: interactive))
    }

    /// A modal/control container (font panel, recording panel). Not clickable
    /// itself, therefore not `.interactive()`.
    func glassPanel(cornerRadius: CGFloat = 28) -> some View {
        lumenGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: false)
    }
}

struct GlassIconButton: View {
    let systemName: String
    let label: String
    var tint: Color = .primary
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    icon
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            } else {
                Button(action: action) {
                    icon
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color(uiColor: .separator), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var icon: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? tint : Color.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

struct GlassCapsuleButton: View {
    let title: String
    var systemName: String?
    var tint: Color = .primary
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                if prominent {
                    Button(action: action) { label }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                } else {
                    Button(action: action) { label }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            } else {
                Button(action: action) {
                    label
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color(uiColor: .separator), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 7) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.footnote.weight(.semibold))
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .contentShape(Capsule())
    }
}

struct GlassSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
