import Foundation
import Moya
// APPROOV STEP 1: add the approov-service-alamofire package and import its ApproovAFSession
// module. It provides ApproovService (configuration) and ApproovSession (networking).
import ApproovAFSession
import Approov

/// All of the Approov integration for this app. Copy this pattern into your own Moya app:
/// initialize Approov once at launch (step 2), then create providers with an ApproovSession (step 3).
///
/// Approov is fail-open here: a request always leaves the device, with an Approov token when one
/// could be obtained and without one otherwise, and the backend decides whether to serve it.
/// Only a failed pin check (a detected man-in-the-middle) stops a request being sent.
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
            // Fail open: keep networking available. The error explains the problem without
            // containing the configuration.
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
        let mutator: ApproovServiceMutator = messageSigning
            ? ApproovDefaultMessageSigning().setDefaultFactory(
                ApproovDefaultMessageSigning.generateDefaultSignatureParametersFactory())
            : ApproovServiceMutatorDefault.shared
        ApproovService.setServiceMutator(FailOpenMutator(base: mutator))
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

/// Fail-open request policy. By default, service 3.5.6 does not send a request when no Approov token
/// can be fetched (for example, the Approov cloud is unreachable) or when a secret cannot be substituted.
/// This mutator sends such requests without the token or with the placeholder left in place, so the
/// backend rejects them. A detected man-in-the-middle still stops the request. All other decisions,
/// including message signing, are delegated to `base`.
struct FailOpenMutator: ApproovServiceMutator {
    let base: ApproovServiceMutator

    func handleInterceptorFetchTokenResult(_ approovResults: ApproovTokenFetchResult, url: String) throws -> Bool {
        switch approovResults.status {
        case .success, .mitmDetected, .noApproovService, .unknownURL, .unprotectedURL:
            return try base.handleInterceptorFetchTokenResult(approovResults, url: url)
        default:
            return true // proceed without a token
        }
    }

    func handleInterceptorHeaderSubstitutionResult(_ approovResults: ApproovTokenFetchResult, header: String) throws -> Bool {
        switch approovResults.status {
        case .success, .mitmDetected:
            return try base.handleInterceptorHeaderSubstitutionResult(approovResults, header: header)
        default:
            return false // leave the placeholder
        }
    }

    func handleInterceptorQueryParamSubstitutionResult(_ approovResults: ApproovTokenFetchResult, queryKey: String) throws -> Bool {
        switch approovResults.status {
        case .success, .mitmDetected:
            return try base.handleInterceptorQueryParamSubstitutionResult(approovResults, queryKey: queryKey)
        default:
            return false // leave the placeholder
        }
    }

    func handlePrecheckResult(_ approovResults: ApproovTokenFetchResult) throws {
        try base.handlePrecheckResult(approovResults)
    }

    func handleFetchTokenResult(_ approovResults: ApproovTokenFetchResult) throws {
        try base.handleFetchTokenResult(approovResults)
    }

    func handleFetchSecureStringResult(_ approovResults: ApproovTokenFetchResult, operation: String, key: String) throws {
        try base.handleFetchSecureStringResult(approovResults, operation: operation, key: key)
    }

    func handleFetchCustomJWTResult(_ approovResults: ApproovTokenFetchResult) throws {
        try base.handleFetchCustomJWTResult(approovResults)
    }

    func handleInterceptorShouldProcessRequest(_ request: URLRequest) throws -> Bool {
        try base.handleInterceptorShouldProcessRequest(request)
    }

    func handleInterceptorProcessedRequest(_ request: URLRequest, changes: ApproovRequestMutations) throws -> URLRequest {
        try base.handleInterceptorProcessedRequest(request, changes: changes)
    }

    func handlePinningShouldProcessRequest(_ request: URLRequest) -> Bool {
        base.handlePinningShouldProcessRequest(request)
    }
}
