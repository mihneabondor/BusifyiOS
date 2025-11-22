import SwiftUI
import OneSignalFramework
import RevenueCat

@main
struct BusifyiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Purchases.configure(withAPIKey: "appl_gQPUaKqJFZWQmMYTBripzKlEPyI")
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)

        OneSignal.initialize("29198d15-48c7-40fc-91fb-7cf2d39ef4d8", withLaunchOptions: launchOptions)

        if !UserDefaults.standard.bool(forKey: "busifycluj.didRequestNotifications") {
            OneSignal.Notifications.requestPermission({ accepted in
                print("User accepted notifications: \(accepted)")
                UserDefaults.standard.set(true, forKey: "busifycluj.didRequestNotifications")
                self.tryRegisterExternalId()
            }, fallbackToSettings: true)
        } else {
            print("Notification permission already requested.")
            tryRegisterExternalId()
        }

        return true
    }

    private func tryRegisterExternalId() {
        if let externalId = UserDefaults.standard.string(forKey: "busifycluj.notificationid") {
            print("Logging in with saved external ID: \(externalId)")
            OneSignal.login(externalId)
        } else {
            let externalId = UUID().uuidString
            UserDefaults.standard.set(externalId, forKey: "busifycluj.notificationid")
            print("Generated new external ID: \(externalId)")
            OneSignal.login(externalId)
        }
    }
}
