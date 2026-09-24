# Testing

The sample uses Approov Alamofire service **3.5.6**, Moya **15.0.3** and the Approov SDK **3.5.3**. The committed `Package.resolved` locks every transitive dependency. It is tested with Xcode 26.4 (CI) and Xcode 27.0.

## Run the tests

Choose a simulator with `xcrun simctl list devices available`, then run from the repository root:

```sh
xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -derivedDataPath build -resultBundlePath TestResults.xcresult \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- test
```

Remove an old result bundle before running again. Keep simulator ad-hoc signing (`CODE_SIGN_IDENTITY=-`): with `CODE_SIGNING_ALLOWED=NO` the build succeeds, but the simulator refuses to load the unsigned Approov framework.

The deterministic tests need no network or account. They cover response handling, Moya session wiring, the order of Approov and Moya plugin processing, and requests after a failed initialization (see [failure handling](README.md#failure-handling)). They intercept requests before they leave the device, so they do not test TLS, pinning or attestation.

CI also runs `python3 scripts/verify-dependencies.py build` after resolving packages, which checks that every package checkout matches `Package.resolved` and has no local changes.

## Live tests

Opt-in tests call the Shapes backend through Moya and `ApproovSession`. `xcodebuild` passes variables prefixed with `TEST_RUNNER_` to the tests, without the prefix; unprefixed variables are not passed. In Xcode, set the variables in the scheme's Test action instead.

- `RUN_LIVE_TESTS=1` checks the public v1 endpoints, and checks that v3 and v5 reject requests without a valid token, including after a failed initialization.
- `RUN_PROTECTED_LIVE_TESTS=1` with `APPROOV_CONFIG` checks, against your account, that v3 accepts an Approov token, v5 rejects an unsigned or tampered request, and v5 accepts an installation-signed request.

For the protected test, the account must manage the Shapes domain and include the installation public key in tokens:

```sh
approov api -add shapes.approov.io
approov policy -setInstallPubKey on
```

A simulator cannot pass attestation on its own. Supply an account [development key](https://approov.io/docs/latest/approov-usage-documentation/#using-a-development-key) in `APPROOV_DEV_KEY`, or [force the simulator's device ID to pass](https://approov.io/docs/latest/approov-usage-documentation/#forcing-a-device-id-to-pass); the app logs the device ID at startup. The commands below read the values without echoing or saving them (zsh syntax):

```sh
read -rs "TEST_RUNNER_APPROOV_CONFIG?Approov config: " && export TEST_RUNNER_APPROOV_CONFIG
read -rs "TEST_RUNNER_APPROOV_DEV_KEY?Approov dev key: " && export TEST_RUNNER_APPROOV_DEV_KEY
TEST_RUNNER_RUN_LIVE_TESTS=1 TEST_RUNNER_RUN_PROTECTED_LIVE_TESTS=1 \
xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -derivedDataPath build -resultBundlePath ProtectedTestResults.xcresult \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- test
unset TEST_RUNNER_APPROOV_CONFIG TEST_RUNNER_APPROOV_DEV_KEY
```

Approov never returns a protected process to bypass mode, so the tests that need bypass mode skip once the protected test has run. Never commit a configuration or development key, and remove force-pass entries and development keys from the account after testing.

## Build Release for devices

```sh
xcodebuild -project shapes-app/ApproovShapes.xcodeproj \
  -scheme ApproovShapes -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

This checks compilation and linking only.

## Before you release

Simulator and development-key results do not prove attestation on real devices. Before releasing your app:

1. Remove development keys and force-pass entries, and register your [app signing certificate](SHAPES-EXAMPLE.md#add-your-signing-certificate-to-approov).
2. On a signed physical device, check that protected requests succeed and that your backend rejects requests with a missing, invalid or expired token (and a missing or tampered signature, if you use message signing).
3. If you use secrets protection, check that substitution works and that the real secret is not in the app binary.
4. Check behavior offline, on a poor network and with backend 4xx/5xx responses.
