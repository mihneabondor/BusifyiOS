import SwiftUI
@preconcurrency import WebKit
import CoreLocation
import CoreMotion
import OneSignalFramework

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
import CoreLocation

struct WebView: UIViewRepresentable {
    @Binding var url: String
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var motionManager: MotionManager // you can remove if not needed anymore
    @Binding var refreshTrigger: Bool
    @Binding var locationUpdateTrigger: UUID

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        var lastLoadedURL: String?
        var webView: WKWebView?

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let requestURL = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if let host = requestURL.host, host == "app.busify.ro" {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(requestURL)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("🌐 Page started loading")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            print("🌐 Page finished loading")

            // Inject latest location to override geolocation API
            injectLocation()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "debugLog" {
                print("🌐 WebView: \(message.body)")
            }
        }

        private func injectLocation() {
            guard let webView = webView else { return }
            guard let location = parent.locationManager.lastKnownLocation else {
                print("⚠️ No location available to inject")
                return
            }

            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            let locationJS = """
            console.log('🔧 Overriding geolocation API');
            navigator.geolocation.getCurrentPosition = function(success, error) {
                console.log('📍 getCurrentPosition called');
                success({
                    coords: {
                        latitude: \(latitude),
                        longitude: \(longitude),
                        accuracy: 10,
                        altitude: null,
                        altitudeAccuracy: null,
                        heading: null,
                        speed: null
                    },
                    timestamp: Date.now()
                });
            };
            navigator.geolocation.watchPosition = function(success, error) {
                console.log('📍 watchPosition called');
                var id = Math.floor(Math.random() * 10000);
                setInterval(function() {
                    success({
                        coords: {
                            latitude: \(latitude),
                            longitude: \(longitude),
                            accuracy: 10,
                            altitude: null,
                            altitudeAccuracy: null,
                            heading: null,
                            speed: null
                        },
                        timestamp: Date.now()
                    });
                }, 1000);
                return id;
            };
            """
            webView.evaluateJavaScript(locationJS) { result, error in
                if let error = error {
                    print("❌ Location JS injection error: \(error)")
                } else {
                    print("✅ Location API overridden in WebView")
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

        // Debug message handler
        userContentController.add(context.coordinator, name: "debugLog")

        // Inject console.log override to forward logs to native side
        let setupScript = """
        window.nativeLocationUpdate = function(location) {
            window._latestLocation = location;
            if (window._watchSuccess) {
                window._watchSuccess({
                    coords: location,
                    timestamp: Date.now()
                });
            }
        };

        navigator.geolocation.getCurrentPosition = function(success, error) {
            console.log('📍 getCurrentPosition called');
            success({
                coords: window._latestLocation || {
                    latitude: 0,
                    longitude: 0,
                    accuracy: 100
                },
                timestamp: Date.now()
            });
        };

        navigator.geolocation.watchPosition = function(success, error) {
            console.log('📍 watchPosition called');
            window._watchSuccess = success;
            return 1;
        };
        """
        let userScript = WKUserScript(source: setupScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(userScript)

        config.userContentController = userContentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        loadURL(webView: webView, context: context)
        
        self.locationManager.onLocationUpdate = { [weak webView] location in
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            let locationJS = """
            window.nativeLocationUpdate({
                latitude: \(latitude),
                longitude: \(longitude),
                accuracy: 10,
                altitude: null,
                altitudeAccuracy: null,
                heading: null,
                speed: null
            });
            """
            webView?.evaluateJavaScript(locationJS, completionHandler: nil)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadURL(webView: webView, context: context)

        if refreshTrigger {
            webView.reload()
        }
        
        updateLocationInWebView(webView)
    }


    private func loadURL(webView: WKWebView, context: Context) {
        guard let newURL = URL(string: url) else { return }

        if newURL.absoluteString == context.coordinator.lastLoadedURL {
            return
        }

        print("🌐 Loading URL: \(newURL.absoluteString)")
        context.coordinator.lastLoadedURL = newURL.absoluteString
        webView.load(URLRequest(url: newURL))
    }
    
    func updateLocationInWebView(_ webView: WKWebView) {
        guard let location = locationManager.lastKnownLocation else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        let locationJS = """
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition = function(success, error) {
                success({
                    coords: {
                        latitude: \(latitude),
                        longitude: \(longitude),
                        accuracy: 10,
                        altitude: null,
                        altitudeAccuracy: null,
                        heading: null,
                        speed: null
                    },
                    timestamp: Date.now()
                });
            };
            // For watchPosition, simulate calls every second
            navigator.geolocation.watchPosition = function(success, error) {
                var id = Math.floor(Math.random() * 10000);
                setInterval(function() {
                    success({
                        coords: {
                            latitude: \(latitude),
                            longitude: \(longitude),
                            accuracy: 10,
                            altitude: null,
                            altitudeAccuracy: null,
                            heading: null,
                            speed: null
                        },
                        timestamp: Date.now()
                    });
                }, 1000);
                return id;
            };
        }
        """

        webView.evaluateJavaScript(locationJS) { result, error in
            if let error = error {
                print("❌ Location update JS error: \(error)")
            } else {
                print("✅ Location updated in WebView")
            }
        }
    }

}
