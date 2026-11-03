import SwiftUI

enum Theme {
    static let aurora: [Color] = [
        Color(red: 0x3E / 255, green: 0xE6 / 255, blue: 0xC8 / 255),
        Color(red: 0x5A / 255, green: 0xA9 / 255, blue: 0xFF / 255),
        Color(red: 0x9C / 255, green: 0x7C / 255, blue: 0xFF / 255),
        Color(red: 0xF3 / 255, green: 0x9B / 255, blue: 0xFF / 255),
    ]
    static let accent = Color(red: 0x8F / 255, green: 0xB7 / 255, blue: 0xFF / 255)
    static let coral = Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0x7A / 255)

    /// Glass goes near-white over a white page and its tint alone doesn't hold, leaving white text
    /// at ~1.5:1. A scrim under the content keeps white text above 4.5:1 on any backdrop.
    static let pillTint = Color.black.opacity(0.5)
    static let pillScrim = Color.black.opacity(0.55)

    /// The aurora closed into a loop, for angular gradients.
    static let auroraLoop = aurora + [aurora[0]]
    static let auroraRimStops = aurora + [.white.opacity(0.12), .white.opacity(0.12), aurora[0]]
}

/// The four-point sparkle used for cleanup.
struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let k = r * 0.16
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}

struct KeyCap: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
