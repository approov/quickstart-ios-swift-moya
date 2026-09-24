# Moya Options

This provides some other options available with the Moya networking stack. Moya is an abstraction over an Alamofire `Session`, so Approov is added by passing an `ApproovSession` to `MoyaProvider(session:)`. The general provider options are described in [Moya's provider documentation](https://github.com/Moya/Moya/blob/master/docs/Providers.md). The rest of this page describes how Moya features interact with Approov and how to customize the `ApproovSession`.

## Moya Plugins and Approov

With Alamofire 5.11 or later (this quickstart locks 5.12.2), the session interceptor installed by `ApproovSession` adapts each request **before** the per-request interceptor that Moya uses to run plugin `prepare(_:target:)` methods. Approov therefore does not see headers added or changed by a Moya plugin, such as the `Authorization` header added by `AccessTokenPlugin`:

* a plugin-added header is not available for [token binding](API-PROTECTION.md#token-binding) with `setBindingHeader(header:)`;
* a placeholder in a plugin-added header is not [substituted](SECRETS-PROTECTION.md#substituting-the-secret-automatically);
* a plugin-added header is not covered by an [installation message signature](API-PROTECTION.md#message-signing), and a plugin that changes a signed component (method, URL, `Content-Type` or body) after signing invalidates the signature.

Put any header that Approov must process in the target's `headers` (or in a custom `endpointClosure`), as the Shapes sample does for `Api-Key`. Alternatively, add it with an Alamofire adapter passed to the `ApproovSession` initializer; those adapters run before the Approov processing:

```swift
import Alamofire
import ApproovAFSession

let session = ApproovSession(startRequestsImmediately: false,
                             interceptor: Interceptor(adapters: [myAuthorizationAdapter]))
```

Plugins that only observe requests and responses (such as `NetworkLoggerPlugin`, `willSend` or `didReceive`) are unaffected. `ApproovShapesTests.testApproovAdaptsBeforeMoyaPluginPrepare` checks this ordering against the locked dependencies.

## Network Retry Options

The Approov interceptor inside `ApproovSession` adapts requests but does not retry them. If you need retries, pass your own retrier when creating the session; it is combined with the Approov interceptor:

```swift
let session = ApproovSession(startRequestsImmediately: false,
                             interceptor: Interceptor(retriers: [RetryPolicy()]))
let provider = MoyaProvider<MyService>(session: session)
```

A retried request is adapted again, so it receives a fresh Approov token (and signature, if enabled). Avoid retrying requests that fail because Approov rejected the app. See [Alamofire's adapting and retrying documentation](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#adapting-and-retrying-requests-with-requestinterceptor).

## Trust Manager

`ApproovSession` 3.5.6 creates an `ApproovTrustManager` by default. Its `serverTrustManager` parameter accepts an `ApproovTrustManager`, not an arbitrary Alamofire `ServerTrustManager`. Keep the default unless you need additional trust evaluators for other hosts:

```swift
let evaluators: [String: ServerTrustEvaluating] = [
    "some.other.host.com": RevocationTrustEvaluator(),
    "another.host": PinnedCertificatesTrustEvaluator()
]
let manager = ApproovTrustManager(evaluators: evaluators)
let session = ApproovSession(startRequestsImmediately: false, serverTrustManager: manager)
```

This approach will use the Approov dynamic pinning for all hosts that are being [managed](https://approov.io/docs/latest/approov-usage-documentation/#managing-api-domains) by Approov. Other host names will be passed to your custom evaluators. If you specify an evaluator that is also managed by Approov, then Approov will take precedence. Only set `allHostsMustBeEvaluated: true` if every host the app contacts is listed in `evaluators`: in bypass mode, or for hosts not explicitly added to Approov, the setting rejects any host without its own evaluator.

## Alamofire Requests

If your code also makes use of the default Alamofire `Session` outside Moya, like so:

```swift
AF.request("https://httpbin.org/get").response { response in
    debugPrint(response)
}
```

replace it with a retained `ApproovSession`. Alamofire cancels outstanding requests when their session is deallocated, so do not create the session as a local variable:

```swift
// For example, a property created after ApproovService.initialize(config:)
let approovSession: ApproovSession

approovSession.request("https://httpbin.org/get").responseData { response in
    debugPrint(response)
}
```

## Network Delegate

You may specify your own network delegate when the `ApproovSession` is constructed as follows:

```swift
let session = ApproovSession(startRequestsImmediately: false, delegate: delegate)
```
