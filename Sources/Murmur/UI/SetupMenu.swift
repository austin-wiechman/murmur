import MurmurCore
import MurmurEngine
import SwiftUI

/// The menu while setup is unfinished: one row per step, with the next step's button in the accent color.
struct SetupMenu: View {
    var prefs: Preferences
    var status: StatusStore
    weak var actions: AppActions?
    var confirming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                checklist.opacity(confirming ? 0 : 1)
                if confirming { ReadyConfirmation(hint: prefs.shortcutHint) }
            }
            .padding(14)
            Divider().padding(.horizontal, 12)
            MenuRow(title: "Quit Murmur", shortcut: "⌘Q") { actions?.quit() }.padding(6)
        }
    }

    private var setup: Setup { status.setup }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Set up Murmur").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(setup.completedSteps) of \(Setup.Step.allCases.count) done")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(Setup.Step.allCases, id: \.self) { step in
                HStack(alignment: .top, spacing: 10) {
                    StepDot(state: setup.isDone(step) ? .done : step == setup.nextStep ? .next : .waiting)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(step)).fontWeight(step == setup.nextStep ? .semibold : .regular)
                        detail(step)
                    }
                    Spacer(minLength: 8)
                    if !setup.isDone(step), let label = buttonTitle(step) {
                        StepButton(label: label, prominent: step == setup.nextStep) { act(step) }
                    }
                }
            }
        }
        .font(.system(size: 13))
    }

    private func title(_ step: Setup.Step) -> String {
        switch step {
        case .accessibility: "Accessibility"
        case .microphone: "Microphone"
        case .updates: "Updates"
        case .speechModel: "Speech model"
        }
    }

    @ViewBuilder private func detail(_ step: Setup.Step) -> some View {
        switch step {
        case .accessibility:
            caption(setup.accessibility ? "Shortcuts and pasting work" : "Needed for your shortcuts and to paste")
        case .microphone:
            caption("Audio stays on this Mac")
        case .updates where setup.updatesAnswered:
            caption(status.automaticUpdates ? "Checks automatically" : "Only when you ask")
        case .updates:
            caption("Check for new versions automatically?")
            HStack(spacing: 6) {
                StepButton(label: "Automatically", prominent: setup.nextStep == .updates) { status.setAutomaticUpdates(true) }
                StepButton(label: "Only when I ask", prominent: false) { status.setAutomaticUpdates(false) }
            }
            .padding(.top, 4)
        case .speechModel where setup.speechModelReady:
            caption("Downloaded")
        case .speechModel:
            modelProgress
        }
    }

    @ViewBuilder private var modelProgress: some View {
        switch status.modelProgress {
        case .downloading(let fraction):
            ProgressView(value: fraction).controlSize(.small).padding(.top, 3)
            caption("Downloading, \(Int(fraction * 100))% of about 580 MB")
        case .preparing:
            ProgressView().progressViewStyle(.linear).controlSize(.small).padding(.top, 3)
            caption("Preparing for the Neural Engine")
        case nil:
            ProgressView().progressViewStyle(.linear).controlSize(.small).padding(.top, 3)
            caption("Loading")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
    }

    private func buttonTitle(_ step: Setup.Step) -> String? {
        switch step {
        case .accessibility, .microphone: "Allow"
        case .updates, .speechModel: nil
        }
    }

    private func act(_ step: Setup.Step) {
        switch step {
        case .accessibility: actions?.grant(.accessibility)
        case .microphone: actions?.grant(.microphone)
        case .updates, .speechModel: break
        }
    }
}

private struct StepButton: View {
    var label: String
    var prominent: Bool
    var action: () -> Void

    var body: some View {
        if prominent {
            Button(label, action: action).buttonStyle(.borderedProminent).controlSize(.small)
        } else {
            Button(label, action: action).buttonStyle(.bordered).controlSize(.small)
        }
    }
}

private struct StepDot: View {
    enum State { case done, next, waiting }
    var state: State

    var body: some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(.green)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            case .next:
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                Circle().fill(Color.accentColor).padding(4.5)
            case .waiting:
                Circle().strokeBorder(.secondary, lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .animation(.spring(duration: 0.3, bounce: 0.4), value: state)
    }
}

/// A green circle draws itself, then the check strokes in.
private struct ReadyConfirmation: View {
    var hint: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var tick: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().trim(from: 0, to: ring)
                    .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                CheckShape().trim(from: 0, to: tick)
                    .stroke(.green, style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
                    .padding(15)
            }
            .frame(width: 52, height: 52)
            Text("Murmur is ready").font(.system(size: 15, weight: .semibold))
            Text(hint + ".").font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .onAppear {
            if reduceMotion {
                ring = 1
                tick = 1
                return
            }
            withAnimation(.easeInOut(duration: 0.55)) { ring = 1 }
            withAnimation(.easeOut(duration: 0.3).delay(0.45)) { tick = 1 }
        }
    }
}
