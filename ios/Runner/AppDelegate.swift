import UIKit
import Flutter
import Firebase

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // ✅ Initialize Firebase
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // ✅ Register Flutter plugins
    GeneratedPluginRegistrant.register(with: self)

    // ❌ NO notification setup here

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}