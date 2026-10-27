#if !MOA_TESTING
import Foundation
import XCTest
@testable import Moa

final class MoaDataSafetyTests: XCTestCase {
    private func withHome(_ body: (URL, [String: String]) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-data-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home, ["HOME": home.path])
    }

    func testLegacyCloudMigrationDoesNotUndoDisabledStateOrRestoreDeletedFiles() throws {
        try withHome { home, environment in
            let fm = FileManager.default
            let oldSupport = home.appendingPathComponent("Library/Application Support/Moa-Lite")
            let oldCloud = MoaDataRoot.iCloudDriveRoot(environment: environment).appendingPathComponent("Moa-Lite")
            try fm.createDirectory(at: oldSupport, withIntermediateDirectories: true)
            try fm.createDirectory(at: oldCloud.appendingPathComponent(".moa-lite"), withIntermediateDirectories: true)
            try Data().write(to: oldSupport.appendingPathComponent("icloud-data-root-enabled"))
            try Data("old".utf8).write(to: oldCloud.appendingPathComponent(".moa-lite/deleted.json"))
            XCTAssertTrue(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            let newCloud = MoaDataRoot.iCloudURL(environment: environment)
            let migrated = newCloud.appendingPathComponent("deleted.json")
            XCTAssertTrue(fm.fileExists(atPath: migrated.path))
            try fm.removeItem(at: migrated)
            try fm.removeItem(at: MoaDataRoot.iCloudStorageStateURL(environment: environment))
            XCTAssertFalse(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            XCTAssertFalse(MoaDataRoot.isICloudStorageEnabled(environment: environment))
            XCTAssertFalse(fm.fileExists(atPath: migrated.path))
        }
    }

    func testExistingMoaDataAndDisabledStateRemainAuthoritative() throws {
        try withHome { home, environment in
            let fm = FileManager.default
            let oldSupport = home.appendingPathComponent("Library/Application Support/Moa-Lite")
            let newLocal = MoaDataRoot.localURL(environment: environment)
            try fm.createDirectory(at: oldSupport, withIntermediateDirectories: true)
            try fm.createDirectory(at: newLocal, withIntermediateDirectories: true)
            try Data().write(to: oldSupport.appendingPathComponent("icloud-data-root-enabled"))
            try Data("current".utf8).write(to: newLocal.appendingPathComponent("profiles.json"))
            XCTAssertFalse(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            XCTAssertFalse(MoaDataRoot.isICloudStorageEnabled(environment: environment))
            XCTAssertEqual(try Data(contentsOf: newLocal.appendingPathComponent("profiles.json")), Data("current".utf8))
        }
    }

    func testLegacyLocalMigrationIgnoresCloudDataFromAnotherDevice() throws {
        try withHome { home, environment in
            let fm = FileManager.default
            let oldLocal = home.appendingPathComponent(".moa-lite")
            let cloud = MoaDataRoot.iCloudURL(environment: environment)
            try fm.createDirectory(at: oldLocal, withIntermediateDirectories: true)
            try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
            try Data("local".utf8).write(to: oldLocal.appendingPathComponent("profiles.json"))
            try Data("cloud".utf8).write(to: cloud.appendingPathComponent("profiles.json"))
            XCTAssertTrue(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            XCTAssertFalse(MoaDataRoot.isICloudStorageEnabled(environment: environment))
            XCTAssertEqual(try Data(contentsOf: MoaDataRoot.localURL(environment: environment).appendingPathComponent("profiles.json")), Data("local".utf8))
            XCTAssertEqual(try Data(contentsOf: cloud.appendingPathComponent("profiles.json")), Data("cloud".utf8))
        }
    }

    func testLegacyCloudModeUsesExistingMoaCloudData() throws {
        try withHome { home, environment in
            let fm = FileManager.default
            let oldSupport = home.appendingPathComponent("Library/Application Support/Moa-Lite")
            let cloud = MoaDataRoot.iCloudURL(environment: environment)
            try fm.createDirectory(at: oldSupport, withIntermediateDirectories: true)
            try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
            try Data().write(to: oldSupport.appendingPathComponent("icloud-data-root-enabled"))
            try Data("cloud".utf8).write(to: cloud.appendingPathComponent("profiles.json"))
            XCTAssertTrue(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            XCTAssertTrue(MoaDataRoot.isICloudStorageEnabled(environment: environment))
            XCTAssertEqual(try Data(contentsOf: cloud.appendingPathComponent("profiles.json")), Data("cloud".utf8))
        }
    }

    func testUnavailableLegacyCloudRetriesWhenDataAppears() throws {
        try withHome { home, environment in
            let fm = FileManager.default
            let oldSupport = home.appendingPathComponent("Library/Application Support/Moa-Lite")
            let oldCloud = MoaDataRoot.iCloudDriveRoot(environment: environment).appendingPathComponent("Moa-Lite")
            try fm.createDirectory(at: oldSupport, withIntermediateDirectories: true)
            try Data().write(to: oldSupport.appendingPathComponent("icloud-data-root-enabled"))
            XCTAssertThrowsError(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            XCTAssertFalse(MoaDataRoot.isICloudStorageEnabled(environment: environment))
            try fm.createDirectory(at: oldCloud, withIntermediateDirectories: true)
            try Data("recovered".utf8).write(to: oldCloud.appendingPathComponent("profiles.json"))
            XCTAssertTrue(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            XCTAssertTrue(MoaDataRoot.isICloudStorageEnabled(environment: environment))
            XCTAssertEqual(try Data(contentsOf: MoaDataRoot.iCloudURL(environment: environment).appendingPathComponent("profiles.json")), Data("recovered".utf8))
        }
    }

    func testRetryDoesNotHideLocalDataCreatedAfterCloudMigrationFailed() throws {
        try withHome { home, environment in
            let fm = FileManager.default
            let oldSupport = home.appendingPathComponent("Library/Application Support/Moa-Lite")
            let oldCloud = MoaDataRoot.iCloudDriveRoot(environment: environment).appendingPathComponent("Moa-Lite")
            let local = MoaDataRoot.localURL(environment: environment)
            try fm.createDirectory(at: oldSupport, withIntermediateDirectories: true)
            try Data().write(to: oldSupport.appendingPathComponent("icloud-data-root-enabled"))
            XCTAssertThrowsError(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            try fm.createDirectory(at: local, withIntermediateDirectories: true)
            try Data("new".utf8).write(to: local.appendingPathComponent("profiles.json"))
            try fm.createDirectory(at: oldCloud, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: oldCloud.appendingPathComponent("profiles.json"))
            XCTAssertFalse(try MoaDataRoot.migrateLegacyMoaLiteRootsIfNeeded(environment: environment))
            XCTAssertFalse(MoaDataRoot.isICloudStorageEnabled(environment: environment))
            XCTAssertEqual(try Data(contentsOf: local.appendingPathComponent("profiles.json")), Data("new".utf8))
        }
    }

    func testExistingNestedMoaCloudDataDoesNotRestoreDeletedFiles() throws {
        try withHome { _, environment in
            let fm = FileManager.default
            let cloud = MoaDataRoot.iCloudURL(environment: environment)
            let nested = MoaDataRoot.legacyNestedICloudURL(environment: environment)
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            try fm.createDirectory(at: MoaDataRoot.supportDirectory(environment: environment), withIntermediateDirectories: true)
            try Data().write(to: MoaDataRoot.iCloudStorageStateURL(environment: environment))
            try Data("current".utf8).write(to: cloud.appendingPathComponent("current.json"))
            try Data("old".utf8).write(to: nested.appendingPathComponent("deleted.json"))
            let controller = MoaDataPackageController(environment: environment)
            let migrated = cloud.appendingPathComponent("deleted.json")
            XCTAssertFalse(try controller.repairLegacyICloudDataSplitIfNeeded())
            XCTAssertFalse(fm.fileExists(atPath: migrated.path))
            XCTAssertTrue(fm.fileExists(atPath: nested.appendingPathComponent("deleted.json").path))
            XCTAssertFalse(try controller.repairLegacyICloudDataSplitIfNeeded())
            XCTAssertFalse(fm.fileExists(atPath: migrated.path))
        }
    }

    func testNestedOnlyMoaCloudDataStillMigrates() throws {
        try withHome { _, environment in
            let fm = FileManager.default
            let cloud = MoaDataRoot.iCloudURL(environment: environment)
            let nested = MoaDataRoot.legacyNestedICloudURL(environment: environment)
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            try fm.createDirectory(at: MoaDataRoot.supportDirectory(environment: environment), withIntermediateDirectories: true)
            try Data().write(to: MoaDataRoot.iCloudStorageStateURL(environment: environment))
            try Data("legacy".utf8).write(to: nested.appendingPathComponent("profiles.json"))
            let controller = MoaDataPackageController(environment: environment)
            XCTAssertTrue(try controller.repairLegacyICloudDataSplitIfNeeded())
            XCTAssertEqual(try Data(contentsOf: cloud.appendingPathComponent("profiles.json")), Data("legacy".utf8))
            XCTAssertFalse(try controller.repairLegacyICloudDataSplitIfNeeded())
        }
    }

    func testExportFailureKeepsExistingArchiveAndUnsafeLinksAreRejected() throws {
        try withHome { home, environment in
            let fm = FileManager.default
            let root = MoaDataRoot.localURL(environment: environment)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("profile".utf8).write(to: root.appendingPathComponent("profiles.json"))
            let archive = home.appendingPathComponent("backup.zip")
            let original = Data("previous backup".utf8)
            try original.write(to: archive)
            let controller = MoaDataPackageController(environment: environment)
            controller.testingBeforeExportArchive = { throw CocoaError(.fileWriteOutOfSpace) }
            XCTAssertThrowsError(try controller.exportDataPackage(to: archive))
            XCTAssertEqual(try Data(contentsOf: archive), original)
            XCTAssertThrowsError(try controller.exportDiagnosticPackage(to: archive))
            XCTAssertEqual(try Data(contentsOf: archive), original)
            controller.testingBeforeExportArchive = nil
            try fm.createSymbolicLink(atPath: root.appendingPathComponent("outside").path, withDestinationPath: "/tmp")
            XCTAssertThrowsError(try controller.exportDataPackage(to: archive))
            XCTAssertEqual(try Data(contentsOf: archive), original)
        }
    }

    func testDiagnosticURLsOmitCredentialsQueryAndFragment() throws {
        try withHome { home, environment in
            let root = MoaDataRoot.localURL(environment: environment)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let json = #"{"profiles":[{"baseURL":"https://user:password@example.com/path-token?api_key=secret#token"}]}"#
            try Data(json.utf8).write(to: root.appendingPathComponent("profiles.json"))
            let archive = home.appendingPathComponent("diagnostics.zip")
            try MoaDataPackageController(environment: environment).exportDiagnosticPackage(to: archive)
            let extracted = home.appendingPathComponent("extract")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, extracted.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let data = try Data(contentsOf: extracted.appendingPathComponent("MoaDiagnostics/redacted/profiles.json"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
            XCTAssertEqual(profiles.first?["baseURL"] as? String, "[REDACTED]")
        }
    }
}
#endif
