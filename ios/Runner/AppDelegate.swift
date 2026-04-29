import UIKit
import Flutter
import Firebase
import UserNotifications   // ✅ REQUIRED

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // ✅ Initialize Firebase
    if FirebaseApp.app() == nil {
        FirebaseApp.configure()
    }

    // ✅ Register plugins
    GeneratedPluginRegistrant.register(with: self)

    // ✅ Request notification permission
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    }

    // ✅ Register for remote notifications (IMPORTANT)
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
