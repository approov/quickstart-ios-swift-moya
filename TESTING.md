# Testing and release gates

## Baseline

This quickstart consumes Approov Alamofire **3.5.6**, Moya **15.0.3** and native Approov SDK **3.5.3**. The committed Xcode `Package.resolved` records every transitive dependency. Local validation used Xcode **26.4 (17E192)** and iOS Simulator **26.4**. The CI image offers Xcode 26.4.1 through the same `Xcode_26.4.app` path; CI itself still needs a hosted run.

The authoritative stable acceptance criteria are [core-service-layers-testing/TESTING_REQUIREMENTS.md at 1ea387b](https://github.com/approov/core-service-layers-testing/blob/1ea387b/TESTING_REQUIREMENTS.md), rechecked on 2026-09-16. There is no separate Moya or Alamofire requirements file in that revision. Moya consumes the Alamofire service; the general requirements therefore apply to that dependency as well as this integration. CI uses the iOS 26.4.1 runtime installed with its pinned Xcode 26.4.1 image; local commands below use the available iOS 26.4 runtime.

The newer [feature/3.8.0 requirements](https://github.com/approov/core-service-layers-testing/blob/feature/3.8.0/TESTING_REQUIREMENTS.md) explicitly target the upcoming 3.8.x contract. Do not mix their status/header and signing defaults into validation of service 3.5.6. Recheck both the release and the applicable requirements commit before a release decision.

## Run the quickstart regression suite

After resolving packages, run `python3 scripts/verify-dependencies.py build` with the actual derived-data directory. It verifies every dependency revision against `Package.resolved` and rejects modified checkouts. CI runs this check before testing. A test against a patched package cache must be reported separately from a test against the published lockfile.

Choose an available simulator using `xcrun simctl list devices available`, then run from the repository root:

```sh
xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -derivedDataPath build -resultBundlePath TestResults.xcresult \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- test
```

Remove or rename an old result bundle before another run. Keep simulator ad-hoc signing enabled: `CODE_SIGNING_ALLOWED=NO` can build successfully but the simulator then refuses to load the unsigned Approov binary framework.

Twelve deterministic tests cover all four shapes, response and network errors, HTTPS target mapping, Moya session wiring, rejected configuration after bypass startup, and signing without an account configuration. Failed initialization must prevent provider creation. URLProtocol intercepts the wiring test before transport: it verifies session wiring and absence of protection headers, **not TLS or attestation**.

An opt-in live test sends both demo requests through Moya and `ApproovSession` and checks the public Shapes API response. Enable it only when network access is expected:

```sh
RUN_LIVE_TESTS=1 xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -derivedDataPath build-live -resultBundlePath LiveTestResults.xcresult \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- test
```

When running from a shell, Xcode may not forward custom environment variables to the test host. In that case, add `RUN_LIVE_TESTS=1` to the scheme's Test action or set it in the selected simulator before running the live test.

Two additional opt-in tests cover the protected endpoints. One confirms that bypass-mode v3 and v5 requests are rejected. The other confirms that v3 accepts a valid Approov token, v5 rejects the same request without a message signature, and v5 accepts the installation-signed request. Set `RUN_LIVE_TESTS=1` for the rejection test. Set both `RUN_PROTECTED_LIVE_TESTS=1` and `APPROOV_CONFIG` for the protected test. The account must manage `shapes.approov.io`, include the installation public key in tokens, and pass the selected test device:

```sh
approov api -add shapes.approov.io
approov policy -setInstallPubKey on
```

Run the protected tests as separate selected-test invocations while changing account policy. Approov configuration is process-wide, so this keeps the bypass and protected phases independent:

```sh
xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -derivedDataPath build-protected -resultBundlePath ProtectedTestResults.xcresult \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- \
  -only-testing:ApproovShapesTests/ApproovShapesTests/testLiveProtectedV3AndSignedV5Endpoints test
```

Do not commit `APPROOV_CONFIG` or a development/force-pass override. Remove temporary account overrides after collecting the results.

For a simulator run from an authenticated Approov terminal, `bash scripts/test-protected.sh SIMULATOR_UDID APPROOV_DEVICE_ID DERIVED_DATA` verifies the locked dependencies, temporarily adds that device to force pass if needed, runs only the protected test, and removes the entry it added. It restores the previous simulator test environment on exit. `DERIVED_DATA` must already contain the resolved packages; `RESULT_ROOT` optionally selects a fresh output directory. No account configuration is written to the repository. This helper is only for simulator integration testing, not production device attestation.

The empty-config example intentionally starts in bypass mode against v1. The separate protected tests check backend rejection and acceptance; force-passed simulator results do not prove physical-device attestation. The negative checks require HTTP 400 and the expected proof-related response, so an outage or an unrelated HTTP error cannot count as a pass. They also exercise invalid tokens and a corrupted v5 signature.

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

These are deterministic in-process checks against the mini SDK. They do not prove device attestation, backend enforcement, or real TLS pin validation. The quickstart remains pinned to the published 3.5.6 package until the service change is released. The 2026-09-15 protected run used a patched service checkout. The 2026-09-16 startup, public/invalid-token, physical-device and Release-archive checks used unmodified published packages, verified against the committed lockfile.

On 2026-09-16 the iPhone simulator suite passed 14 tests with the protected-account test skipped. The connected iPhone 16e (iOS 27.0 beta) passed all 12 deterministic tests with three live tests skipped. A development-signed Release archive passed strict code-signature verification and included the Approov and Alamofire privacy manifests. This does not constitute App Store distribution validation or attestation acceptance on the physical device.

## Requirements coverage and remaining release gates

| Requirement | Evidence / remaining work |
| --- | --- |
| §1 Initialization | Nine existing initialization tests plus reset and reinitialization regressions pass. Sample bypass wiring passes. Real SDK comment identity and signed-device startup remain to be validated. |
| §2 Request processing | Mini-SDK regressions for artifacts, empty values, binding, protected/unprotected traffic, exclusions and status fallback pass. Backend request capture remains a device gate. |
| §3 Mutators | Default and custom token/substitution decisions pass, including rejected-token skip and abort behavior. Wire-level server receipt remains a device gate. |
| §4 Pinning | Trust-manager selection, dynamic pins, accept-any, exclusions and bypass configuration pass in process. Real valid/invalid TLS pins, pin updates, non-TLS challenges and shared-certificate host ordering remain device/network gates. |
| §5 Signing | RFC 9421 headers, single-signature replacement, failure fallback and POST/PUT/PATCH body-digest policies pass deterministically. Valid/missing-signature v5 enforcement passed on a force-passed simulator on 2026-09-15; the new corrupted-signature check needs a fresh authenticated run. Streamed-body behavior remains an external gate. |
| §6 Secure strings / custom JWT | Valid/missing/empty/ranged substitutions and an 18 KB custom JWT payload pass. Real protected backend acceptance remains an external gate. |
| §7 Public interface | Corrected module, initialization state, mutator API, reset behavior and removed-method guidance are covered by build or tests. |
| §8 API / changelog accuracy | Quickstart points to the pinned public source/reference. Companion service patch records both behavior changes under Unreleased. |
| §9 Documentation | Corrected imports, dependency requirements, initialization failure handling, Moya provider wiring, reference links and walkthrough file locations. Device screenshots still need refreshing after an actual protected run. |

### Signed-device and backend checks

Use a dedicated test account and record app commit, package lock, device/OS, signing identity, policy and result for each scenario. Do not put secrets or full tokens in the evidence report.

1. Run the Hello and v1 demo steps. Confirm these are labeled unprotected and do not count as a protection pass.
2. Configure the account and v3 endpoint. The guarded protected live test covers missing and valid proof. On a registered signed device without a development/force-pass override, also verify invalid, expired and replayed tokens are rejected by the backend.
3. Run the pinning scenarios in §4, including invalid system trust in bypass mode and the two shared-certificate host orders. Capture server receipt/non-receipt and pin-check logs.
4. Configure v5. The guarded protected live test covers missing and valid installation signatures. Also verify tampered signature rejection and exercise digest and signing-failure cases from §5.
5. Run secrets protection with placeholders; verify backend acceptance after substitution and rejection/failure paths. Confirm real credentials are absent from the app binary.
6. Exercise offline/poor network, cancellation, rapid taps, background/foreground recovery, and backend 401/403/429/5xx responses.
7. Repeat on the oldest supported iOS version and a current physical device. Remove development keys/force-pass settings, build a signed Release archive, validate privacy manifests and App Store requirements, and refresh walkthrough screenshots.

**Release decision:** the local quickstart fixes are reviewable, but production sign-off requires a published corrected service dependency and the outstanding protection/device evidence. Do not describe the passing simulator suite as full requirements compliance.
