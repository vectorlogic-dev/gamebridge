import Foundation

/// View-facing summary of a `LaunchReadinessReport`: whether launch should be
/// enabled, a short title for the readiness banner, and the top-priority
/// message to display. Kept as a plain value type so tests don't need SwiftUI.
struct BottleLaunchState: Equatable {
    let report: LaunchReadinessReport

    var canLaunch: Bool {
        report.status != .blocked
    }

    var title: String {
        switch report.status {
        case .info:    return "Ready to launch"
        case .warning: return "Launch with warnings"
        case .blocked: return "Launch blocked"
        }
    }

    var primaryMessage: String {
        report.findings.first?.message ?? "No launch issues detected."
    }
}
