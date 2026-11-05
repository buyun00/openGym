#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
npm ci --prefix frontend
(
  cd frontend
  VITE_MOBILE=1 npm run build
  node ../scripts/catalogue/stage-media.mjs dist
  npx cap sync ios
)
# Check only iOS and dist; Android is not built in this workflow.
node --input-type=module <<'JS'
import { checkCopy } from './frontend/scripts/check-mobile-bundle.mjs';
const problems = ['frontend/dist', 'frontend/ios/App/App/public'].flatMap(checkCopy);
if (problems.length) throw new Error(problems.join('\n'));
JS
# Explicit shared scheme, including the embedded widget dependency, for clean CI checkouts.
gem install --user-install xcodeproj --version 1.27.0 --no-document
ruby <<'RUBY'
gem 'xcodeproj', '1.27.0'
require 'xcodeproj'
project = Xcodeproj::Project.open('frontend/ios/App/App.xcodeproj')
app = project.targets.find { |target| target.name == 'App' }
abort 'Missing App target' unless app
tests = project.targets.find { |target| target.name == 'WidgetNavigationUITests' }
unless tests
  tests = project.new_target(:ui_test_bundle, 'WidgetNavigationUITests', :ios, '26.0')
  source = project.main_group.new_file('../Tests/WidgetNavigationUITests/WidgetNavigationUITests.swift')
  tests.source_build_phase.add_file_reference(source)
  tests.add_dependency(app)
end
tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.lin0.lingym.navigationtests'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TEST_TARGET_NAME'] = 'App'
end
project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][tests.uuid] = { 'TestTargetID' => app.uuid }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, tests)
scheme.save_as(project.path, 'App', true)
RUBY
# Simulator tests never receive the personal account credential.
mkdir -p frontend/ios/App/Private
printf '%s' '{"base":"https://example.invalid","token":"","userID":"","name":"CI"}' > frontend/ios/App/Private/GymPersonalConnection.json
