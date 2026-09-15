# Testing and release gates

## Baseline

This quickstart consumes Approov Alamofire **3.5.6**, Moya **15.0.3** and native Approov SDK **3.5.3**. The committed Xcode `Package.resolved` records every transitive dependency. Local validation used Xcode **26.4 (17E192)** and iOS Simulator **26.4**. The CI image offers Xcode 26.4.1 through the same `Xcode_26.4.app` path; CI itself still needs a hosted run.

The authoritative stable acceptance criteria are [core-service-layers-testing/TESTING_REQUIREMENTS.md at 1ea387b](https://github.com/approov/core-service-layers-testing/blob/1ea387b/TESTING_REQUIREMENTS.md), verified on 2026-09-15. There is no separate Moya or Alamofire requirements file in that revision. Moya consumes the Alamofire service; the general requirements therefore apply to that dependency as well as this integration.

The newer [feature/3.8.0 requirements](https://github.com/approov/core-service-layers-testing/blob/feature/3.8.0/TESTING_REQUIREMENTS.md) explicitly target the upcoming 3.8.x contract. Do not mix their status/header and signing defaults into validation of service 3.5.6. Recheck both the release and the applicable requirements commit before a release decision.

## Run the quickstart regression suite

Choose an available simulator using `xcrun simctl list devices available`, then run from the repository root:

```sh
xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -derivedDataPath build -resultBundlePath TestResults.xcresult \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- test
```

Remove or rename an old result bundle before another run. Keep simulator ad-hoc signing enabled: `CODE_SIGNING_ALLOWED=NO` can build successfully but the simulator then refuses to load the unsigned Approov binary framework.

Ten deterministic tests cover all four shapes, case normalization, malformed/missing/wrongly typed JSON fields, unknown shapes, HTTP failures for both buttons, network failure presentation, Moya's HTTP-error success behavior, HTTPS target mapping, and the real Moya → ApproovSession interceptor path in bypass mode. URLProtocol intercepts that integration test before transport: it verifies session wiring and absence of protection headers, **not TLS or attestation**.

An eleventh, opt-in live test sends both demo requests through Moya and `ApproovSession` and checks the public Shapes API response. Enable it only when network access is expected:

```sh
RUN_LIVE_TESTS=1 xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -derivedDataPath build-live -resultBundlePath LiveTestResults.xcresult \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- test
```

When running from a shell, Xcode may not forward custom environment variables to the test host. In that case, add `RUN_LIVE_TESTS=1` to the scheme's Test action or set it in the selected simulator before running the live test.

The example intentionally starts in bypass mode against v1. Passing these tests is not evidence of backend enforcement.

## Build Release for physical devices

```sh
xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

This checks compilation and linking only. Signing, archiving, device execution and distribution validation require your Apple signing configuration.

## Service-layer requirement regressions (internal test infrastructure)

The companion `approov-service-alamofire` change adds `MoyaServiceRequirementsTests.swift` to the service's existing mini-SDK target. It requires access to the private testing repository and is not included in the customer app or public quickstart CI.

To reproduce, use clean sibling checkouts of `approov-service-alamofire` and `core-service-layers-testing`, apply the companion service change to tag **3.5.6**, and check out testing commit `1ea387b`. Then run from the service directory:

```sh
APPROOV_USE_MINI_SDK=1 swift test
```

The complete local run contains 49 tests: 40 requirement regressions and nine existing initialization tests. All 49 pass with the companion service change. The new regressions cover initialization state, token and trace headers, exclusions, token-fetch decisions, binding, secure-string substitution, request mutators, RFC 9421 signing, content digests, long custom JWT payloads, trust-manager selection, dynamic pins, accept-any and excluded URLs, bypass behavior, and reset behavior.

These are deterministic in-process checks against the mini SDK. They do not prove device attestation, backend enforcement, or real TLS pin validation. The quickstart remains pinned to the published 3.5.6 package until the service change is released; local app validation used the patched service checkout.

## Requirements coverage and remaining release gates

| Requirement | Evidence / remaining work |
| --- | --- |
| §1 Initialization | Nine existing initialization tests plus reset and reinitialization regressions pass. Sample bypass wiring passes. Real SDK comment identity and signed-device startup remain to be validated. |
| §2 Request processing | Mini-SDK regressions for artifacts, empty values, binding, protected/unprotected traffic, exclusions and status fallback pass. Backend request capture remains a device gate. |
| §3 Mutators | Default and custom token/substitution decisions pass, including rejected-token skip and abort behavior. Wire-level server receipt remains a device gate. |
| §4 Pinning | Trust-manager selection, dynamic pins, accept-any, exclusions and bypass configuration pass in process. Real valid/invalid TLS pins, pin updates, non-TLS challenges and shared-certificate host ordering remain device/network gates. |
| §5 Signing | RFC 9421 headers, single-signature replacement, failure fallback and POST/PUT/PATCH body-digest policies pass deterministically. v5 backend enforcement and streamed-body behavior remain external gates. |
| §6 Secure strings / custom JWT | Valid/missing/empty/ranged substitutions and an 18 KB custom JWT payload pass. Real protected backend acceptance remains an external gate. |
| §7 Public interface | Corrected module, initialization state, mutator API, reset behavior and removed-method guidance are covered by build or tests. |
| §8 API / changelog accuracy | Quickstart points to the pinned public source/reference. Companion service patch records both behavior changes under Unreleased. |
| §9 Documentation | Corrected imports, dependency requirements, initialization failure handling, Moya provider wiring, reference links and walkthrough file locations. Device screenshots still need refreshing after an actual protected run. |

### Signed-device and backend checks

Use a dedicated test account and record app commit, package lock, device/OS, signing identity, policy and result for each scenario. Do not put secrets or full tokens in the evidence report.

1. Run the Hello and v1 demo steps. Confirm these are labeled unprotected and do not count as a protection pass.
2. Configure the account and v3 endpoint. On a registered signed device with no debugger or force-pass override, verify valid tokens are accepted. Verify missing, invalid, expired and replayed tokens are rejected by the backend.
3. Run the pinning scenarios in §4, including invalid system trust in bypass mode and the two shared-certificate host orders. Capture server receipt/non-receipt and pin-check logs.
4. Configure v5 and verify both valid message signatures and tampered/missing signatures. Exercise digest and signing-failure cases from §5.
5. Run secrets protection with placeholders; verify backend acceptance after substitution and rejection/failure paths. Confirm real credentials are absent from the app binary.
6. Exercise offline/poor network, cancellation, rapid taps, background/foreground recovery, and backend 401/403/429/5xx responses.
7. Repeat on the oldest supported iOS version and a current physical device. Remove development keys/force-pass settings, build a signed Release archive, validate privacy manifests and App Store requirements, and refresh walkthrough screenshots.

**Release decision:** the local quickstart fixes are reviewable, but production sign-off requires a published corrected service dependency and the outstanding protection/device evidence. Do not describe the passing simulator suite as full requirements compliance.
