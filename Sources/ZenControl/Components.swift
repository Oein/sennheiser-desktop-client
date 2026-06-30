import SwiftUI

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 0.10, green: 0.55, blue: 0.78)   // Sennheiser-ish teal/blue
    static let corner: CGFloat = 14
    static let windowWidth: CGFloat = 460
}

extension View {
    /// Elevated card surface used for every settings group.
    func card(_ padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }
}

// MARK: - Section card

struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var accessory: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let accessory { accessory }
            }
            content()
        }
        .card()
    }
}

// MARK: - Setting row (icon + label + trailing control)

struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var enabled: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: - Battery badge

struct BatteryBadge: View {
    let percent: Int
    private var color: Color {
        switch percent { case ..<15: return .red; case ..<35: return .orange; default: return .green }
    }
    private var symbol: String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text("\(percent)%").font(.callout.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Status dot

struct StatusDot: View {
    let connected: Bool
    var body: some View {
        Circle()
            .fill(connected ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - Mode card button (for the noise-control picker)

struct ModeButton: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.accent : Color.primary.opacity(0.06))
            )
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - EQ curve

struct EQCurve: View {
    let gains: [Float]
    let limit: Float

    var body: some View {
        Canvas { ctx, size in
            guard gains.count > 1 else { return }
            let w = size.width, h = size.height
            func point(_ i: Int) -> CGPoint {
                let x = w * CGFloat(i) / CGFloat(gains.count - 1)
                let norm = (CGFloat(gains[i]) + CGFloat(limit)) / (2 * CGFloat(limit)) // 0..1
                let y = h - norm * h
                return CGPoint(x: x, y: y)
            }
            // zero line
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: h / 2)); zero.addLine(to: CGPoint(x: w, y: h / 2))
            ctx.stroke(zero, with: .color(.primary.opacity(0.12)), style: .init(lineWidth: 1, dash: [3, 3]))
            // smooth curve
            var path = Path()
            path.move(to: point(0))
            for i in 1..<gains.count {
                let p0 = point(i - 1), p1 = point(i)
                let midX = (p0.x + p1.x) / 2
                path.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))
            }
            // fill under curve
            var fill = path
            fill.addLine(to: CGPoint(x: w, y: h)); fill.addLine(to: CGPoint(x: 0, y: h)); fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(path, with: .color(Theme.accent), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            // band dots
            for i in 0..<gains.count {
                let p = point(i)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                         with: .color(Theme.accent))
            }
        }
        .frame(height: 70)
        .animation(.easeOut(duration: 0.2), value: gains)
    }
}
