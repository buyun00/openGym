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
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, nil)
scheme.save_as(project.path, 'App', true)
RUBY
