"""Validate distribution profiles and generate CI-only signing settings (no secrets logged)."""
import datetime
import json
import os
import pathlib
import plistlib
import re


def prepare(root, env):
    team = env['APPLE_TEAM_ID']
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('APPLE_TEAM_ID must contain 10 uppercase letters/digits')
    version = env.get('IOS_VERSION', '').strip()
    ref = env.get('GITHUB_REF', '')
    if ref.startswith('refs/tags/ios-v'):
        version = ref.removeprefix('refs/tags/ios-v')
    if version and not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Use a three-part version such as 1.0.0; tags must be ios-v1.0.0')
    # Run number + attempt makes retries distinct as well as subsequent workflow runs.
    build = f"{int(env['GITHUB_RUN_NUMBER'])}.{int(env['GITHUB_RUN_ATTEMPT'])}"
    mapping, targets = {}, {}
    for kind, target, bundle in [('app', 'App', 'org.lin0.lingym'),
                                  ('widget', 'GymWidgets', 'org.lin0.lingym.widgets')]:
        with root.joinpath(kind + '.plist').open('rb') as file:
            profile = plistlib.load(file)
        entitlements = profile.get('Entitlements', {})
        identifier = entitlements.get('application-identifier', '')
        if profile.get('TeamIdentifier') != [team] or identifier.split('.', 1)[-1] != bundle:
            raise ValueError(f'{kind}: profile must belong to APPLE_TEAM_ID and {bundle}')
        if profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices') or entitlements.get('get-task-allow'):
            raise ValueError(f'{kind}: requires an App Store Connect distribution profile')
        if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
            raise ValueError(f'{kind}: provisioning profile has expired')
        if 'group.org.lin0.lingym' not in entitlements.get('com.apple.security.application-groups', []):
            raise ValueError(f'{kind}: profile must enable the shared App Group')
        if kind == 'app' and not entitlements.get('com.apple.developer.healthkit'):
            raise ValueError('app: profile must enable HealthKit')
        mapping[bundle] = profile['UUID']
        targets[target] = profile['UUID']
    export = dict(method='app-store-connect', destination='export', signingStyle='manual',
                  teamID=team, signingCertificate='Apple Distribution', provisioningProfiles=mapping,
                  manageAppVersionAndBuildNumber=False, uploadSymbols=True,
                  testFlightInternalTestingOnly=True)
    with root.joinpath('ExportOptions.plist').open('wb') as file:
        plistlib.dump(export, file)
    root.joinpath('settings.json').write_text(json.dumps(dict(team=team, targets=targets,
                                                            build=build, version=version or None)))


if __name__ == '__main__':
    prepare(pathlib.Path(os.environ['SIGNING_DIR']), os.environ)
