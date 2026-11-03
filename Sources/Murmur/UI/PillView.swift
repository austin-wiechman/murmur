import SwiftUI
import MurmurEngine

/// The recording pill: a Liquid Glass capsule that morphs between states.
struct PillView: View {
    var store: PillStore
    var meter: PillMeter
    weak var actions: AppActions?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            content
                .padding(.horizontal, horizontalPadding)
                .frame(height: 34)
                .frame(minWidth: 34)
                .foregroundStyle(.white)
                .background {
                    Capsule().fill(Theme.pillScrim)
                    if isCleaning { AuroraGlow(animated: !reduceMotion) }
                }
                .glassEffect(.regular.tint(Theme.pillTint), in: Capsule())
                .environment(\.colorScheme, .dark)
                .overlay {
                    SpecularRim()
                    if isCleaning { AuroraRim(animated: !reduceMotion) }
                }
                .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78), value: store.state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var isCleaning: Bool {
        if case .cleaning = store.state { return true }
        return false
    }

    private var horizontalPadding: CGFloat {
        switch store.state {
        case .inserted: 0
        case .locked: 6
        default: 14
        }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .hidden:
            EmptyView()
        case .listening(let heard):
            HStack(spacing: 11) {
                VoiceBars(levels: meter.levels, heard: heard, animated: !reduceMotion)
                if !meter.liveWords.isEmpty { LiveWords(text: meter.liveWords) }
            }
        case .locked(let heard):
            HStack(spacing: 9) {
                PillButton(label: "Cancel (Esc)") { actions?.cancelDictation() } icon: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                VoiceBars(levels: meter.levels, heard: heard, animated: !reduceMotion)
                if !meter.liveWords.isEmpty { LiveWords(text: meter.liveWords) }
                PillButton(label: "Stop and insert", prominent: true) { actions?.stopLocked() } icon: {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).frame(width: 8, height: 8)
                        .foregroundStyle(.black)
                }
            }
        case .transcribing:
            RollingDots(animated: !reduceMotion)
        case .cleaning:
            HStack(spacing: 8) {
                ShimmerText(text: "Cleaning up", animated: !reduceMotion)
                Sparkle()
                    .fill(LinearGradient(colors: Theme.aurora, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 15, height: 15)
                    .modifier(Twinkle(animated: !reduceMotion))
            }
        case .inserted(_, let canUndo):
            if canUndo {
                HStack(spacing: 8) {
                    CheckMark()
                    KeyCap(text: "⌃⌘Z")
                    Text("for your exact words").font(.system(size: 13, weight: .medium)).opacity(0.78)
                }
                .padding(.horizontal, 12)
            } else {
                CheckMark().frame(width: 34)
            }
        case .failure(let failure):
            FailureContent(failure: failure)
        }
    }

    private var accessibilityText: String {
        switch store.state {
        case .hidden: ""
        case .listening: "Listening"
        case .locked: "Listening hands-free"
        case .transcribing: "Transcribing"
        case .cleaning: "Cleaning up"
        case .inserted: "Inserted"
        case .failure(let f): FailureContent.text(for: f).joined(separator: " ")
        }
    }
}

// MARK: - Bars

/// The newest level drives the centre bar and older levels move outward.
struct VoiceBars: View {
    var levels: [Float]
    var heard: Bool
    var animated: Bool

    private static let weights: [CGFloat] = [0.32, 0.46, 0.62, 0.78, 0.92, 1, 0.92, 0.78, 0.62, 0.46, 0.32]

    var body: some View {
        if heard {
            HStack(spacing: 3) {
                ForEach(0..<11, id: \.self) { i in
                    Capsule().frame(width: 3, height: height(i))
                }
            }
            .frame(height: 20)
            .animation(animated ? .spring(response: 0.2, dampingFraction: 0.85) : nil, value: levels)
        } else {
            BreathingDots(animated: animated)
        }
    }

    private func height(_ i: Int) -> CGFloat {
        let distance = abs(i - 5)
        let index = max(0, levels.count - 1 - distance)
        let level = levels.isEmpty ? 0 : CGFloat(min(1, max(0, levels[index])))
        let shaped = pow(level, 0.6)
        return 3 + 17 * shaped * Self.weights[i]
    }
}

struct BreathingDots: View {
    var animated: Bool
    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<11, id: \.self) { i in
                    let phase = sin(t * 2.4 - Double(abs(i - 5)) * 0.55)
                    Circle()
                        .frame(width: 3.5, height: 3.5)
                        .opacity(animated ? 0.8 + 0.2 * phase : 0.9)
                }
            }
            .frame(height: 20)
        }
    }
}

struct RollingDots: View {
    var animated: Bool
    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<11, id: \.self) { i in
                    let wave = sin(t * 7 - Double(i) * 0.62)
                    Circle()
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: animated ? -3.2 * max(0, wave) : 0)
                        .opacity(animated ? 0.6 + 0.4 * max(0, wave) : 0.85)
                }
            }
            .frame(height: 20)
        }
    }
}

// MARK: - Cleaning

/// A thin highlight along the top edge and a fainter one along the bottom, like light on a lens.
struct SpecularRim: View {
    var body: some View {
        Capsule()
            .strokeBorder(LinearGradient(stops: [
                .init(color: .white.opacity(0.55), location: 0),
                .init(color: .white.opacity(0.08), location: 0.45),
                .init(color: .white.opacity(0.0), location: 0.6),
                .init(color: .white.opacity(0.22), location: 1),
            ], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            .allowsHitTesting(false)
    }
}

struct AuroraRim: View {
    var animated: Bool
    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            let angle = Angle.degrees(animated ? context.date.timeIntervalSinceReferenceDate * 115 : 30)
            let stops = Theme.auroraRimStops
            Rectangle()
                .fill(AngularGradient(colors: stops, center: .center, startAngle: angle, endAngle: angle + .degrees(360)))
                .mask(Capsule().strokeBorder(lineWidth: 1.5))
        }
        .allowsHitTesting(false)
    }
}

/// Soft coloured light inside the glass while cleanup runs, kept under the text.
struct AuroraGlow: View {
    var animated: Bool
    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            let angle = Angle.degrees(animated ? context.date.timeIntervalSinceReferenceDate * 80 : 30)
            Capsule()
                .fill(AngularGradient(colors: Theme.auroraLoop, center: .center,
                                      startAngle: angle, endAngle: angle + .degrees(360)))
                .blur(radius: 10)
                .opacity(0.3)
                .clipShape(Capsule())
        }
        .allowsHitTesting(false)
    }
}

struct ShimmerText: View {
    var text: String
    var animated: Bool
    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let x = animated ? (t.truncatingRemainder(dividingBy: 2.2) / 2.2) * 2.4 - 0.7 : 0.5
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.86), location: 0),
                        .init(color: .white.opacity(0.86), location: max(0, x - 0.25)),
                        .init(color: .white, location: min(1, max(0, x))),
                        .init(color: .white.opacity(0.86), location: min(1, x + 0.25)),
                        .init(color: .white.opacity(0.86), location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                .fixedSize()
        }
    }
}

struct Twinkle: ViewModifier {
    var animated: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.06 : 0.86)
            .rotationEffect(.degrees(on ? 45 : 0))
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Inserted, failures, controls

struct CheckMark: View {
    @State private var drawn = false
    var body: some View {
        CheckShape()
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 16)
            .onAppear { withAnimation(.easeOut(duration: 0.32).delay(0.05)) { drawn = true } }
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.width * 0.41, y: rect.height * 0.71))
        p.addLine(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.30))
        return p
    }
}

struct FailureContent: View {
    var failure: PillState.Failure

    static func text(for failure: PillState.Failure) -> [String] {
        switch failure {
        case .noAudio(let device):
            ["No audio.", device.map { "Is \($0) muted?" } ?? "Is your mic muted?"]
        case .pasteBlocked: ["Copied instead.", "⌘V", "to paste"]
        case .modelLoading: ["Getting the speech model ready", ""]
        case .microphoneDenied: ["Mic access is off.", "Allow it in System Settings"]
        case .other(let message): [message, ""]
        }
    }

    var body: some View {
        let parts = Self.text(for: failure)
        HStack(spacing: 8) {
            icon
            Text(parts[0]).font(.system(size: 13, weight: .semibold))
            if case .pasteBlocked = failure {
                KeyCap(text: parts[1])
                Text(parts[2]).font(.system(size: 13, weight: .medium)).opacity(0.78)
            } else if !parts[1].isEmpty {
                Text(parts[1]).font(.system(size: 13, weight: .medium)).opacity(0.78)
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var icon: some View {
        switch failure {
        case .noAudio, .microphoneDenied:
            Image(systemName: "mic.slash").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.coral)
        case .pasteBlocked:
            Image(systemName: "doc.on.clipboard").font(.system(size: 12, weight: .semibold))
        case .modelLoading:
            WhiteSpinner()
        case .other:
            Image(systemName: "exclamationmark.circle").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.coral)
        }
    }
}

struct PillButton<Icon: View>: View {
    var label: String
    var prominent = false
    var action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 22, height: 22)
                .background(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.18)), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct LiveWords: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .fixedSize()
            .opacity(0.86)
            .frame(width: 230, alignment: .trailing)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15)],
                                 startPoint: .leading, endPoint: .trailing))
    }
}

/// macOS draws `ProgressView` grey and ignores `tint`, which reads as disabled on the dark pill.
struct WhiteSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
        }
        .accessibilityLabel("Loading")
    }
}
