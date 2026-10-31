import SwiftUI

enum MiseTheme {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 18/255, green: 17/255, blue: 15/255, alpha: 1)
            : UIColor(red: 247/255, green: 243/255, blue: 234/255, alpha: 1)
    })

    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 29/255, green: 28/255, blue: 24/255, alpha: 1)
            : UIColor(red: 1, green: 253/255, blue: 248/255, alpha: 1)
    })

    static let raisedSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 40/255, green: 38/255, blue: 32/255, alpha: 1)
            : UIColor(red: 242/255, green: 236/255, blue: 225/255, alpha: 1)
    })

    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 242/255, green: 238/255, blue: 228/255, alpha: 1)
            : UIColor(red: 29/255, green: 36/255, blue: 30/255, alpha: 1)
    })

    static let secondaryInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 168/255, green: 163/255, blue: 151/255, alpha: 1)
            : UIColor(red: 107/255, green: 106/255, blue: 96/255, alpha: 1)
    })

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 214/255, green: 132/255, blue: 94/255, alpha: 1)
            : UIColor(red: 160/255, green: 70/255, blue: 38/255, alpha: 1)
    })

    static let sage = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 143/255, green: 166/255, blue: 137/255, alpha: 1)
            : UIColor(red: 83/255, green: 107/255, blue: 82/255, alpha: 1)
    })

    static let line = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 48/255, green: 46/255, blue: 40/255, alpha: 1)
            : UIColor(red: 229/255, green: 222/255, blue: 209/255, alpha: 1)
    })

    static let warning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 224/255, green: 177/255, blue: 102/255, alpha: 1)
            : UIColor(red: 154/255, green: 107/255, blue: 36/255, alpha: 1)
    })

    static let positive = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 133/255, green: 179/255, blue: 123/255, alpha: 1)
            : UIColor(red: 63/255, green: 112/255, blue: 68/255, alpha: 1)
    })
}

extension Font {
    static func miseDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(.title2, design: .serif, weight: weight)
    }

    static let miseEyebrow = Font.system(.caption, design: .default, weight: .semibold)
}

struct PageBackground: View {
    var body: some View {
        MiseTheme.background.ignoresSafeArea()
    }
}

struct MiseDivider: View {
    var body: some View {
        Rectangle().fill(MiseTheme.line).frame(height: 1)
    }
}

struct SectionHeading: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.miseDisplay(24))
                .foregroundStyle(MiseTheme.ink)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MiseTheme.accent)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                    .accessibilityHint("Shows all \(title.lowercased())")
            }
        }
    }
}

struct TagChip: View {
    let text: String
    var highlighted: Bool = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(highlighted ? MiseTheme.accent : MiseTheme.secondaryInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(highlighted ? MiseTheme.accent.opacity(0.11) : MiseTheme.raisedSurface)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = MiseTheme.ink
    var foreground: Color = MiseTheme.background

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(MiseTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MiseTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MiseTheme.line, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(MiseTheme.sage)
                .frame(width: 68, height: 68)
                .background(Circle().fill(MiseTheme.raisedSurface))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(MiseTheme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(MiseTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle(fill: MiseTheme.accent))
                    .padding(.top, 4)
                    .frame(maxWidth: 260)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

struct InlineNotice: View {
    enum Style {
        case info
        case warning
        case success
        case error

        var symbol: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .success: return "checkmark.circle"
            case .error: return "xmark.octagon"
            }
        }

        var color: Color {
            switch self {
            case .info: return MiseTheme.sage
            case .warning: return MiseTheme.warning
            case .success: return MiseTheme.positive
            case .error: return MiseTheme.accent
            }
        }
    }

    let style: Style
    let message: String
    var title: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.symbol)
                .foregroundStyle(style.color)
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(MiseTheme.ink)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(MiseTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.color.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.color.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct FieldLabel: View {
    let text: String
    var optional: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(MiseTheme.secondaryInk)
            if optional {
                Text("Optional")
                    .font(.caption2)
                    .foregroundStyle(MiseTheme.secondaryInk.opacity(0.8))
            }
        }
    }
}

struct Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
