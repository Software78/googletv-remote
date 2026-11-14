import Foundation
import CoreMotion
import GoogleTVKit

/// Turns phone rotation into D-pad presses. The TV protocol has no pointer, so "moving the cursor"
/// means sending an arrow key each time the phone has swung through `stepAngle` radians.
@MainActor
final class MotionPointer {
    private let manager = CMMotionManager()
    private var accum = (x: 0.0, y: 0.0)
    private var lastEmit = Date.distantPast
    private(set) var swung = 0.0          // total rotation since start; lets the UI tell a tap from a gesture

    /// Radians of rotation per key press. Smaller is more sensitive.
    var stepAngle = 0.12
    var onKey: ((TVKey) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        accum = (0, 0); swung = 0
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            MainActor.assumeIsolated { self.handle(motion) }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    private func handle(_ m: CMDeviceMotion) {
        let dt = 1.0 / 60
        let r = m.rotationRate, g = m.gravity
        // Swing about the world's vertical axis (works held flat or upright), and tilt about the device x axis.
        let yaw = r.x * g.x + r.y * g.y + r.z * g.z      // + = swing right
        let pitch = r.x                                  // + = nose up
        guard hypot(yaw, pitch) > 0.15 else { return }   // dead zone
        accum.x += yaw * dt; accum.y += pitch * dt
        swung += hypot(yaw, pitch) * dt

        let now = Date()
        guard now.timeIntervalSince(lastEmit) > 0.06 else { return }
        if abs(accum.x) >= abs(accum.y), abs(accum.x) >= stepAngle {
            onKey?(accum.x > 0 ? .dpadRight : .dpadLeft)
            accum = (0, 0); lastEmit = now
        } else if abs(accum.y) >= stepAngle {
            onKey?(accum.y > 0 ? .dpadUp : .dpadDown)
            accum = (0, 0); lastEmit = now
        }
    }
}
