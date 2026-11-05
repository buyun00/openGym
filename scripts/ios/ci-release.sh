#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/../.."
export SIGNING_DIR="$RUNNER_TEMP/opengym-signing"
mkdir -p "$SIGNING_DIR" "$HOME/Library/MobileDevice/Provisioning Profiles"
python3 - <<'PY'
import base64, os, pathlib, re
root = pathlib.Path(os.environ['SIGNING_DIR'])
for name, filename in [('IOS_DISTRIBUTION_P12_BASE64', 'distribution.p12'),
                       ('IOS_APP_PROFILE_BASE64', 'app.mobileprovision'),
                       ('IOS_WIDGET_PROFILE_BASE64', 'widget.mobileprovision')]:
    try:
        root.joinpath(filename).write_bytes(base64.b64decode(''.join(os.environ[name].split()), validate=True))
    except Exception:
        raise SystemExit('Invalid base64 secret: ' + name)
if not re.fullmatch(r'[A-Z0-9]{10}', os.environ['ASC_KEY_ID']):
    raise SystemExit('Invalid ASC_KEY_ID')
root.joinpath('AuthKey_' + os.environ['ASC_KEY_ID'] + '.p8').write_text(os.environ['ASC_PRIVATE_KEY'])
PY

KEYCHAIN="$RUNNER_TEMP/opengym-signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/distribution.p12" -P "$IOS_DISTRIBUTION_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
for kind in app widget; do
  security cms -D -i "$SIGNING_DIR/$kind.mobileprovision" > "$SIGNING_DIR/$kind.plist"
done
python3 scripts/ios/ci-signing.py
for kind in app widget; do
  cp "$SIGNING_DIR/$kind.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/opengym-ci-$kind.mobileprovision"
done

# Per-target profiles: a global PROVISIONING_PROFILE_SPECIFIER would also affect Pods.
ruby -rjson <<'RUBY'
gem 'xcodeproj', '1.27.0'
require 'xcodeproj'
config = JSON.parse(File.read(File.join(ENV.fetch('SIGNING_DIR'), 'settings.json')))
project = Xcodeproj::Project.open('frontend/ios/App/App.xcodeproj')
config.fetch('targets').each do |name, profile|
  target = project.targets.find { |item| item.name == name }
  abort "Missing target #{name}" unless target
  target.build_configurations.each do |build|
    build.build_settings['CODE_SIGN_STYLE'] = 'Manual'
    build.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
    build.build_settings['DEVELOPMENT_TEAM'] = config.fetch('team')
    build.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = profile
    build.build_settings['CURRENT_PROJECT_VERSION'] = config.fetch('build')
    build.build_settings['MARKETING_VERSION'] = config['version'] if config['version']
  end
end
project.save
RUBY

xcodebuild -workspace frontend/ios/App/App.xcworkspace -scheme App \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$SIGNING_DIR/openGym.xcarchive" \
  -derivedDataPath "$RUNNER_TEMP/ios-derived" archive \
  > "$RUNNER_TEMP/ios-archive.log" 2>&1 || { tail -n 150 "$RUNNER_TEMP/ios-archive.log"; exit 1; }
xcodebuild -exportArchive -archivePath "$SIGNING_DIR/openGym.xcarchive" \
  -exportOptionsPlist "$SIGNING_DIR/ExportOptions.plist" -exportPath "$SIGNING_DIR/export" \
  > "$RUNNER_TEMP/ios-export.log" 2>&1 || { tail -n 100 "$RUNNER_TEMP/ios-export.log"; exit 1; }
shopt -s nullglob
IPAS=("$SIGNING_DIR/export/"*.ipa)
if [ "${#IPAS[@]}" -ne 1 ]; then
  echo 'Expected exactly one exported IPA' >&2
  exit 1
fi
API_PRIVATE_KEYS_DIR="$SIGNING_DIR" xcrun altool --upload-app --type ios \
  --file "${IPAS[0]}" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
echo 'Upload accepted. Apple processing/export-compliance and internal TestFlight group availability still need confirmation in App Store Connect.' >> "$GITHUB_STEP_SUMMARY"
