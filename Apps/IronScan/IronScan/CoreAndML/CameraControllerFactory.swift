import Foundation

enum CameraControllerFactory {
    static func makeDefault() -> any CameraSessionControlling {
        #if targetEnvironment(simulator)
        SimulatorCameraActor()
        #else
        CameraSessionActor()
        #endif
    }
}
