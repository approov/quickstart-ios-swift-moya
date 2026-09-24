import Foundation
import Moya
// APPROOV STEP 1: add the approov-service-alamofire package and import its ApproovAFSession
// module. It provides ApproovService (configuration) and ApproovSession (networking).
import ApproovAFSession

/// All of the Approov integration for this app. Copy this pattern into your own Moya app:
/// initialize Approov once at launch (step 2), then create providers with an ApproovSession (step 3).
/// The app uses it once you uncomment the lines marked "USE APPROOV" in AppDelegate.swift and
/// ViewController.swift, as described in SHAPES-EXAMPLE.md.
///
/// A failed setup does not stop the app: the service layer then sends requests without Approov
/// protection and the backend rejects protected ones. See README.md#failure-handling.
///
/// The empty configuration is deliberate for the first, unprotected tutorial step.
/// A configured account selects v3; ApproovMessageSigning selects signed v5.
enum ShapesNetworking {
    enum SetupError: Error { case sessionUnavailable }
    private(set) static var shapeTarget: MyService = .Shape
    static var isProtected: Bool { ApproovService.isApproovEnabled() }

    // APPROOV STEP 2: initialize once, from application(_:didFinishLaunchingWithOptions:), before
    // any provider is created. `config` comes from `approov sdk -getConfigString`; an empty string
    // starts bypass mode, in which requests are sent without Approov protection.
    static func initialize(config: String, messageSigning: Bool = false) {
        // Use the endpoint for the configured mode even if setup fails. Without Approov the
        // request carries no token or signature, so the protected backend rejects it.
        shapeTarget = config.isEmpty ? .Shape : (messageSigning ? .SignedShape : .ProtectedShape)
        let correlationID = UUID().uuidString
        do {
            try ApproovService.initialize(config: config)
        } catch {
            // Keep networking available: the service layer sends requests without Approov tokens.
            // The error explains the problem without containing the configuration.
            NSLog("Approov initialization failed; requests are sent without Approov tokens; session=%@: %@",
                  correlationID, error.localizedDescription)
            return
        }
        // isInitialized() is also true in bypass mode; only isApproovEnabled() means protection is active.
        guard ApproovService.isApproovEnabled() else {
            if messageSigning { NSLog("ApproovMessageSigning needs ApproovConfig; signing is off") }
            NSLog("Approov bypass mode: requests are unprotected; session=%@", correlationID)
            return
        }
        // APPROOV STEP 4 (optional): apply other settings here, AFTER initialization, which resets
        // them. See API-PROTECTION.md for token binding (setBindingHeader) and SECRETS-PROTECTION.md
        // for secret substitution.
        // *** UNCOMMENT IF USING APPROOV SECRETS PROTECTION
        // ApproovService.addSubstitutionHeader(header: "Api-Key", prefix: nil)
        // shapeTarget = .Shape

        // Installation message signing adds an RFC 9421 signature, made with a per-install key held in
        // secure hardware, to each request that has an Approov token. The v5 endpoint verifies it.
        // Requires `approov policy -setInstallPubKey on`.
        if messageSigning {
            ApproovService.setServiceMutator(
                ApproovDefaultMessageSigning().setDefaultFactory(
                    ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory()))
        }
        // The device ID identifies this install for force-pass testing; never log tokens or the config.
        NSLog("Approov initialized; session=%@ device=%@", correlationID, ApproovService.getDeviceID() ?? "unavailable")
    }

    // APPROOV STEP 3: back each MoyaProvider with an ApproovSession, which adds the Approov token,
    // pins the connection, and applies substitution and signing. startRequestsImmediately must be
    // false so Moya can attach its handlers before the request starts. Keep a reference to the
    // provider for as long as its requests run.
    //
    // Approov processes each request before Moya plugins run prepare(). Declare headers that Approov
    // must bind, substitute or sign in TargetType.headers, not in a plugin (see MOYA-OPTIONS.md).
    /// Pass a configuration only to customize it; the default keeps Alamofire's standard headers, as Moya does.
    static func makeProvider(configuration: URLSessionConfiguration? = nil) throws -> MoyaProvider<MyService> {
        let session = configuration.map { ApproovSession(configuration: $0, startRequestsImmediately: false) }
            ?? ApproovSession(startRequestsImmediately: false)
        guard let session = session else { throw SetupError.sessionUnavailable }
        return MoyaProvider<MyService>(session: session)
    }
}
