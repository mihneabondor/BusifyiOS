import SwiftUI
@preconcurrency import WebKit
import CoreLocation

// LocationManager class to manage location services
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var lastKnownLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownLocation = locations.first
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get user location: \(error.localizedDescription)")
    }
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var refreshTrigger = false
    @State private var urlState = "https://app.busify.ro"
    let background: Color = Color(red: 248/255, green: 249/255, blue: 250/255)
    
    var body: some View {
        GeometryReader{ reader in
            ZStack {
                background
                    .ignoresSafeArea()
                
                WebView(url: $urlState,
                        locationManager: locationManager, refreshTrigger: $refreshTrigger)
                .ignoresSafeArea(.all, edges: .bottom)
                .frame(width: reader.size.width, height: reader.size.height * 1.1)
            }
            .onAppear {
                locationManager.requestLocation()
            }
        }
        .onOpenURL { url in
            let path = url.path
            let query = url.query
            if let query = query {
                let result = path + "?" + query
                print(result)
                urlState = result
            } else {
                print(path)
                urlState = path
            }
        }
    }
    
    func refreshPage() {
        refreshTrigger.toggle() // Trigger a refresh in the WebView
    }
}

struct WebView: UIViewRepresentable {
    @Binding var url: String // Use a binding to dynamically update the URL
    @ObservedObject var locationManager: LocationManager
    @Binding var refreshTrigger: Bool // Triggers a page reload

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: makeWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        loadURL(webView: webView) // Load the initial URL
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Load the new URL if it has changed
        loadURL(webView: webView)
        
        // Inject geolocation data if available
        if let location = locationManager.lastKnownLocation {
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            
            let js = """
            navigator.geolocation.getCurrentPosition = function(success, error) {
                success({
                    coords: { latitude: \(latitude), longitude: \(longitude) }
                });
            };
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // Reload the page if refreshTrigger is toggled
        if refreshTrigger {
            webView.reload()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func loadURL(webView: WKWebView) {
        if let newURL = URL(string: url), webView.url?.absoluteString != newURL.absoluteString {
            webView.load(URLRequest(url: newURL))
        }
    }

    private func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let source = """
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
        var head = document.getElementsByTagName('head')[0];
        head.appendChild(meta);
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let userContentController = WKUserContentController()
        userContentController.addUserScript(script)
        
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        return config
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.host != URL(string: parent.url)?.host {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
