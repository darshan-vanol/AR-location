import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // GeneratedPluginRegistrant.register(with: self)

     guard let apiKey = Bundle.main.infoDictionary?["MAPS_API_KEY"] as? String else {
            print("API Key not found")
            return false
        }
     GMSServices.provideAPIKey(apiKey)
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
