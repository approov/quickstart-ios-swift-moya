import Foundation
import Moya
import ApproovAFSession

/// The empty configuration is deliberate for the first, unprotected tutorial step.
/// Set ApproovConfig in Info.plist and select v3/shapes in MyService for token protection.
enum ShapesNetworking {
    enum SetupError: Error { case initializationUnavailable, sessionUnavailable }

    static func initialize(config: String) throws {
        let correlationID = UUID().uuidString
        do {
            try ApproovService.initialize(config: config)
            guard ApproovService.isInitialized() else { throw SetupError.initializationUnavailable }
            if ApproovService.isApproovEnabled() {
                NSLog("Approov initialized; session=%@ device=%@", correlationID, ApproovService.getDeviceID() ?? "unavailable")
            } else {
                NSLog("Approov bypass mode: requests are unprotected; session=%@", correlationID)
            }
        } catch {
            NSLog("Approov initialization failed; continuing in bypass mode; session=%@", correlationID)
            try ApproovService.initialize(config: "")
            guard ApproovService.isInitialized() else { throw SetupError.initializationUnavailable }
        }
        // Apply optional substitution and signing settings AFTER initialization.
        // ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        // ApproovService.setServiceMutator(
        //     ApproovDefaultMessageSigning().setDefaultFactory(
        //         ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
    }

    static func makeProvider(configuration: URLSessionConfiguration = .default) throws -> MoyaProvider<MyService> {
        guard ApproovService.isInitialized() else { throw SetupError.initializationUnavailable }
        guard let session = ApproovSession(configuration: configuration, startRequestsImmediately: false) else {
            throw SetupError.sessionUnavailable
        }
        return MoyaProvider<MyService>(session: session)
    }
}
