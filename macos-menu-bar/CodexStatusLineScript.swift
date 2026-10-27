import Foundation

enum CodexStatusLineScript {
    static func source() throws -> String {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "CodexStatusLine", withExtension: "js", subdirectory: "Resources")
        #else
        let url = Bundle.main.url(forResource: "CodexStatusLine", withExtension: "js")
        #endif
        guard let url else { throw CodexEnhancementError.resource }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func installation(settings: CodexStatusLineSettings, epoch: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "epoch": epoch, "showContext": settings.showContext,
            "showCache": settings.showCache, "belowComposer": settings.belowComposer
        ])
        return "\(try source())(\(String(decoding: data, as: UTF8.self)))"
    }

    static func update(_ snapshot: CodexLiveSnapshot, subscription: Int) throws -> String {
        let data = try JSONEncoder().encode(snapshot)
        return "globalThis.__moaCodexStatusLine?.update(\(String(decoding: data, as: UTF8.self)),\(subscription))"
    }
}
