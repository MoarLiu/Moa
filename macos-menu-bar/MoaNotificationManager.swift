import AppKit
import Foundation
import UserNotifications

enum MoaNotificationAction: Equatable {
    case openUsage(MoaUsageSource?)
    case openSettingsAbout

    private static let kindKey = "moaNotificationKind"
    private static let sourceKey = "moaUsageSource"

    var userInfo: [AnyHashable: Any] {
        switch self {
        case .openUsage(let source):
            var info: [AnyHashable: Any] = [Self.kindKey: "dailyUsageAlert"]
            if let source { info[Self.sourceKey] = source.rawValue }
            return info
        case .openSettingsAbout:
            return [Self.kindKey: "updateAvailable"]
        }
    }

    static func parse(userInfo: [AnyHashable: Any]) -> Self? {
        guard let kind = userInfo[kindKey] as? String else { return nil }
        switch kind {
        case "dailyUsageAlert":
            let source = (userInfo[sourceKey] as? String).flatMap(MoaUsageSource.init(rawValue:))
            return .openUsage(source)
        case "updateAvailable":
            return .openSettingsAbout
        default:
            return nil
        }
    }
}

enum MoaNotificationAuthorizationState: Equatable {
    case unavailable
    case notDetermined
    case authorized
    case denied
}

protocol MoaUserNotificationDelivering: AnyObject {
    var onAction: ((MoaNotificationAction) -> Void)? { get set }
    func authorizationState(completion: @escaping (MoaNotificationAuthorizationState) -> Void)
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func deliver(
        identifier: String,
        title: String,
        body: String,
        action: MoaNotificationAction,
        allowsAuthorizationPrompt: Bool,
        completion: @escaping (Bool) -> Void
    )
}

/// Bridges UNUserNotificationCenter safely. Never touches UNUserNotificationCenter.current()
/// outside a real `.app` bundle or under test/preview modes (which would raise an NSException).
final class MoaSystemNotificationBackend: NSObject, MoaUserNotificationDelivering, UNUserNotificationCenterDelegate {
    var onAction: ((MoaNotificationAction) -> Void)?
    private var delegateInstalled = false

    static var isSystemCenterAvailable: Bool {
        guard !MoaRuntimeMode.suppressesUserInteraction,
              !MoaRuntimeMode.isWorkspacePreview else {
            return false
        }
        return Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private func center() -> UNUserNotificationCenter? {
        guard Self.isSystemCenterAvailable else { return nil }
        let current = UNUserNotificationCenter.current()
        if !delegateInstalled {
            current.delegate = self
            delegateInstalled = true
        }
        return current
    }

    func installDelegateIfAvailable() {
        _ = center()
    }

    func authorizationState(completion: @escaping (MoaNotificationAuthorizationState) -> Void) {
        guard let center = center() else {
            completion(.unavailable)
            return
        }
        center.getNotificationSettings { settings in
            let state: MoaNotificationAuthorizationState
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                state = .authorized
            case .denied:
                state = .denied
            case .notDetermined:
                state = .notDetermined
            @unknown default:
                state = .unavailable
            }
            DispatchQueue.main.async { completion(state) }
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard let center = center() else {
            completion(false)
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func deliver(
        identifier: String,
        title: String,
        body: String,
        action: MoaNotificationAction,
        allowsAuthorizationPrompt: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard let center = center() else {
            completion(false)
            return
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.enqueue(center: center, identifier: identifier, title: title, body: body, action: action, completion: completion)
            case .notDetermined where allowsAuthorizationPrompt:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else {
                        DispatchQueue.main.async { completion(false) }
                        return
                    }
                    self.enqueue(center: center, identifier: identifier, title: title, body: body, action: action, completion: completion)
                }
            case .notDetermined, .denied:
                DispatchQueue.main.async { completion(false) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private func enqueue(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String,
        action: MoaNotificationAction,
        completion: @escaping (Bool) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = action.userInfo
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let action = MoaNotificationAction.parse(userInfo: response.notification.request.content.userInfo) {
            DispatchQueue.main.async { [weak self] in
                self?.onAction?(action)
            }
        }
        completionHandler()
    }
}

final class MoaNotificationManager: ObservableObject {
    @Published private(set) var authorizationState: MoaNotificationAuthorizationState = .unavailable
    private let backend: MoaUserNotificationDelivering
    private let fallbackHandler: (String, String) -> Void

    var onAction: ((MoaNotificationAction) -> Void)? {
        didSet { backend.onAction = onAction }
    }

    init(
        backend: MoaUserNotificationDelivering = MoaSystemNotificationBackend(),
        fallbackHandler: @escaping (String, String) -> Void = { title, detail in
            MoaFeedbackCenter.shared.show(title: title, detail: detail)
        }
    ) {
        self.backend = backend
        self.fallbackHandler = fallbackHandler
        if let system = backend as? MoaSystemNotificationBackend {
            system.installDelegateIfAvailable()
        }
        refreshAuthorizationState()
    }

    func refreshAuthorizationState() {
        backend.authorizationState { [weak self] state in
            self?.authorizationState = state
        }
    }

    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        backend.authorizationState { [weak self] state in
            self?.authorizationState = state
            switch state {
            case .authorized:
                completion?(true)
            case .notDetermined:
                self?.backend.requestAuthorization { granted in
                    self?.refreshAuthorizationState()
                    completion?(granted)
                }
            case .denied, .unavailable:
                completion?(false)
            }
        }
    }

    /// Delivers a system notification when permitted; otherwise falls back to a
    /// non-activating banner so background alerts never steal focus.
    func post(
        identifier: String,
        title: String,
        body: String,
        action: MoaNotificationAction,
        allowsAuthorizationPrompt: Bool = true,
        fallbackOnDenied: Bool = true,
        completion: ((Bool) -> Void)? = nil
    ) {
        backend.deliver(identifier: identifier, title: title, body: body, action: action,
                        allowsAuthorizationPrompt: allowsAuthorizationPrompt) { [weak self] delivered in
            self?.refreshAuthorizationState()
            if !delivered && fallbackOnDenied {
                self?.fallbackHandler(title, body)
            }
            completion?(delivered)
        }
    }
}
