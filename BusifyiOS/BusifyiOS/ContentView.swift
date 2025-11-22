import SwiftUI
@preconcurrency import WebKit
import CoreLocation
import CoreMotion
import OneSignalFramework
import RevenueCat

// MARK: - Enhanced Motion Manager with Debugging
class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    @Published var motionData: (acceleration: CMAcceleration, rotationRate: CMRotationRate)?
    @Published var deviceMotion: CMDeviceMotion?
    @Published var isActive = false

    init() {
        setupMotionManager()
        startUpdating()
    }
    
    private func setupMotionManager() {
        print("🔧 Setting up MotionManager...")
        print("📱 Device motion available: \(motionManager.isDeviceMotionAvailable)")
        print("📱 Accelerometer available: \(motionManager.isAccelerometerAvailable)")
        print("📱 Gyroscope available: \(motionManager.isGyroAvailable)")
        print("📱 Magnetometer available: \(motionManager.isMagnetometerAvailable)")
    }

    func startUpdating() {
        guard motionManager.isDeviceMotionAvailable else {
            print("❌ Device motion not available")
            return
        }

        print("🚀 Starting motion updates...")
        motionManager.deviceMotionUpdateInterval = 0.1
        
        // Use .xMagneticNorthZVertical for compass-like behavior
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: OperationQueue()) { [weak self] data, error in
            if let error = error {
                print("❌ Motion error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("❌ No motion data received")
                return
            }
            
            DispatchQueue.main.async {
                self?.isActive = true
                self?.deviceMotion = data
                self?.motionData = (
                    acceleration: data.userAcceleration,
                    rotationRate: data.rotationRate
                )
                
//                // Debug logging (remove in production)
//                if Int(Date().timeIntervalSince1970) % 2 == 0 { // Log every 2 seconds
//                    print("📊 Motion Data:")
//                    print("   Acceleration: x=\(String(format: "%.3f", data.userAcceleration.x)), y=\(String(format: "%.3f", data.userAcceleration.y)), z=\(String(format: "%.3f", data.userAcceleration.z))")
//                    print("   Rotation: x=\(String(format: "%.3f", data.rotationRate.x)), y=\(String(format: "%.3f", data.rotationRate.y)), z=\(String(format: "%.3f", data.rotationRate.z))")
//                    print("   Attitude: yaw=\(String(format: "%.1f", data.attitude.yaw * 180 / .pi))°, pitch=\(String(format: "%.1f", data.attitude.pitch * 180 / .pi))°, roll=\(String(format: "%.1f", data.attitude.roll * 180 / .pi))°")
//                }
            }
        }
    }

    func stopUpdating() {
        print("🛑 Stopping motion updates...")
        motionManager.stopDeviceMotionUpdates()
        isActive = false
    }
    
    // Get compass heading from device motion (more accurate than CLLocationManager for orientation)
    var compassHeading: Double? {
        guard let motion = deviceMotion else { return nil }
        
        // Convert yaw from radians to degrees and normalize to 0-360
        var heading = motion.attitude.yaw * 180 / .pi
        heading = heading < 0 ? heading + 360 : heading
        return 360 - heading // Invert to match compass convention
    }
}

// MARK: - Enhanced Location Manager with Debugging
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocationUpdate: ((CLLocation) -> Void)?
    
    let locationUpdateTrigger = PassthroughSubject<Void, Never>()

    @Published var lastKnownLocation: CLLocation? {
        didSet {
            locationUpdateTrigger.send()
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            DispatchQueue.main.async {
                self.lastKnownLocation = location
                self.onLocationUpdate?(location) // 🔥 Send to whoever is listening
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}


// MARK: - Content View
struct ContentView: View {
    @State private var locationUpdateTrigger = UUID()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var motionManager = MotionManager()
    @State private var refreshTrigger = false
    @State private var urlState = "https://app.busify.ro/map"
    let background: Color = Color(red: 248/255, green: 249/255, blue: 250/255)

    var body: some View {
        GeometryReader { _ in
            ZStack {
                WebView(url: $urlState,
                        locationManager: locationManager,
                        motionManager: motionManager,
                        refreshTrigger: $refreshTrigger,
                        locationUpdateTrigger: $locationUpdateTrigger)
            }
            .onAppear {
                if let externalId = UserDefaults.standard.string(forKey: "busifycluj.notificationid") {
                    OneSignal.login(externalId)
                    urlState = "https://app.busify.ro/map?notificationUserId=\(externalId)"
                }
                locationManager.requestLocation()
            }
            .onReceive(locationManager.locationUpdateTrigger) { _ in
                locationUpdateTrigger = UUID() // trigger a refresh when location changes
            }

        }
        .onOpenURL { url in
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems ?? []

            let userNotificationId = UserDefaults.standard.string(forKey: "busifycluj.notificationid") ?? ""
            if !queryItems.contains(where: { $0.name == "notificationUserId" }) {
                queryItems.append(URLQueryItem(name: "notificationUserId", value: userNotificationId))
            }
            components?.queryItems = queryItems

            if let finalURL = components?.url {
                if finalURL.absoluteString != urlState {
                    urlState = finalURL.absoluteString
                }
            }
        }
    }

    func refreshPage() {
        refreshTrigger.toggle()
    }
}

// MARK: - WebView
// MARK: - Enhanced WebView
import SwiftUI
import WebKit
import Combine
import CoreLocation

import SwiftUI
import WebKit
import Combine
import CoreLocation

struct WebView: UIViewRepresentable {
    @Binding var url: String
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var motionManager: MotionManager
    @Binding var refreshTrigger: Bool
    @Binding var locationUpdateTrigger: UUID

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        var lastLoadedURL: String?
        var webView: WKWebView?
        var watchCallbacks: [String] = []

        // Domains to explicitly block (ad/tracking domains)
//        let blockedHostSubstrings = [
//            "googlesyndication.com",
//            "doubleclick.net",
//            "adservice.google.com",
//            "pagead2.googlesyndication.com",
//            "adtrafficquality.google",
//            "googletagmanager.com",
//            "googletagservices.com",
//            "google.com"
//        ]

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let requestURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let host = requestURL.host?.lowercased() ?? ""
            let scheme = requestURL.scheme?.lowercased() ?? ""

            // Domains that should stay inside the app (in WebView)
            let inAppDomains = [
                "app.busify.ro"
            ]

            // Domains that should open in Safari
            let externalDomains = [
                "busify.ro",
                "ctpcj.ro",
                "revolut.me"
            ]

            // Check domain types
            let isInAppDomain = inAppDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }

            let isExternalDomain = externalDomains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }

            // 1️⃣ Non-http(s) schemes → open externally
            if scheme != "http" && scheme != "https" {
                print("🔗 Non-http(s) scheme detected (\(scheme)). Opening externally.")
                UIApplication.shared.open(requestURL, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }

            // 2️⃣ Internal app domain (app.busify.ro) → allow inside WebView
            if isInAppDomain {
                print("✅ Allowed in-app domain: \(requestURL.absoluteString)")
                decisionHandler(.allow)
                return
            }

            // 3️⃣ External whitelisted domains → open in Safari
            if isExternalDomain {
                print("🌍 Opening allowed external domain in Safari: \(requestURL.absoluteString)")
                UIApplication.shared.open(requestURL, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }

            // 4️⃣ Everything else → block
            print("⛔ Blocked navigation to non-allowed host: \(requestURL.absoluteString)")
            decisionHandler(.cancel)
        }


        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("🌐 Page started loading")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            print("🌐 Page finished loading")
            setupLocationOverride()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "debugLog" {
                print("🌐 WebView: \(message.body)")
            }
            
            if message.name == "donationHandler" {
                    handleDonationRequest(message.body)
                    return
            }
        }
        
        func handleDonationRequest(_ data: Any) {
            guard let dict = data as? [String: Any],
                  let type = dict["type"] as? String,
                  type == "DONATION_REQUEST",
                  let amount = dict["amount"] as? String,
                  let productId = donationProductMap[amount] else {
                print("❌ Invalid donation request or unknown amount")
                return
            }

            print("🎁 Donation request received: \(amount) → \(productId)")

            Task {
                await processDonation(productId: productId)
            }
        }
        
        func processDonation(productId: String) async {
            do {
                let offerings = try await Purchases.shared.offerings()
                
                // Find the package whose storeProduct has matching productIdentifier
                guard let package = offerings.all.values
                    .flatMap({ $0.availablePackages })
                    .first(where: { $0.storeProduct.productIdentifier == productId }) else {
                    print("❌ No package found for productId: \(productId)")
                    return
                }

                let result = try await Purchases.shared.purchase(package: package)
                print("✅ Purchase success: \(result)")
            }
            catch {
                print("❌ Purchase error: \(error)")
            }
        }


        
        let donationProductMap: [String: String] = [
            "5": "com.mihnea.busifycluj.subscriptions.donation5lei",
            "10": "com.mihnea.busifycluj.subscriptions.donation10lei",
            "25": "com.mihnea.busifycluj.subscriptions.donation25lei",
            "50": "com.mihnea.busifycluj.subscriptions.donation50lei"
        ]

        
//        func initiatePurchase(for amount: String) {
//            guard let productID = amountToProductID[amount] else {
//                print("❌ No product for amount: \(amount)")
//                return
//            }
//
//            print("🔎 Fetching product: \(productID)")
//
//            Purchases.shared.getProducts([productID]) { products in
//                guard let product = products.first else {
//                    print("❌ Product not found:", productID)
//                    return
//                }
//
//                self.purchase(product)
//            }
//        }
        
        func purchase(_ product: StoreProduct) {
            Purchases.shared.purchase(product: product) { transaction, customerInfo, error, userCancelled in

                if userCancelled {
                    print("❌ User cancelled purchase")
                    self.sendDonationStatus("cancelled")
                    return
                }

                if let error = error {
                    print("❌ Purchase error:", error.localizedDescription)
                    self.sendDonationStatus("error")
                    return
                }

                print("🎉 Purchase successful")

                self.sendDonationStatus("success")
            }
        }
        
        func sendDonationStatus(_ status: String) {
            let js = "window.postMessage({ type: 'DONATION_STATUS', status: '\(status)' }, '*');"

            webView?.evaluateJavaScript(js, completionHandler: nil)
        }


        private func setupLocationOverride() {
            guard let webView = webView else { return }
            let setupJS = """
            // ... your existing geolocation override JS ...
            // (omitted here for brevity - re-use the exact JS you had)
            """
            webView.evaluateJavaScript(setupJS) { result, error in
                if let error = error {
                    print("❌ Setup JS error: \(error)")
                } else {
                    print("✅ Geolocation override setup complete")
                    self.injectCurrentLocation()
                }
            }
        }

        func injectCurrentLocation() {
            guard let webView = webView,
                  let location = parent.locationManager.lastKnownLocation else {
                print("⚠️ No location available to inject")
                return
            }
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            let locationJS = """
            window.updateLocation({
                latitude: \(latitude),
                longitude: \(longitude),
                accuracy: 10,
                altitude: null,
                altitudeAccuracy: null,
                heading: null,
                speed: null
            });
            """
            webView.evaluateJavaScript(locationJS) { result, error in
                if let error = error {
                    print("❌ Location injection error: \(error)")
                } else {
                    print("✅ Location injected: \(latitude), \(longitude)")
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        //donations
        userContentController.add(context.coordinator, name: "donationHandler")
        
        // Debug handler
        userContentController.add(context.coordinator, name: "debugLog")
        config.userContentController = userContentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Optionally clear website data on creation to remove stale ad scripts/caches
        // Set to `true` only if you actually want to clear data at startup
        let shouldClearWebDataOnStart = false
        if shouldClearWebDataOnStart {
            let dataStore = WKWebsiteDataStore.default()
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                print("🧹 Cleared WKWebView website data on start")
            }
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Load initial URL
        loadURL(webView: webView, context: context)

        // set up location update callback
        self.locationManager.onLocationUpdate = { location in
            DispatchQueue.main.async {
                context.coordinator.injectCurrentLocation()
            }
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let newURL = URL(string: url),
           newURL.absoluteString != context.coordinator.lastLoadedURL {
            loadURL(webView: webView, context: context)
        }

        if refreshTrigger {
            webView.reload()
        }

        // Inject location when locationUpdateTrigger changes
        context.coordinator.injectCurrentLocation()
    }

    private func loadURL(webView: WKWebView, context: Context) {
        guard let newURL = URL(string: url) else { return }
        if newURL.absoluteString == context.coordinator.lastLoadedURL { return }

        print("🌐 Loading URL: \(newURL.absoluteString)")
        context.coordinator.lastLoadedURL = newURL.absoluteString
        webView.load(URLRequest(url: newURL))
    }
}
