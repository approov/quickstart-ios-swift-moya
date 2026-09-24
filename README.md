# Approov Quickstart: iOS Swift Moya

[![CI](https://github.com/approov/quickstart-ios-swift-moya/actions/workflows/ios.yml/badge.svg)](https://github.com/approov/quickstart-ios-swift-moya/actions/workflows/ios.yml)

This quickstart is for native iOS apps written in Swift that use [Moya](https://github.com/Moya/Moya) to make the API calls you want to protect with Approov. Moya runs on Alamofire, so you add Approov by giving your `MoyaProvider` an `ApproovSession` from the [Approov Alamofire service](https://github.com/approov/approov-service-alamofire). It adds Approov tokens, pins connections, and can also protect secrets and sign requests. Your Moya targets do not change.

You need an Approov trial or paid account and its configuration string, which is in your onboarding email or available with `approov sdk -getConfigString`.

> **New to Approov? Start with the [Shapes example](SHAPES-EXAMPLE.md).** It walks you through running a small Moya app, adding Approov to it, and seeing its API requests being accepted, and then adds message signing and secrets protection. The sample targets iOS 15 and is tested with Xcode 26.4 and 27.0.

The rest of this page lists the steps for adding Approov to your own Moya app. In the Shapes sample, each step is marked with an `APPROOV STEP` comment in `ShapesNetworking.swift`.

## ADDING APPROOV SERVICE DEPENDENCY

In Xcode, choose **File → Add Package Dependencies**, enter `https://github.com/approov/approov-service-alamofire.git`, choose **Exact Version** `3.5.6`, and add the `ApproovAFSession` product to your app target.

![Add Package Dependency](readme-images/add-package-repository.png)

This also brings in Alamofire and the closed-source [Approov SDK](https://github.com/approov/approov-ios-sdk). You import the module as `ApproovAFSession`; the session class it provides is `ApproovSession`.

## INITIALIZING APPROOV

Initialize Approov once at launch, in `application(_:didFinishLaunchingWithOptions:)`, before you create any provider:

```swift
import ApproovAFSession

do {
    try ApproovService.initialize(config: "<enter-your-config-string-here>")
} catch {
    // Keep going: requests are then sent without Approov tokens, and your backend rejects them.
    NSLog("Approov initialization failed: %@", error.localizedDescription)
}
```

Apply optional settings, such as token binding, secret substitution or message signing, **after** this call, because initialization resets them. An empty configuration string starts Approov in bypass mode, where requests are not protected. Never log Approov tokens or the configuration string.

## USING MOYA WITH APPROOV

Create each `MoyaProvider` with an `ApproovSession`, and keep a reference to the provider while its requests run:

```swift
import Moya
import ApproovAFSession

guard let session = ApproovSession(startRequestsImmediately: false) else { return }
let provider = MoyaProvider<MyService>(session: session)
```

`startRequestsImmediately: false` lets Moya attach its handlers before each request starts.

> **Declare headers in your targets, not in plugins.** Approov processes a request before Moya plugins run their `prepare` step, so it cannot bind, substitute or sign a header added by a plugin such as `AccessTokenPlugin`. Put such headers in the target's `headers`. See [Moya options](MOYA-OPTIONS.md#moya-plugins-and-approov).

## FAILURE HANDLING

Your backend enforces Approov by checking the token on every request, so a request that reaches it without a valid token is refused there. The service layer sends a request whenever the backend can make that decision, and holds it back only when sending would not help:

| Situation | Request | Result |
| --- | --- | --- |
| The app passes attestation | Sent with a valid Approov token | The backend serves it |
| The app fails attestation | Sent with a token that does not verify | The backend rejects it |
| Initialization failed, or the Approov service is unavailable | Sent without a token | The backend rejects protected requests |
| The API domain is not added to Approov | Sent unchanged | – |
| No token because of a network problem, or a man-in-the-middle is detected | **Not sent** | `.failure` with a retryable Approov networking error |
| A secret cannot be fetched for substitution | **Not sent** | `.failure` with an Approov error |
| The server certificate does not match the Approov pins | **Not sent** | `.failure` |

A temporary network problem therefore gives the app an error it can retry, rather than a backend rejection, and a failed secret fetch stops the request instead of sending the placeholder. Pinning is always enforced because a man-in-the-middle could read everything on the connection, including tokens, secrets and user data. To change the decision for a particular status, install a custom service mutator; see [Reference](REFERENCE.md).

## CHECKING IT WORKS

Until you add your API domains to Approov, requests are sent without an Approov token. Your app still contacts the Approov cloud, and you can see the results in [Live Metrics](https://approov.io/docs/latest/approov-usage-documentation/#metrics-graphs) within a minute or so. To see what Approov did with each request, search the device console for `ApproovService`.

With Moya, a backend rejection arrives as `.success` with an HTTP 4xx status, so check `response.statusCode`. A request that Approov did not send arrives as `.failure`; see [failure handling](#failure-handling).

## NEXT STEPS

To protect your APIs or secrets, choose one or both of these options:

* [API protection](API-PROTECTION.md): your backend checks an [Approov token](https://approov.io/docs/latest/approov-usage-documentation/#approov-tokens) on each request. Optionally, add message signing and token binding.
* [Secrets protection](SECRETS-PROTECTION.md): API keys and other secrets are delivered at runtime to apps that pass attestation, so they are no longer in the app code.

See also:

* [Moya options](MOYA-OPTIONS.md): plugins, retries, trust managers and delegates with `ApproovSession`.
* [Reference](REFERENCE.md): the `ApproovService` API for service 3.5.6.
* [Testing](TESTING.md): running the sample's tests, and checks before you release.
