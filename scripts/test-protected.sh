#!/bin/bash
# Run from an authenticated Approov shell. Configuration is never written to disk.
set -euo pipefail
if [[ $# -ne 3 ]]; then
  echo "Usage: bash scripts/test-protected.sh SIMULATOR_UDID APPROOV_DEVICE_ID DERIVED_DATA" >&2
  exit 2
fi
simulator=$1
device=$2
derived_data=$3
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
result_root=${RESULT_ROOT:-/private/tmp/moya-protected-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$result_root"
# simctl spawn needs a booted simulator.
xcrun simctl bootstatus "$simulator" -b > /dev/null
# Preserve any test environment that was already present on this simulator.
old_config=$(xcrun simctl spawn "$simulator" launchctl getenv APPROOV_CONFIG || true)
old_flag=$(xcrun simctl spawn "$simulator" launchctl getenv RUN_PROTECTED_LIVE_TESTS || true)
added_device=0
cleanup() {
  status=$?
  trap - EXIT
  set +e
  if [[ -n "$old_config" ]]; then
    xcrun simctl spawn "$simulator" launchctl setenv APPROOV_CONFIG "$old_config"
  else
    xcrun simctl spawn "$simulator" launchctl unsetenv APPROOV_CONFIG
  fi
  if [[ -n "$old_flag" ]]; then
    xcrun simctl spawn "$simulator" launchctl setenv RUN_PROTECTED_LIVE_TESTS "$old_flag"
  else
    xcrun simctl spawn "$simulator" launchctl unsetenv RUN_PROTECTED_LIVE_TESTS
  fi
  if [[ "$added_device" == 1 ]]; then
    if ! approov forcepass -removeDevice "$device"; then
      echo "Cleanup failed: remove temporary force-pass device $device from your account." >&2
      status=1
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
devices=$(approov forcepass -listDevices)
config=$(approov sdk -getConfigString)
if [[ -z "$config" ]]; then
  echo "No SDK configuration returned." >&2
  exit 1
fi
if ! printf '%s\n' "$devices" | awk '{print $1}' | grep -Fxq -- "$device"; then
  approov forcepass -addDevice "$device"
  added_device=1
fi
xcrun simctl spawn "$simulator" launchctl setenv APPROOV_CONFIG "$config"
unset config
xcrun simctl spawn "$simulator" launchctl setenv RUN_PROTECTED_LIVE_TESTS 1
python3 scripts/verify-dependencies.py "$derived_data"
xcodebuild -quiet -project shapes-app/ApproovShapes.xcodeproj -scheme ApproovShapes \
  -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$result_root/DerivedData" -clonedSourcePackagesDirPath "$derived_data/SourcePackages" \
  -resultBundlePath "$result_root/Protected.xcresult" \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- \
  -only-testing:ApproovShapesTests/ApproovShapesTests/testLiveProtectedV3AndSignedV5Endpoints test \
  > "$result_root/build.log" 2>&1
xcrun xcresulttool get test-results summary --path "$result_root/Protected.xcresult" > "$result_root/summary.json"
echo "Protected test passed. Results: $result_root"
