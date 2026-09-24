import XCTest
import Alamofire
import Moya
import ApproovAFSession
import Approov
@testable import ApproovShapes

final class ApproovShapesTests: XCTestCase {
    // Approov never downgrades a protected process to bypass mode, so these tests
    // skip after the protected live test has initialized the same process.
    private func requireBypassProcess() throws {
        try XCTSkipIf(ApproovService.isApproovEnabled(), "Requires a bypass-mode process")
    }

    // Fail open: a failed setup keeps networking available and sends requests without
    // Approov headers to the configured endpoint, where the backend rejects them.
    func testFailedSetupStillSendsRequestsWithoutApproov() throws {
        try requireBypassProcess()
        ShapesNetworking.initialize(config: "invalid-sdk-configuration")
        defer { ShapesNetworking.initialize(config: "") }
        XCTAssertFalse(ShapesNetworking.isProtected)
        XCTAssertEqual(ShapesNetworking.shapeTarget, .ProtectedShape)
        let request = try capturedRequest(for: ShapesNetworking.shapeTarget)
        XCTAssertEqual(request.url?.path, "/v3/shapes")
        XCTAssertNil(request.value(forHTTPHeaderField: "Approov-Token"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Signature"))
    }

    func testSigningWithoutConfigurationStaysUnprotected() throws {
        try requireBypassProcess()
        ShapesNetworking.initialize(config: "", messageSigning: true)
        defer { ShapesNetworking.initialize(config: "") }
        XCTAssertEqual(ShapesNetworking.shapeTarget, .Shape)
        XCTAssertFalse(ShapesNetworking.isProtected)
        let request = try capturedRequest(for: ShapesNetworking.shapeTarget)
        XCTAssertNil(request.value(forHTTPHeaderField: "Signature"))
    }

    func testFailOpenMutatorSendsWithoutTokenButBlocksManInTheMiddle() throws {
        let mutator = FailOpenMutator(base: ApproovServiceMutatorDefault.shared)
        let url = "https://shapes.approov.io/v3/shapes"
        for status in [ApproovTokenFetchStatus.noNetwork, .poorNetwork, .rejected, .notInitialized, .internalError] {
            XCTAssertTrue(try mutator.handleInterceptorFetchTokenResult(FakeTokenFetchResult(status), url: url), "\(status)")
            XCTAssertFalse(try mutator.handleInterceptorHeaderSubstitutionResult(FakeTokenFetchResult(status), header: "Api-Key"))
            XCTAssertFalse(try mutator.handleInterceptorQueryParamSubstitutionResult(FakeTokenFetchResult(status), queryKey: "key"))
        }
        XCTAssertThrowsError(try mutator.handleInterceptorFetchTokenResult(FakeTokenFetchResult(.mitmDetected), url: url))
        XCTAssertThrowsError(try mutator.handleInterceptorHeaderSubstitutionResult(FakeTokenFetchResult(.mitmDetected), header: "Api-Key"))
        XCTAssertThrowsError(try mutator.handleInterceptorQueryParamSubstitutionResult(FakeTokenFetchResult(.mitmDetected), queryKey: "key"))
        XCTAssertTrue(try mutator.handleInterceptorFetchTokenResult(FakeTokenFetchResult(.success), url: url))
        XCTAssertFalse(try mutator.handleInterceptorFetchTokenResult(FakeTokenFetchResult(.unknownURL), url: url))
    }

    // Sends a request through the app's provider and returns what reached the transport.
    private func capturedRequest(for target: MyService) throws -> URLRequest {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CaptureProtocol.self]
        let provider = try ShapesNetworking.makeProvider(configuration: configuration)
        let completed = expectation(description: "captured \(target)")
        var captured: URLRequest?
        CaptureProtocol.onRequest = { captured = $0 }
        defer { CaptureProtocol.onRequest = nil }
        provider.request(target) { _ in completed.fulfill() }
        wait(for: [completed], timeout: 5)
        return try XCTUnwrap(captured, "The request did not leave the provider")
    }

    private func present(_ json: String, code: Int = 200, target: MyService = .Shape) -> ShapesPresentation {
        ShapesPresentation.make(target: target, result: .success(Response(statusCode: code, data: Data(json.utf8))))
    }

    func testKnownShapes() {
        for shape in ["circle", "rectangle", "square", "triangle"] {
            XCTAssertEqual(present("{\"status\":\"ok\",\"shape\":\"\(shape)\"}"),
                           ShapesPresentation(message: "ok", imageName: shape))
        }
    }

    func testMixedCaseShape() {
        XCTAssertEqual(present("{\"status\":\"ok\",\"shape\":\"CiRcLe\"}").imageName, "circle")
    }

    func testMalformedAndIncompleteResponsesDoNotCrash() {
        for body in ["", "not json", "[]", "null", "{}", "{\"status\":\"ok\"}",
                     "{\"shape\":\"circle\"}", "{\"status\":5,\"shape\":\"circle\"}",
                     "{\"status\":\"ok\",\"shape\":null}"] {
            XCTAssertEqual(present(body).message, "Invalid response from the Shapes API.", body)
            XCTAssertEqual(present(body).imageName, "confused", body)
        }
    }

    func testUnknownShape() {
        XCTAssertEqual(present("{\"status\":\"ok\",\"shape\":\"hexagon\"}").imageName, "confused")
    }

    func testHTTPFailuresForBothButtons() {
        for target in [MyService.Hello, .Shape] {
            for code in [204, 301, 401, 403, 429, 500, 503] {
                let presentation = present("sensitive server diagnostics", code: code, target: target)
                XCTAssertEqual(presentation.message, "HTTP \(code): request was not accepted.")
                XCTAssertEqual(presentation.imageName, "confused")
            }
        }
    }

    func testHelloSuccess() {
        XCTAssertEqual(present("hello", target: .Hello), ShapesPresentation(message: "200 : OK", imageName: "hello"))
    }

    func testNetworkFailureDoesNotExposeRequestDetails() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "sensitive request details"])
        let presentation = ShapesPresentation.make(target: .Shape, result: .failure(.underlying(error, nil)))
        XCTAssertEqual(presentation.imageName, "confused")
        XCTAssertFalse(presentation.message.contains("sensitive"))
    }

    // Mirrors the unwrapping shown in SECRETS-PROTECTION.md#handling-rejections.
    func testApproovRejectionCanBeReadFromMoyaError() {
        let rejection = ApproovError.rejectionError(message: "rejected", ARC: "arc", rejectionReasons: "reasons")
        let result: Result<Response, MoyaError> = .failure(.underlying(AFError.requestAdaptationFailed(error: rejection), nil))
        guard case .failure(.underlying(let error, _)) = result,
              case .rejectionError(_, let arc, let rejectionReasons)? = error.asAFError?.underlyingError as? ApproovError else {
            return XCTFail("ApproovError was not found in the Moya error")
        }
        XCTAssertEqual(arc, "arc")
        XCTAssertEqual(rejectionReasons, "reasons")
    }

    func testMoyaHTTPErrorIsHandledEvenThoughTransportSucceeded() {
        let completed = expectation(description: "stubbed response")
        let provider = MoyaProvider<MyService>(endpointClosure: { target in
            Endpoint(url: URL(target: target).absoluteString,
                     sampleResponseClosure: { .networkResponse(403, Data()) },
                     method: target.method, task: target.task, httpHeaderFields: target.headers)
        }, stubClosure: MoyaProvider.immediatelyStub)
        provider.request(.Hello) { result in
            XCTAssertEqual(ShapesPresentation.make(target: .Hello, result: result).message,
                           "HTTP 403: request was not accepted.")
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
    }

    func testTargetsUseHTTPSAndExpectedPaths() throws {
        for (target, path) in [(MyService.Hello, "/v1/hello"),
                               (.Shape, "/v1/shapes"),
                               (.ProtectedShape, "/v3/shapes"),
                               (.SignedShape, "/v5/shapes")] {
            let request = try MoyaProvider<MyService>.defaultEndpointMapping(for: target).urlRequest()
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "shapes.approov.io")
            XCTAssertEqual(request.url?.path, path)
            XCTAssertEqual(request.httpMethod, "GET")
        }
    }

    func testMoyaUsesApproovSessionAndBypassPreservesRequest() throws {
        try requireBypassProcess()
        ShapesNetworking.initialize(config: "")
        XCTAssertTrue(ApproovService.isInitialized())
        XCTAssertFalse(ApproovService.isApproovEnabled())
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CaptureProtocol.self]
        let provider = try ShapesNetworking.makeProvider(configuration: configuration)
        XCTAssertTrue(provider.session is ApproovSession)
        XCTAssertFalse(provider.session.startRequestsImmediately)
        let completed = expectation(description: "request through real Approov interceptor")
        CaptureProtocol.onRequest = { request in
            XCTAssertEqual(request.url?.path, "/v1/hello")
            XCTAssertNil(request.value(forHTTPHeaderField: "Approov-Token"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Approov-TraceID"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Signature"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Api-Key"), MyService.Hello.headers?["Api-Key"])
        }
        defer { CaptureProtocol.onRequest = nil }
        provider.request(.Hello) { result in
            XCTAssertEqual(ShapesPresentation.make(target: .Hello, result: result).imageName, "hello")
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
    }

    // Alamofire 5.11+ adapts with the session interceptor (Approov) before the per-request
    // interceptor that runs Moya plugin prepare(). Approov cannot bind, substitute or sign
    // plugin-added headers; TargetType headers and ApproovSession adapters are visible.
    func testApproovAdaptsBeforeMoyaPluginPrepare() throws {
        try requireBypassProcess()
        ShapesNetworking.initialize(config: "")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CaptureProtocol.self]
        let probe = HeaderProbe()
        let session = try XCTUnwrap(ApproovSession(configuration: configuration, startRequestsImmediately: false,
                                                   interceptor: Interceptor(adapters: [probe])))
        let provider = MoyaProvider<MyService>(session: session, plugins: [AuthorizationPlugin()])
        let completed = expectation(description: "request through plugin and session adapters")
        var wireHeaders: [String: String]?
        CaptureProtocol.onRequest = { wireHeaders = $0.allHTTPHeaderFields }
        defer { CaptureProtocol.onRequest = nil }
        provider.request(.Hello) { _ in completed.fulfill() }
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(probe.seen?["Api-Key"], MyService.Hello.headers?["Api-Key"])
        XCTAssertNil(probe.seen?["Authorization"], "Session adapters now run before Moya plugins")
        XCTAssertEqual(wireHeaders?["Authorization"], "Bearer plugin-token")
    }

    func testLiveShapesEndpointsThroughMoyaAndApproovSession() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_TESTS=1 to exercise the public Shapes API")
        }
        ShapesNetworking.initialize(config: "")
        let provider = try ShapesNetworking.makeProvider(configuration: .ephemeral)

        for target in [MyService.Hello, .Shape] {
            let completed = expectation(description: "live \(target)")
            provider.request(target) { result in
                switch result {
                case .failure(let error):
                    XCTFail("Live request failed: \(error)")
                case .success(let response):
                    XCTAssertEqual(response.statusCode, 200)
                    let presentation = ShapesPresentation.make(target: target, result: result)
                    XCTAssertNotEqual(presentation.imageName, "confused", presentation.message)
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 20)
        }
    }

    func testLiveProtectedEndpointsRejectBypassRequests() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_TESTS=1 to verify protected endpoint rejection")
        }
        try requireBypassProcess()
        // Bypass mode and a failed setup both send the request without a token; the backend rejects it.
        for config in ["", "invalid-sdk-configuration"] {
            ShapesNetworking.initialize(config: config)
            let provider = try ShapesNetworking.makeProvider(configuration: .ephemeral)
            for target in [MyService.ProtectedShape, .SignedShape] {
                let response = try liveResponse(for: target, using: provider)
                XCTAssertEqual(response.statusCode, 400, "\(target): \(responseBody(response))")
                XCTAssertTrue(responseBody(response).lowercased().contains("approov token"), responseBody(response))
            }
        }
        ShapesNetworking.initialize(config: "")
        for target in [MyService.ProtectedShape, .SignedShape] {
            var invalidRequest = try MoyaProvider<MyService>.defaultEndpointMapping(for: target).urlRequest()
            invalidRequest.setValue("invalid-test-token", forHTTPHeaderField: "Approov-Token")
            let invalidResponse = try rawResponse(for: invalidRequest)
            XCTAssertEqual(invalidResponse.statusCode, 400)
            XCTAssertTrue(responseBody(invalidResponse).contains("invalid approov token"), responseBody(invalidResponse))
        }
    }

    func testLiveProtectedV3AndSignedV5Endpoints() throws {
        guard ProcessInfo.processInfo.environment["RUN_PROTECTED_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_PROTECTED_LIVE_TESTS=1 and APPROOV_CONFIG to exercise v3 and v5")
        }
        guard let config = ProcessInfo.processInfo.environment["APPROOV_CONFIG"], !config.isEmpty else {
            XCTFail("APPROOV_CONFIG is required for protected endpoint tests")
            return
        }

        // Upgrade the app process to protected mode and prove v3 token acceptance.
        ShapesNetworking.initialize(config: config)
        XCTAssertTrue(ApproovService.isApproovEnabled(), "The supplied config did not enable Approov")
        // Optional development key for simulators; it is held by the native SDK across re-initialization.
        if let devKey = ProcessInfo.processInfo.environment["APPROOV_DEV_KEY"], !devKey.isEmpty {
            ApproovService.setDevKey(devKey: devKey)
        }
        XCTAssertEqual(ShapesNetworking.shapeTarget, .ProtectedShape)
        let protectedProvider = try ShapesNetworking.makeProvider(configuration: .ephemeral)
        let v3Response = try liveResponse(for: .ProtectedShape, using: protectedProvider)
        XCTAssertEqual(v3Response.statusCode, 200, "v3 response: \(responseBody(v3Response))")

        // v5 must reject an unsigned protected request, then accept installation signing.
        let unsignedV5Response = try liveResponse(for: .SignedShape, using: protectedProvider)
        XCTAssertEqual(unsignedV5Response.statusCode, 400,
                          "unsigned v5 response: \(responseBody(unsignedV5Response))")
        XCTAssertTrue(responseBody(unsignedV5Response).lowercased().contains("signature"), responseBody(unsignedV5Response))
        ShapesNetworking.initialize(config: config, messageSigning: true)
        XCTAssertEqual(ShapesNetworking.shapeTarget, .SignedShape)
        let signedResponse = try liveResponse(for: .SignedShape, using: protectedProvider)
        XCTAssertEqual(signedResponse.statusCode, 200, "v5 response: \(responseBody(signedResponse))")
        let presentation = ShapesPresentation.make(target: .SignedShape, result: .success(signedResponse))
        XCTAssertNotEqual(presentation.imageName, "confused", presentation.message)

        // Send the same authenticated request with corrupted signature bytes.
        // Use an ordinary session so the Approov interceptor cannot repair it.
        var tamperedRequest = try XCTUnwrap(signedResponse.request)
        let signature = try XCTUnwrap(tamperedRequest.value(forHTTPHeaderField: "Signature"))
        let separator = try XCTUnwrap(signature.firstIndex(of: ":"))
        tamperedRequest.setValue(String(signature[...separator]) + Data(repeating: 0, count: 64).base64EncodedString() + ":",
                                 forHTTPHeaderField: "Signature")
        let tamperedResponse = try rawResponse(for: tamperedRequest)
        XCTAssertEqual(tamperedResponse.statusCode, 400)
        XCTAssertTrue(responseBody(tamperedResponse).lowercased().contains("signature"), responseBody(tamperedResponse))
    }

    private func rawResponse(for request: URLRequest) throws -> Response {
        let completed = expectation(description: "backend rejects altered proof")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var received: Response?
        session.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse, let data = data {
                received = Response(statusCode: response.statusCode, data: data)
            } else {
                XCTFail("Backend rejection request did not receive an HTTP response (\(error != nil))")
            }
            completed.fulfill()
        }.resume()
        wait(for: [completed], timeout: 30)
        return try XCTUnwrap(received)
    }

    private func liveResponse(for target: MyService,
                              using provider: MoyaProvider<MyService>,
                              timeout: TimeInterval = 30) throws -> Response {
        let completed = expectation(description: "live response for \(target)")
        var received: Result<Response, MoyaError>?
        provider.request(target) { result in
            received = result
            completed.fulfill()
        }
        wait(for: [completed], timeout: timeout)
        return try XCTUnwrap(received).get()
    }

    private func responseBody(_ response: Response) -> String {
        String(data: response.data, encoding: .utf8) ?? "<non-UTF-8 response body>"
    }
}

private struct AuthorizationPlugin: PluginType {
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        var request = request
        request.setValue("Bearer plugin-token", forHTTPHeaderField: "Authorization")
        return request
    }
}

// The SDK has no public initializer for results; override the status the mutator reads.
private final class FakeTokenFetchResult: ApproovTokenFetchResult {
    private let fakeStatus: ApproovTokenFetchStatus
    init(_ status: ApproovTokenFetchStatus) {
        fakeStatus = status
        super.init()
    }
    override var status: ApproovTokenFetchStatus { fakeStatus }
}

// Runs in the same session interceptor as, and immediately before, the Approov adapter.
// Written once on Alamofire's queue and read after the test's wait, which orders the accesses.
private final class HeaderProbe: RequestAdapter, @unchecked Sendable {
    var seen: [String: String]?
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        seen = urlRequest.allHTTPHeaderFields
        completion(.success(urlRequest))
    }
}

// Exercises Moya -> ApproovSession -> URL loading, without real attestation or TLS.
private final class CaptureProtocol: URLProtocol {
    static var onRequest: ((URLRequest) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.onRequest?(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("hello".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
