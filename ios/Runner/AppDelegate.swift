import UIKit
import Flutter
import Firebase // 🔥 1. Add this import

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 🔥 2. Initialize Firebase before the plugin registration
    if FirebaseApp.app() == nil {
        FirebaseApp.configure()
    }
    
    GeneratedPluginRegistrant.register(with: self)
    
    // 🔥 3. Register for remote notifications (Required for APNS token)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}