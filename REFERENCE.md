# Service API reference

This Moya quickstart uses **approov-service-alamofire 3.5.6**, imported as `ApproovAFSession`.

Use the versioned [service API reference](https://github.com/approov/approov-service-alamofire/blob/3.5.6/REFERENCE.md), [usage examples](https://github.com/approov/approov-service-alamofire/blob/3.5.6/USAGE.md), and [public source](https://github.com/approov/approov-service-alamofire/blob/3.5.6/Sources/ApproovSession/ApproovService.swift). The source is authoritative if prose disagrees with it.

Corrections to the older quickstart reference:

- Import `ApproovAFSession`, then call `try ApproovService.initialize(config: config, comment: nil)`.
- Empty configuration enters initialized bypass mode. It does not enable native Approov protection. A subsequent valid configuration can enable protection.
- `isInitialized()` and `isApproovEnabled()` distinguish service readiness from active protection.
- Use `setServiceMutator(_:)`. `setApproovInterceptorExtensions(_:)` is a deprecated alias.
- `setProceedOnNetworkFailure(proceed:)` is not a public method in this release. Configure a service mutator for an explicit per-status decision override.
- Use `initializationError`, not `initializationFailure`, when matching `ApproovError`.
- `precheck()` is a development check. Do not add manual token caching or redundant prefetching to the request flow.
- Manual `setDataHashInToken(data:)` and automatic `setBindingHeader(header:)` must not be mixed. Binding state persists for the process; use a header that is consistently present.
- Message signing is configured explicitly in this release; see the [worked example](SHAPES-EXAMPLE.md#shapes-app-with-installation-message-signing).
- With Alamofire 5.11 or later, `ApproovSession` processes a request before Moya plugin `prepare` methods run. Headers that binding, substitution or signing depend on must come from `TargetType.headers` or an adapter passed to `ApproovSession(interceptor:)`; see [Moya plugins and Approov](MOYA-OPTIONS.md#moya-plugins-and-approov).

See [initialization and failure handling](README.md#initializing-approov) and [release validation](TESTING.md).
