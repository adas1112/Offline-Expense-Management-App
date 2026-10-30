import Foundation
import LocalAuthentication

enum BiometricFailure: Error, Equatable {
    case canceled
    case unavailable(String)
    case failed(String)
}

enum BiometricAuthService {
    static func availability() -> (title: String, symbol: String, available: Bool, message: String?) {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        let symbol: String
        let title: String
        switch context.biometryType {
        case .faceID:
            symbol = "faceid"
            title = "Face ID"
        case .touchID:
            symbol = "touchid"
            title = "Touch ID"
        case .opticID:
            symbol = "opticid"
            title = "Optic ID"
        default:
            symbol = "lock"
            title = "Device passcode"
        }
        if available {
            return (title, symbol, true, nil)
        }
        let message = error?.localizedDescription ?? "Set a device passcode before turning on app lock."
        return (title, symbol, false, message)
    }

    static func authenticate(reason: String) async -> Result<Void, BiometricFailure> {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failure(.unavailable(error?.localizedDescription ?? "App lock is not available on this device."))
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return success ? .success(()) : .failure(.failed("Authentication did not succeed."))
        } catch let authError as LAError {
            switch authError.code {
            case .userCancel, .appCancel, .systemCancel:
                return .failure(.canceled)
            case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
                return .failure(.unavailable(authError.localizedDescription))
            default:
                return .failure(.failed(authError.localizedDescription))
            }
        } catch {
            return .failure(.failed("Authentication did not succeed."))
        }
    }
}
