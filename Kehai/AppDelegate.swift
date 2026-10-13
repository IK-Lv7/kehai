import UIKit
import UserNotifications
import WidgetKit

extension Notification.Name {
    /// トントンが届いた。object は送った人の ID (String)。開いている画面の更新に使う。
    static let tapReceived = Notification.Name("KehaiTapReceived")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PushRegistrar.didReceive(token: deviceToken) }
    }

    /// トントンが届いたら、相手のキャラが手を振る絵を、ウィジェットに出す。
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let senderId = userInfo["sender_id"] as? String {
            TapFeedback.record(partnerId: senderId)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .tapReceived, object: senderId)
        }
        completionHandler(.newData)
    }

    /// アプリを開いているときも、バナーを出す。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
