import XCTest
import Moya
import ApproovAFSession
@testable import ApproovShapes

final class ApproovShapesTests: XCTestCase {
    func testFailedProtectedSetupBlocksProviderEvenAfterBypass() throws {
        try ShapesNetworking.initialize(config: "")
        defer { try? ShapesNetworking.initialize(config: "") }
        XCTAssertThrowsError(try ShapesNetworking.initialize(config: "invalid-sdk-configuration"))
        XCTAssertNil(ShapesNetworking.shapeTarget)
        XCTAssertThrowsError(try ShapesNetworking.makeProvider())
    }

    func testSigningCannotBeEnabledInBypassMode() throws {
        try ShapesNetworking.initialize(config: "")
        defer { try? ShapesNetworking.initialize(config: "") }
        XCTAssertEqual(ShapesNetworking.shapeTarget, .Shape)
        XCTAssertThrowsError(try ShapesNetworking.enableInstallationMessageSigning())
        XCTAssertThrowsError(try ShapesNetworking.initialize(config: "", messageSigning: true))
        XCTAssertNil(ShapesNetworking.shapeTarget)
        XCTAssertThrowsError(try ShapesNetworking.makeProvider())
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
        try ShapesNetworking.initialize(config: "")
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

    func testLiveShapesEndpointsThroughMoyaAndApproovSession() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_TESTS=1 to exercise the public Shapes API")
        }
        try ShapesNetworking.initialize(config: "")
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
        try ShapesNetworking.initialize(config: "")
        let provider = try ShapesNetworking.makeProvider(configuration: .ephemeral)
        for target in [MyService.ProtectedShape, .SignedShape] {
            let response = try liveResponse(for: target, using: provider)
            XCTAssertEqual(response.statusCode, 400, "\(target): \(responseBody(response))")
            XCTAssertTrue(responseBody(response).lowercased().contains("approov token"), responseBody(response))
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
        try ShapesNetworking.initialize(config: config)
        XCTAssertTrue(ApproovService.isApproovEnabled(), "The supplied config did not enable Approov")
        XCTAssertEqual(ShapesNetworking.shapeTarget, .ProtectedShape)
        let protectedProvider = try ShapesNetworking.makeProvider(configuration: .ephemeral)
        let v3Response = try liveResponse(for: .ProtectedShape, using: protectedProvider)
        XCTAssertEqual(v3Response.statusCode, 200, "v3 response: \(responseBody(v3Response))")

        // v5 must reject an unsigned protected request, then accept installation signing.
        let unsignedV5Response = try liveResponse(for: .SignedShape, using: protectedProvider)
        XCTAssertEqual(unsignedV5Response.statusCode, 400,
                          "unsigned v5 response: \(responseBody(unsignedV5Response))")
        XCTAssertTrue(responseBody(unsignedV5Response).lowercased().contains("signature"), responseBody(unsignedV5Response))
        try ShapesNetworking.initialize(config: config, messageSigning: true)
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
