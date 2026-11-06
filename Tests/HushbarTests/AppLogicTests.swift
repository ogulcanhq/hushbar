import AppKit
import CoreAudio
import XCTest

@testable import Hushbar

final class AppSettingTests: XCTestCase {
    func testGainFollowsSquaredCurve() {
        XCTAssertEqual(AppSetting(volume: 1).gain, 1)
        XCTAssertEqual(AppSetting(volume: 0.5).gain, 0.25)
        XCTAssertEqual(AppSetting(volume: 0).gain, 0)
    }

    func testMutingSilencesWithoutForgettingVolume() {
        let setting = AppSetting(volume: 0.5, isMuted: true)
        XCTAssertEqual(setting.gain, 0)
        XCTAssertEqual(setting.volume, 0.5)
    }

    func testDefaultSettingNeverRoutes() {
        for permission in [CapturePermission.Status.granted, .denied, .undetermined] {
            XCTAssertFalse(AppSetting().needsRoute(permission: permission))
        }
    }

    func testMuteRoutesEvenWithoutPermission() {
        XCTAssertTrue(AppSetting(isMuted: true).needsRoute(permission: .denied))
    }

    func testPartialVolumeDoesNotSilenceAppWhenPermissionDenied() {
        let setting = AppSetting(volume: 0.5)
        XCTAssertFalse(setting.needsRoute(permission: .denied))
        XCTAssertTrue(setting.needsRoute(permission: .granted))
        XCTAssertTrue(setting.needsRoute(permission: .undetermined))
    }
}

final class MakeRowsTests: XCTestCase {
    private func identity(_ key: String, regular: Bool = true) -> AppIdentity {
        AppIdentity(key: key, name: key, icon: NSImage(), isRegularApp: regular)
    }

    func testListsIdleRegularAppsButHidesIdleDaemons() {
        let rows = makeRows(
            processes: [(identity("app"), false), (identity("daemon", regular: false), false)],
            seenPlaying: [],
            settings: [:])
        XCTAssertEqual(rows.map(\.id), ["app"])
    }

    func testDaemonAppearsOnceItHasPlayed() {
        let rows = makeRows(
            processes: [(identity("daemon", regular: false), false)],
            seenPlaying: ["daemon"],
            settings: [:])
        XCTAssertEqual(rows.map(\.id), ["daemon"])
    }

    func testAdjustedDaemonStaysListedSoItCanBeRestored() {
        let rows = makeRows(
            processes: [(identity("daemon", regular: false), false)],
            seenPlaying: [],
            settings: ["daemon": AppSetting(isMuted: true)])
        XCTAssertEqual(rows.map(\.id), ["daemon"])
    }

    func testHelpersFoldIntoOneRowThatPlaysIfAnyHelperPlays() {
        for order in [[true, false], [false, true]] {
            let rows = makeRows(
                processes: order.map { (identity("browser"), $0) },
                seenPlaying: [],
                settings: [:])
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.isPlaying, true)
        }
    }

    func testSortsByNameIgnoringCase() {
        let rows = makeRows(
            processes: [(identity("beta"), false), (identity("Alpha"), false), (identity("gamma"), false)],
            seenPlaying: [],
            settings: [:])
        XCTAssertEqual(rows.map(\.name), ["Alpha", "beta", "gamma"])
    }
}

final class AppIdentityTests: XCTestCase {
    func testOutermostAppBundleSkipsNestedHelpers() {
        let path = "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        XCTAssertEqual(AppIdentity.outermostAppBundle(in: path), "/Applications/Browser.app")
    }

    func testNoBundleForBareExecutable() {
        XCTAssertNil(AppIdentity.outermostAppBundle(in: "/usr/bin/afplay"))
    }
}

final class ProcessRouteTests: XCTestCase {
    /// A failed setup must release each resource once. A double free here aborts the test run.
    func testFailedSetupCleansUpWithoutCrashing() {
        XCTAssertThrowsError(
            try ProcessRoute(
                processObject: AudioObjectID(0x7FFF_FFFF),
                outputUID: "hushbar.tests.no-such-device",
                gain: 1))
    }
}
