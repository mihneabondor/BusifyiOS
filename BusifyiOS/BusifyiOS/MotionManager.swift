import CoreMotion

class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private let motionActivityManager = CMMotionActivityManager()
    private let queue = OperationQueue()
    @Published var motionData: (acceleration: CMAcceleration, rotationRate: CMRotationRate)?

    init() {
        requestAuthorization()
        startUpdating()
    }
    
    // Request user permission for motion data
    func requestAuthorization() {
        if CMMotionActivityManager.authorizationStatus() == .notDetermined {
            motionActivityManager.queryActivityStarting(from: Date(), to: Date(), to: .main) { _, _ in
                // Access requested, status will be updated
            }
        } else if CMMotionActivityManager.authorizationStatus() == .denied {
            print("Motion data access denied. Check Settings.")
        }
    }
    
    func startUpdating() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available on this device.")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0 // 60 Hz update frequency
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] data, error in
            guard let data = data, error == nil else { return }
            
            DispatchQueue.main.async {
                self?.motionData = (
                    acceleration: data.userAcceleration,
                    rotationRate: data.rotationRate
                )
            }
        }
    }
    
    func stopUpdating() {
        motionManager.stopDeviceMotionUpdates()
    }
}
