import SwiftUI

enum FrameCutColors {
    static let canvas = Color(red: 0.043, green: 0.051, blue: 0.071)
    static let toolbar = Color(red: 0.059, green: 0.067, blue: 0.090)
    static let panel = Color(red: 0.071, green: 0.082, blue: 0.110)
    static let elevated = Color(red: 0.090, green: 0.102, blue: 0.137)
    static let player = Color(red: 0.018, green: 0.021, blue: 0.029)
    static let border = Color.white.opacity(0.09)
    static let borderStrong = Color.white.opacity(0.16)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.40)
    static let accent = Color(red: 0.486, green: 0.549, blue: 1.0)
    static let accentBright = Color(red: 0.612, green: 0.659, blue: 1.0)
    static let success = Color(red: 0.286, green: 0.788, blue: 0.541)
    static let warning = Color(red: 0.941, green: 0.702, blue: 0.353)
    static let danger = Color(red: 0.949, green: 0.388, blue: 0.424)
}

struct PanelSurface: ViewModifier {
    let radius: CGFloat
    let color: Color

    func body(content: Content) -> some View {
        content
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(FrameCutColors.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func panelSurface(radius: CGFloat = 10, color: Color = FrameCutColors.panel) -> some View {
        modifier(PanelSurface(radius: radius, color: color))
    }
}

struct ToolbarActionButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.white : FrameCutColors.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isPrimary
                            ? FrameCutColors.accent.opacity(configuration.isPressed ? 0.72 : 1)
                            : Color.white.opacity(configuration.isPressed ? 0.11 : 0.065)
                    )
            }
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(FrameCutColors.borderStrong, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TransportButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? Color.white : FrameCutColors.primaryText)
            .padding(.horizontal, isPrimary ? 18 : 12)
            .frame(height: isPrimary ? 42 : 38)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isPrimary
                            ? FrameCutColors.accent.opacity(configuration.isPressed ? 0.75 : 1)
                            : Color.white.opacity(configuration.isPressed ? 0.10 : 0.055)
                    )
            }
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(FrameCutColors.border, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ShortcutBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(FrameCutColors.tertiaryText)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(FrameCutColors.border, lineWidth: 1)
            }
    }
}

struct SectionLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(FrameCutColors.secondaryText)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FrameCutColors.tertiaryText)
            }
        }
    }
}
