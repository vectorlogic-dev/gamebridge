import XCTest
@testable import GameBridge

final class BottleLaunchStateTests: XCTestCase {
    func testBlockedReportDisablesLaunchAndUsesBlockedTitle() {
        let report = LaunchReadinessReport(
            status: .blocked,
            selectedRuntime: nil,
            findings: [
                ReadinessFinding(
                    severity: .blocked,
                    code: .missingRuntimeSelection,
                    message: "Choose a Wine runtime before launching."
                )
            ]
        )

        let state = BottleLaunchState(report: report)

        XCTAssertFalse(state.canLaunch)
        XCTAssertEqual(state.title, "Launch blocked")
        XCTAssertEqual(state.primaryMessage, "Choose a Wine runtime before launching.")
    }

    func testWarningReportKeepsLaunchEnabled() {
        let report = LaunchReadinessReport(
            status: .warning,
            selectedRuntime: nil,
            findings: [
                ReadinessFinding(
                    severity: .warning,
                    code: .missingDXVKSupportFiles,
                    message: "DXVK is not cached yet and may need installation."
                )
            ]
        )

        let state = BottleLaunchState(report: report)

        XCTAssertTrue(state.canLaunch)
        XCTAssertEqual(state.title, "Launch with warnings")
        XCTAssertEqual(state.primaryMessage, "DXVK is not cached yet and may need installation.")
    }

    func testInfoReportUsesReadyTitleAndFallbackMessage() {
        let report = LaunchReadinessReport(
            status: .info,
            selectedRuntime: nil,
            findings: []
        )

        let state = BottleLaunchState(report: report)

        XCTAssertTrue(state.canLaunch)
        XCTAssertEqual(state.title, "Ready to launch")
        XCTAssertEqual(state.primaryMessage, "No launch issues detected.")
    }
}
