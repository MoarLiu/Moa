import Foundation

enum MoaL10n {
    private static let lock = NSLock()
    private static var cachedBundle: Bundle?

    static func bundle(
        for language: MoaAppLanguage,
        in parentBundle: Bundle = .main
    ) -> Bundle {
        guard let lproj = language.lprojName else {
            return parentBundle
        }
        if let path = parentBundle.path(forResource: lproj, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle
        }
        return parentBundle
    }

    static func reload(defaults: UserDefaults = .standard, parentBundle: Bundle = .main) {
        let resolved = bundle(for: MoaAppLanguage.current(defaults: defaults), in: parentBundle)
        lock.lock()
        cachedBundle = resolved
        lock.unlock()
    }

    private static func activeBundle() -> Bundle {
        lock.lock()
        if let cached = cachedBundle {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let resolved = bundle(for: MoaAppLanguage.current())
        lock.lock()
        if cachedBundle == nil {
            cachedBundle = resolved
        }
        let result = cachedBundle ?? resolved
        lock.unlock()
        return result
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: activeBundle(), value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }
}
