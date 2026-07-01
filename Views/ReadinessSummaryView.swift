import SwiftUI

/// Compact banner shown above the launch controls in `BottleDetailView`.
/// Colour and icon track `state.report.status` so a quick glance tells the
/// user whether they can launch.
struct ReadinessSummaryView: View {
    let state: BottleLaunchState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.callout.bold())
                Text(state.primaryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if state.report.findings.count > 1 {
                    Text("+\(state.report.findings.count - 1) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch state.report.status {
        case .info:    return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch state.report.status {
        case .info:    return .green
        case .warning: return .orange
        case .blocked: return .red
        }
    }
}
