#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
DEVICE=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS-26" in runtime:
        for device in devices[runtime]:
            if device["name"].startswith("iPhone"):
                print(device["udid"])
                sys.exit(0)
raise SystemExit("No available iOS 26 iPhone simulator")
')
# ML Kit's simulator binaries require x86_64. Build every dependency for that
# same architecture; otherwise Capacitor builds arm64 on Apple Silicon runners.
xcodebuild -workspace frontend/ios/App/App.xcworkspace -scheme App \
  -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE,arch=x86_64" \
  -derivedDataPath "$RUNNER_TEMP/ios-simulator" \
  -resultBundlePath "$RUNNER_TEMP/WidgetNavigation.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  -only-testing:WidgetNavigationUITests test \
  > "$RUNNER_TEMP/ios-navigation.log" 2>&1 || { tail -n 160 "$RUNNER_TEMP/ios-navigation.log"; exit 1; }
echo 'Widget deep links passed on iOS Simulator: cold launch, background resume, and legacy widget URL.' >> "$GITHUB_STEP_SUMMARY"
