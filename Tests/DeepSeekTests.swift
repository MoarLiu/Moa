import Darwin
import Foundation

#if !MOA_TESTING
@testable import Moa
#endif

enum DeepSeekTests {
    static let tests: [(String, () throws -> Void)] = [
        ("DeepSeek edits only the account grant in Harness YAML", documentEdits),
        ("DeepSeek rejects ambiguous and unsupported credential formats", documentGuards),
        ("DeepSeek saves after quit and manages saved account copies", saveAndManage),
        ("DeepSeek account enrollment and switching preserve other credentials", switchAndEnroll),
        ("DeepSeek launch failures restore only the previous account grant", launchRollback),
        ("DeepSeek credential writes respect process locks and stopped clients", writeExclusion),
        ("DeepSeek rejects symbolic links and corrupt saved accounts", storageGuards),
        ("DeepSeek account snapshots stay outside packages and iCloud", storageIsolation)
    ]
    private struct Failure: Error, CustomStringConvertible { let description: String }
    private static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw Failure(description: message) }
    }
    private static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch is DeepSeekError { return }
        throw Failure(description: "expected a safe DeepSeek error")
    }
    private final class Runtime: DeepSeekAppManaging {
        var isRunning = true
        var events: [String] = []
        var onQuit: (() throws -> Void)?
        var onLaunch: (() throws -> Void)?
        var refuseQuit = false
        var remainRunning = false
        func quit() throws {
            events.append("quit")
            if refuseQuit { throw DeepSeekError.message("DeepSeek did not quit. Finish active tasks and quit it, then try again.") }
            try onQuit?()
            if !remainRunning { isRunning = false }
        }
        func launch() throws {
            events.append("launch")
            try onLaunch?()
            isRunning = true
        }
    }
    private static func withFixture(_ body: (URL, DeepSeekController, Runtime) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-deepseek-tests-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let runtime = Runtime()
        let controller = DeepSeekController(environment: ["HOME": home.path], runtime: runtime)
        try write(document("synthetic-account-a"), to: controller.authURL)
        try body(home, controller, runtime)
    }
    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    private static func snapshot(_ token: String) -> String {
        "  deepseek-account-platform/default:\n    kind: grant\n    payload:\n      version: 1\n      token: \(token)\n      issuer: https://platform.deepseek.com\n"
    }
    private static func document(_ token: String?) -> String {
        """
        # Harness credential store
        version: 1
        records:
          client-connection/browser-session:
            kind: grant
            payload:
              version: 1
              secret: synthetic-browser-session
          deepseek-account-platform/device:
            kind: grant
            payload:
              id: 11111111-1111-4111-8111-111111111111
        """ + "\n" + (token.map(snapshot) ?? "") + """
          future-provider/retained:
            kind: api-key
            key: synthetic-other-provider
        refs:
          DEEPSEEK_API_KEY: synthetic-api-key
          CUSTOM_KEY: 'preserve: # raw YAML'
        # Keep this comment too.
        future: {enabled: true}
        """ + "\n"
    }

    private static func documentEdits() throws {
        let a = document("synthetic-a")
        let b = try DeepSeekCredentialDocument.savedLogin(snapshot("synthetic-b"))
        let edited = try DeepSeekCredentialDocument(a).replacingLogin(with: b)
        try check(edited == document("synthetic-b"), "only the account grant may change")
        try check(try DeepSeekCredentialDocument(a).replacingLogin(with: nil) == document(nil), "new login must keep device, browser session, refs, and unknown sections")
        let crlf = a.replacingOccurrences(of: "\n", with: "\r\n")
        try check(try DeepSeekCredentialDocument(crlf).replacingLogin(with: b) == document("synthetic-b").replacingOccurrences(of: "\n", with: "\r\n"), "line endings must survive")
        for empty in ["", "# empty store\n", "version: 1\n", "version: 1\nrecords: {}\n"] {
            let added = try DeepSeekCredentialDocument(empty).replacingLogin(with: b)
            try check(try DeepSeekCredentialDocument(added).login?.fingerprint == b.fingerprint, "first account must fit an empty store")
            let cleared = try DeepSeekCredentialDocument(added).replacingLogin(with: nil)
            try check(try DeepSeekCredentialDocument(cleared).login == nil, "the last record must leave valid YAML")
        }
        let quoted = a.replacingOccurrences(of: "deepseek-account-platform/default:", with: "\"deepseek-account-platform/default\":")
            .replacingOccurrences(of: "token: synthetic-a", with: "token: 'synthetic-a' # credential")
        try check(try DeepSeekCredentialDocument(quoted).login?.fingerprint == DeepSeekCredentialDocument(a).login?.fingerprint, "quoted keys and scalars must be read correctly")
        let singleQuoted = a.replacingOccurrences(of: "token: synthetic-a", with: "token: 'synthetic''opaque'")
        try check(try DeepSeekCredentialDocument(singleQuoted).login != nil, "YAML escaped single quotes must be supported")
    }

    private static func documentGuards() throws {
        let valid = document("synthetic-secret-never-in-errors")
        let variants = [
            valid.replacingOccurrences(of: "version: 1\nrecords:", with: "version: 2\nrecords:"),
            valid.replacingOccurrences(of: "version: 1\nrecords:", with: "version: \"1\"\nrecords:"),
            valid + "version: 1\n",
            valid.replacingOccurrences(of: "    kind: grant\n    payload:", with: "    kind: grant\n    kind: grant\n    payload:"),
            valid.replacingOccurrences(of: "      token: synthetic-secret-never-in-errors", with: "      token: &alias synthetic-secret-never-in-errors"),
            valid.replacingOccurrences(of: "      token: synthetic-secret-never-in-errors", with: "      token: null"),
            valid.replacingOccurrences(of: "      token: synthetic-secret-never-in-errors", with: "      token: 12345"),
            valid.replacingOccurrences(of: "      token: synthetic-secret-never-in-errors", with: "      token: synthetic-secret-never-in-errors\n        continuation"),
            valid.replacingOccurrences(of: "https://platform.deepseek.com", with: "https://untrusted.invalid"),
            valid.replacingOccurrences(of: "records:\n", with: "records: &aliased\n"),
            valid.replacingOccurrences(of: "    payload:\n      version: 1\n      token:", with: "    payload: {}\n      version: 1\n      token:")
        ]
        for input in variants {
            do { _ = try DeepSeekCredentialDocument(input); throw Failure(description: "unsupported format was accepted") }
            catch let error as DeepSeekError {
                try check(!error.localizedDescription.contains("synthetic-secret"), "errors must not expose tokens")
            }
        }
        try rejects { _ = try DeepSeekCredentialDocument.savedLogin(snapshot("a") + "refs:\n  INJECTED: value\n") }
        try rejects { _ = try DeepSeekCredentialDocument.savedLogin(snapshot("a") + "  duplicate/record:\n    kind: grant\n    payload: {}\n") }
    }

    private static func saveAndManage() throws {
        try withFixture { _, controller, runtime in
            runtime.onQuit = { try write(document("synthetic-latest"), to: controller.authURL) }
            let a = try controller.saveCurrent(name: " A ")
            try check(a.name == "A" && a.snapshot.contains("synthetic-latest"), "capture must happen after graceful quit")
            try check(runtime.events == ["quit", "launch"], "saving must restore a running app")
            runtime.onQuit = nil
            let savedAgain = try controller.saveCurrent(name: "Renamed")
            try check(savedAgain.id == a.id && (try controller.accounts().count) == 1, "same login must update its saved copy")
            let before = try read(controller.authURL)
            try controller.rename(id: a.id, name: "Manual name")
            try check(try controller.accounts().first?.name == "Manual name", "renaming must persist")
            try rejects { _ = try controller.saveCurrent(name: "  ") }
            try controller.delete(id: a.id)
            try check(try controller.accounts().isEmpty && read(controller.authURL) == before, "forgetting must leave the live login unchanged")
            try write(document(nil), to: controller.authURL)
            try rejects { _ = try controller.saveCurrent(name: "API key is not an account") }
        }
    }

    private static func switchAndEnroll() throws {
        try withFixture { _, controller, _ in
            let a = try controller.saveCurrent(name: "A")
            try controller.prepareNewLogin()
            try check(try read(controller.authURL) == document(nil), "enrollment must remove just the grant")
            try write(document("synthetic-account-b"), to: controller.authURL)
            let b = try controller.saveCurrent(name: "B")
            try write(document("synthetic-account-b").replacingOccurrences(of: "synthetic-api-key", with: "latest-api-key"), to: controller.authURL)
            _ = try controller.apply(id: a.id)
            try check(try controller.currentFingerprint() == a.fingerprint, "B to A must select A")
            try check(try read(controller.authURL).contains("latest-api-key"), "switching must keep the latest provider key")
            _ = try controller.apply(id: b.id)
            try check(try controller.currentFingerprint() == b.fingerprint, "A to B must select B")
            try check(try controller.accounts().count == 2, "automatic captures must retain identities and names")
        }
    }

    private static func launchRollback() throws {
        try withFixture { _, controller, runtime in
            let a = try controller.saveCurrent(name: "A")
            try write(document("synthetic-account-b"), to: controller.authURL)
            let b = try controller.saveCurrent(name: "B")
            _ = try controller.apply(id: a.id)
            runtime.onLaunch = {
                runtime.onLaunch = nil
                try write(document("synthetic-b-updated").replacingOccurrences(of: "synthetic-api-key", with: "key-updated-during-launch"), to: controller.authURL)
                runtime.isRunning = true
                throw DeepSeekError.message("Unable to open DeepSeek. Open DeepSeek Harness manually and try again.")
            }
            try rejects { _ = try controller.apply(id: b.id) }
            try check(try controller.currentFingerprint() == a.fingerprint, "failed launch must restore the original grant")
            try check(try read(controller.authURL).contains("key-updated-during-launch"), "rollback must keep unrelated startup changes")
            try check(try controller.accounts().contains(where: { $0.snapshot.contains("synthetic-b-updated") }), "new target credentials must be preserved before rollback")
            runtime.onLaunch = {
                runtime.onLaunch = nil
                throw DeepSeekError.message("Unable to open DeepSeek. Open DeepSeek Harness manually and try again.")
            }
            try rejects { try controller.prepareNewLogin() }
            try check(try controller.currentFingerprint() == a.fingerprint, "failed fresh-login launch must also restore A")
        }
    }

    private static func writeExclusion() throws {
        try withFixture { home, controller, runtime in
            let a = try controller.saveCurrent(name: "A")
            let before = try read(controller.authURL)
            runtime.refuseQuit = true
            try rejects { try controller.prepareNewLogin() }
            runtime.refuseQuit = false
            runtime.remainRunning = true
            try rejects { _ = try controller.apply(id: a.id) }
            runtime.remainRunning = false
            let writerLock = controller.authURL.appendingPathExtension("lock")
            try write("\(getpid())\n", to: writerLock)
            try rejects { try controller.prepareNewLogin() }
            try check(try read(controller.authURL) == before, "contended writer lock must prevent edits")
            try FileManager.default.removeItem(at: writerLock)
            try check(Darwin.kill(Int32.max, 0) != 0 && errno == ESRCH, "fixture lock owner must be absent")
            try write("\(Int32.max)\n", to: writerLock)
            _ = try controller.saveCurrent(name: "A")
            try check(!FileManager.default.fileExists(atPath: writerLock.path), "a proven exited writer must be recoverable with Harness's claim protocol")
            let other = DeepSeekController(environment: ["HOME": home.path], runtime: runtime)
            runtime.onQuit = { try rejects { try other.delete(id: a.id) } }
            _ = try controller.saveCurrent(name: "A")
            runtime.onQuit = nil
            try check(try controller.accounts().count == 1, "another Moa must not edit the account store during an operation")
            try check(!FileManager.default.fileExists(atPath: writerLock.path), "Harness writer lock must be released")
        }
    }

    private static func storageGuards() throws {
        try withFixture { home, controller, runtime in
            _ = try controller.saveCurrent(name: "A")
            let original = try read(controller.authURL)
            try FileManager.default.removeItem(at: controller.authURL)
            let outside = home.appendingPathComponent("untouched.yaml")
            try write(original, to: outside)
            try FileManager.default.createSymbolicLink(at: controller.authURL, withDestinationURL: outside)
            try rejects { try controller.prepareNewLogin() }
            try check(try read(outside) == original, "credential symlink targets must not be edited")
            try FileManager.default.removeItem(at: controller.authURL)
            try write(original, to: controller.authURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: controller.authURL.path)
            try rejects { _ = try controller.currentFingerprint() }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: controller.authURL.path)
            try write("corrupt-private-store", to: controller.storageURL)
            runtime.events = []
            try rejects { try controller.prepareNewLogin() }
            try check(runtime.events.isEmpty && (try read(controller.authURL)) == original, "a corrupt account store must fail before quitting or changing credentials")
            try FileManager.default.removeItem(at: controller.storageURL)
            try FileManager.default.createSymbolicLink(at: controller.storageURL, withDestinationURL: outside)
            try rejects { _ = try controller.accounts() }
            let relative = DeepSeekController(environment: ["HOME": home.path, "DSH_HOME": "relative"], runtime: runtime)
            try rejects { _ = try relative.currentFingerprint() }
            let customHome = home.appendingPathComponent("custom-harness")
            let custom = DeepSeekController(environment: ["HOME": home.path, "DSH_HOME": customHome.path], runtime: runtime)
            try write(document("synthetic-custom-home"), to: custom.authURL)
            // Reuse a valid database from the default home: it must not silently
            // supply accounts to a different Harness credential path.
            try FileManager.default.removeItem(at: controller.storageURL)
            _ = try controller.saveCurrent(name: "Default home")
            try rejects { _ = try custom.accounts() }
        }
    }

    private static func storageIsolation() throws {
        try withFixture { home, controller, _ in
            _ = try controller.saveCurrent(name: "private-deepseek-name")
            try check(try FileManager.default.attributesOfItem(atPath: controller.storageURL.path)[.posixPermissions] as? Int == 0o600, "snapshots must be owner-only")
            try check(try FileManager.default.attributesOfItem(atPath: controller.storageURL.deletingLastPathComponent().path)[.posixPermissions] as? Int == 0o700, "snapshot directory must be private")
            let environment = ["HOME": home.path]
            let packages = MoaDataPackageController(environment: environment)
            let root = MoaDataRoot.localURL(environment: environment)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try write("{}", to: root.appendingPathComponent("profiles.json"))
            let archive = home.appendingPathComponent("data.zip")
            let diagnostics = home.appendingPathComponent("diagnostic.zip")
            _ = try packages.exportDataPackage(to: archive)
            _ = try packages.exportDiagnosticPackage(to: diagnostics)
            for (index, zip) in [archive, diagnostics].enumerated() {
                let destination = home.appendingPathComponent("extracted-\(index)")
                try check(MoaProcessRunner.run("/usr/bin/ditto", ["-x", "-k", zip.path, destination.path]) == 0, "fixture archive must extract")
                for case let file as URL in FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil)! {
                    if !file.hasDirectoryPath, let data = try? Data(contentsOf: file) {
                        try check(!file.path.contains("deepseek-accounts") && data.range(of: Data("private-deepseek-name".utf8)) == nil && data.range(of: Data("synthetic-account-a".utf8)) == nil, "packages and diagnostics must exclude account metadata and tokens")
                    }
                }
            }
            try FileManager.default.createDirectory(at: MoaDataRoot.iCloudDriveRoot(environment: environment), withIntermediateDirectories: true)
            _ = try packages.enableICloudStorage()
            let afterMove = DeepSeekController(environment: environment, runtime: Runtime())
            try check(afterMove.storageURL == controller.storageURL && (try afterMove.accounts().count) == 1, "iCloud must leave DeepSeek account snapshots on this Mac")
            _ = try packages.disableICloudStorage()
        }
    }
}
