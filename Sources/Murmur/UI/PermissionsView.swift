import AVFoundation
import SwiftUI

/// One row per permission: what it's for, whether it's on, and a button that fixes it.
struct PermissionRows: View {
    var status: StatusStore
    weak var actions: AppActions?

    var body: some View {
        ForEach(Permission.allCases) { permission in
            // An HStack, not LabeledContent: a Form aligns LabeledContent's button with the title's
            // baseline, which leaves it above center when the detail line is long.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(permission))
                    Text(detail(permission)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if granted(permission) {
                    Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button(buttonTitle(permission)) { actions?.grant(permission) }
                }
            }
        }
    }

    private func granted(_ permission: Permission) -> Bool {
        !status.missingPermissions.contains(permission)
    }

    private func title(_ permission: Permission) -> String {
        permission == .accessibility ? "Accessibility" : "Microphone"
    }

    private func detail(_ permission: Permission) -> String {
        switch permission {
        case .accessibility:
            granted(permission) ? "Your shortcuts work in every app, and text is pasted for you"
                : "Needed for your shortcuts and to paste. Turn on Murmur in the list."
        case .microphone:
            "Needed to hear you. Audio stays on this Mac."
        }
    }

    private func buttonTitle(_ permission: Permission) -> String {
        if permission == .microphone && status.microphone == .notDetermined { return "Allow" }
        if permission == .accessibility { return "Allow" }
        return "Open System Settings"
    }
}
