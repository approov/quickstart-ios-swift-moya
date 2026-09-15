
# Moya Options
This provides some other options available with the Moya networking stack. As Moya just provides an abstraction layer, in order to access the Alamofire features, you will have to set the provider options found [here](https://github.com/Moya/Moya/blob/master/docs/Providers.md).

The rest of the sections here outline how to modify the session in Alamofire.

## Network Retry Options
The `ApproovInterceptor` class implements Alamofire's Interceptor protocol which includes an option to invoke a retry attempt in case the original request failed. We do not implement the retry option in `ApproovInterceptor`, but if you require implementing one, you should mimic the contents of the `adapt()` function and perhaps add some logic regarding retry attempts. See an example [here](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#adapting-and-retrying-requests-with-requestinterceptor).

## Trust Manager
`ApproovSession` 3.5.6 creates an `ApproovTrustManager` by default. Its `serverTrustManager` parameter accepts an `ApproovTrustManager`, not an arbitrary Alamofire `ServerTrustManager`. Keep the default unless you need additional trust evaluators for other hosts:

```swift
let evaluators: [String: ServerTrustEvaluating] = [
    "some.other.host.com": RevocationTrustEvaluator(),
    "another.host": PinnedCertificatesTrustEvaluator()
]
let manager = ApproovTrustManager(allHostsMustBeEvaluated: true, evaluators: evaluators)
let session = ApproovSession(startRequestsImmediately: false, serverTrustManager: manager)
```

This approach will use the Approov dynamic pinning for all hosts that are being [managed](https://approov.io/docs/latest/approov-usage-documentation/#managing-api-domains) by Approov. Other host names will be passed to your custom evaluators. If you specify an evaluator that is also managed by Approov, then Approov will take precedence.

### Alamofire Request
If your code makes use of the default Alamofire `Session`, like so:

```swift
AF.request("https://httpbin.org/get").response { response in
    debugPrint(response)
}
```

all you will need to do to use Approov is to replace the default `Session` object with the `ApproovSession`:

```swift
guard let approovSession = ApproovSession() else { return }
approovSession.request("https://httpbin.org/get").responseData { response in
    debugPrint(response)
}
```

## Network Delegate
You may specify your own network delegate when the `ApproovSession` is constructed as follows:

```swift
let session = ApproovSession(delegate: delegate)
```
