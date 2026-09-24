# Approov Quickstart: iOS Swift Moya

[![CI](https://github.com/approov/quickstart-ios-swift-moya/actions/workflows/ios.yml/badge.svg)](https://github.com/approov/quickstart-ios-swift-moya/actions/workflows/ios.yml)
![Xcode](https://img.shields.io/badge/Xcode-26.4%2B-blue?logo=xcode)
![iOS](https://img.shields.io/badge/iOS-15%2B-blue?logo=apple)
![Service layer](https://img.shields.io/badge/ApproovAFSession-3.5.6-blue)
![SDK](https://img.shields.io/badge/Approov_SDK-3.5.3-blue)
![Signing](https://img.shields.io/badge/Message_Signing-RFC_9421-green)

Integrate Approov into a Swift iOS app using [Moya](https://github.com/Moya/Moya). Moya uses Alamofire underneath; the Approov Alamofire service provides token injection, dynamic pinning and optional secrets protection and message signing. Follow the [Shapes worked example](SHAPES-EXAMPLE.md) to exercise the integration with an Approov trial or paid account.

The integration takes four steps. Each is marked with an `APPROOV STEP` comment in the sample, so you can copy the pattern into your own app:

| Step | What to do | Where in the sample |
| --- | --- | --- |
| 1 | [Add the service dependency](#adding-approov-service-dependency) and `import ApproovAFSession` | `ShapesNetworking.swift` |
| 2 | [Initialize Approov once at launch](#initializing-approov) with your account configuration | `ShapesNetworking.initialize`, called from `AppDelegate.swift` |
| 3 | [Create each `MoyaProvider` with an `ApproovSession`](#using-moya-with-approov) | `ShapesNetworking.makeProvider`, used by `ViewController.swift` |
| 4 | Optionally, enable [message signing, token binding](API-PROTECTION.md) or [secrets protection](SECRETS-PROTECTION.md) after initialization | `ShapesNetworking.initialize` |

Your Moya `TargetType` definitions do not change; `MyService.swift` is an ordinary target.

## ADDING APPROOV SERVICE DEPENDENCY

Use [Swift Package Manager](https://developer.apple.com/documentation/swift_packages/adding_package_dependencies_to_your_app) in **File → Add Package Dependencies**:

| Repository | Exact version | Product / Swift import |
| --- | --- | --- |
| `https://github.com/approov/approov-service-alamofire.git` | `3.5.6` | `ApproovAFSession` |
| `https://github.com/Moya/Moya.git` | `15.0.3` | `Moya` |

![Add Package Dependency](readme-images/add-package-repository.png)

The sample already includes these dependencies. `ApproovSession` is the session **class**; `ApproovAFSession` is the package product and module. The service depends on the closed-source [Approov iOS SDK](https://github.com/approov/approov-ios-sdk) 3.5.3. Commit the application's `Package.resolved` file so CI and local builds use the same transitive versions.

## PROJECT CHANGES

Open `shapes-app/ApproovShapes.xcodeproj` in Xcode. The sample targets iOS 15 and is validated with Xcode 26.4 (CI) and Xcode 27.0. The locked dependencies need at least Swift 6.1 tools (Xcode 16.3), which swift-http-structured-headers 1.7.0 requires; older Xcode versions are not tested. Choose your own signing team for physical-device builds.

For the unprotected tutorial baseline, leave `ApproovConfig` in the app's `Info.plist` empty. Obtain the account configuration with `approov sdk -getConfigString`. A valid account configuration automatically selects the protected v3 Shape endpoint. Set `ApproovMessageSigning` to `YES` to enable installation signing and select v5. Signing requires a non-empty account configuration. Do not commit account-specific configuration or development overrides.

## INITIALIZING APPROOV

Initialize once in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`, before creating a provider. The sample implements this in `ShapesNetworking.initialize(config:messageSigning:)`. A failed initialization is logged and does not stop the app (see [fail-open behavior](#fail-open-behavior)):

```swift
import ApproovAFSession

do {
    try ApproovService.initialize(config: config)
    if ApproovService.isApproovEnabled() {
        NSLog("Approov enabled; device=%@", ApproovService.getDeviceID() ?? "unavailable")
        // Apply optional settings (binding, substitution, signing, fail-open mutator) here.
    } else {
        NSLog("Approov bypass mode: requests are unprotected")
    }
} catch {
    // Keep going: requests are sent without Approov tokens and the backend rejects them.
    NSLog("Approov initialization failed: %@", error.localizedDescription)
}
```

An empty configuration initializes the service in bypass mode without initializing the native SDK. Check `isApproovEnabled()` before claiming protection is active. Apply substitution, binding or signing configuration **after** initialization, because initialization resets service settings. Never log full tokens, API keys or configuration strings.

## USING MOYA WITH APPROOV

Retain a provider backed by an Approov session. Create it after `ApproovService.initialize(config:)` has been called:

```swift
import Moya
import ApproovAFSession

guard let session = ApproovSession(startRequestsImmediately: false) else { return }
let provider = MoyaProvider<MyService>(session: session)
```

`startRequestsImmediately: false` lets Moya attach its handlers before starting a request, following [Moya's custom-session guidance](https://github.com/Moya/Moya/blob/master/docs/Providers.md). Keep using this provider for protected targets. See [Moya options](MOYA-OPTIONS.md) for session customization.

Approov processes each request before Moya plugins run their `prepare` step. Declare headers that Approov must bind, substitute or sign in the target's `headers`, not in a plugin such as `AccessTokenPlugin`. See [Moya plugins and Approov](MOYA-OPTIONS.md#moya-plugins-and-approov).

Moya can return `.success(Response)` for HTTP errors such as 401, 403 or 500. Check the status code and decode response bodies safely. The sample displays HTTP failures and malformed responses without force-unwrapping server-controlled JSON.

## FAIL-OPEN BEHAVIOR

Approov protection is enforced by your **backend**, which checks the Approov token (and, with message signing, the signature) on every request. The app therefore never needs to stop a request to be secure: a request without a valid token is simply refused by the backend. Blocking requests in the app adds no security, because an attacker can remove that check from a modified app, and it can make the app unusable when Approov cannot be reached.

The sample is fail-open: every request leaves the device, and only a failed pin check stops one.

| Situation | What the app sends | What the backend does |
| --- | --- | --- |
| Device passes attestation | Valid Approov token (and signature) | Serves the request |
| Device fails attestation | A token that does not verify | Rejects the request |
| Approov cloud unreachable (`noNetwork`, `poorNetwork`) or another token-fetch failure | No Approov token | Rejects protected requests |
| Initialization failed (for example, an invalid configuration) | No Approov token; standard TLS validation only | Rejects protected requests |
| A secret cannot be substituted | The placeholder, not the secret | Rejects the invalid API key |
| **Pin check fails, or the SDK detects a man-in-the-middle** (`mitmDetected`) | **Nothing: the request is not sent** | – |

Pinning stays fail-closed because a man-in-the-middle could read or change anything on the connection, including tokens, secrets and user data. Whenever Approov is enabled, the service checks the certificate of each API domain added to Approov against its Approov pins, in addition to standard TLS validation, and cancels the request on a mismatch.

By default, service 3.5.6 does not send a request when it cannot fetch a token or substitute a secret; it returns a retryable `ApproovError` instead. The sample installs `FailOpenMutator` (in `ShapesNetworking.swift`) to send those requests. It delegates all other decisions, including a detected man-in-the-middle and message signing, to the standard mutator. Copy it into your app and install it once after initialization, wrapping the message-signing mutator if you use one:

```swift
ApproovService.setServiceMutator(FailOpenMutator(base: ApproovServiceMutatorDefault.shared))
```

Fail-open is only safe when the backend enforces Approov on every protected endpoint. Deploy the [backend token check](API-PROTECTION.md) first. A backend that accepts requests without a token would accept them from any client.

## CHECKING IT WORKS

Start with the [Shapes tutorial](SHAPES-EXAMPLE.md), then run the automated checks and device scenarios in [TESTING.md](TESTING.md). Simulator builds and stubbed responses do not prove real attestation, TLS pinning or backend enforcement.

For account diagnostics, check [Live Metrics](https://approov.io/docs/latest/approov-usage-documentation/#metrics-graphs). An unknown API domain does not receive an Approov token. Seeing requests succeed against an unprotected endpoint is only a connectivity check.

## NEXT STEPS

- [API protection](API-PROTECTION.md): enforce an [Approov token](https://approov.io/docs/latest/approov-usage-documentation/#approov-tokens) at your backend.
- [Secrets protection](SECRETS-PROTECTION.md): replace embedded credentials with Approov-managed secrets. It can be combined with API protection.
- [Reference](REFERENCE.md): the public API for the pinned service version.
- [Moya options](MOYA-OPTIONS.md) and [Alamofire options](https://github.com/approov/approov-service-alamofire/blob/3.5.6/ALAMOFIRE-OPTIONS.md).

This quickstart targets the published 3.5.6 service. The upcoming service migration has a different request/status/signing contract; do not apply those assumptions to this version.
