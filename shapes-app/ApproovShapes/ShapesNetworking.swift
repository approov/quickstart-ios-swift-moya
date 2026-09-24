import Foundation
import Moya
import ApproovAFSession

/// The empty configuration is deliberate for the first, unprotected tutorial step.
/// A configured account selects v3; ApproovMessageSigning selects signed v5.
enum ShapesNetworking {
    enum SetupError: Error { case initializationUnavailable, sessionUnavailable, protectionRequired }
    private(set) static var shapeTarget: MyService?
    static var isProtected: Bool { shapeTarget != nil && ApproovService.isApproovEnabled() }

    static func initialize(config: String, messageSigning: Bool = false) throws {
        // The SDK may preserve an earlier bypass state on failure. Do not mistake
        // that state for a successful setup of this application's requested mode.
        shapeTarget = nil
        let correlationID = UUID().uuidString
        do {
            guard !messageSigning || !config.isEmpty else { throw SetupError.protectionRequired }
            try ApproovService.initialize(config: config)
            guard ApproovService.isInitialized() else { throw SetupError.initializationUnavailable }
            guard config.isEmpty || ApproovService.isApproovEnabled() else { throw SetupError.protectionRequired }
            if ApproovService.isApproovEnabled() {
                // Apply optional settings AFTER initialization, which resets them.
                shapeTarget = .ProtectedShape
                // *** UNCOMMENT IF USING APPROOV SECRETS PROTECTION
                // ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
                // shapeTarget = .Shape
                if messageSigning { try enableInstallationMessageSigning() }
                NSLog("Approov initialized; session=%@ device=%@", correlationID, ApproovService.getDeviceID() ?? "unavailable")
            } else {
                shapeTarget = .Shape
                NSLog("Approov bypass mode: requests are unprotected; session=%@", correlationID)
            }
        } catch {
            shapeTarget = nil
            NSLog("Approov initialization failed; networking unavailable; session=%@", correlationID)
            throw error
        }
    }

    /// Pass a configuration only to customize it; the default keeps Alamofire's standard headers, as Moya does.
    static func makeProvider(configuration: URLSessionConfiguration? = nil) throws -> MoyaProvider<MyService> {
        guard shapeTarget != nil, ApproovService.isInitialized() else { throw SetupError.initializationUnavailable }
        let session = configuration.map { ApproovSession(configuration: $0, startRequestsImmediately: false) }
            ?? ApproovSession(startRequestsImmediately: false)
        guard let session = session else { throw SetupError.sessionUnavailable }
        return MoyaProvider<MyService>(session: session)
    }

    static func enableInstallationMessageSigning() throws {
        guard shapeTarget != nil, ApproovService.isApproovEnabled() else { throw SetupError.protectionRequired }
        ApproovService.setServiceMutator(
            ApproovDefaultMessageSigning().setDefaultFactory(
                ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
        shapeTarget = .SignedShape
    }
}
