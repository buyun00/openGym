import datetime
import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ci_signing', pathlib.Path(__file__).with_name('ci-signing.py'))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.env = dict(APPLE_TEAM_ID='ABCDEFGHIJ', GITHUB_RUN_NUMBER='12', GITHUB_RUN_ATTEMPT='2',
                        GITHUB_REF='refs/tags/ios-v1.2.3')
        self.profiles = {}
        for kind, suffix in [('app', ''), ('widget', '.widgets')]:
            self.profiles[kind] = dict(
                TeamIdentifier=['ABCDEFGHIJ'], UUID=kind + '-uuid',
                ExpirationDate=datetime.datetime.now() + datetime.timedelta(days=30),
                Entitlements={'application-identifier': 'ABCDEFGHIJ.org.lin0.lingym' + suffix,
                              'com.apple.security.application-groups': ['group.org.lin0.lingym'],
                              'com.apple.developer.healthkit': kind == 'app', 'get-task-allow': False})

    def run_prepare(self):
        for kind, data in self.profiles.items():
            self.root.joinpath(kind + '.plist').write_bytes(plistlib.dumps(data))
        signing.prepare(self.root, self.env)

    def test_internal_export_and_two_distinct_profiles(self):
        self.run_prepare()
        export = plistlib.loads(self.root.joinpath('ExportOptions.plist').read_bytes())
        self.assertTrue(export['testFlightInternalTestingOnly'])
        self.assertEqual(export['provisioningProfiles']['org.lin0.lingym.widgets'], 'widget-uuid')
        import json
        settings = json.loads(self.root.joinpath('settings.json').read_text())
        self.assertEqual((settings['version'], settings['build']), ('1.2.3', '12.2'))

    def test_wrong_widget_profile(self):
        self.profiles['widget']['Entitlements']['application-identifier'] = 'ABCDEFGHIJ.org.lin0.lingym'
        with self.assertRaisesRegex(ValueError, 'widget: profile must belong'):
            self.run_prepare()

    def test_ad_hoc_rejected(self):
        self.profiles['app']['ProvisionedDevices'] = ['device']
        with self.assertRaisesRegex(ValueError, 'App Store Connect'):
            self.run_prepare()

    def test_expired_rejected(self):
        self.profiles['app']['ExpirationDate'] = datetime.datetime(2020, 1, 1)
        with self.assertRaisesRegex(ValueError, 'expired'):
            self.run_prepare()

    def test_healthkit_required(self):
        self.profiles['app']['Entitlements']['com.apple.developer.healthkit'] = False
        with self.assertRaisesRegex(ValueError, 'HealthKit'):
            self.run_prepare()

    def test_invalid_tag_rejected(self):
        self.env['GITHUB_REF'] = 'refs/tags/ios-vbad'
        with self.assertRaisesRegex(ValueError, 'three-part version'):
            self.run_prepare()


if __name__ == '__main__':
    unittest.main()
