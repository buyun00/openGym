import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('monitor', pathlib.Path(__file__).with_name('ci-testflight.py'))
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.state = 'VALID'
        self.exempt = False
        self.beta = 'IN_BETA_TESTING'
        self.linked = True
        self.version = '1.0.1'
        self.posts = []
        self.group = {'id': 'group', 'attributes': {'hasAccessToAllBuilds': False}}

    def api(self, path, body=None):
        if body:
            self.posts.append(body)
            self.linked = True
            return {}
        if path.startswith('/v1/builds?'):
            return {'data': [{'id': 'build', 'attributes': {'processingState': self.state,
                    'usesNonExemptEncryption': self.exempt}, 'relationships': {
                    'preReleaseVersion': {'data': {'id': 'release'}}, 'buildBetaDetail': {'data': {'id': 'detail'}}}}],
                    'included': [{'id': 'release', 'attributes': {'version': self.version}},
                                 {'id': 'detail', 'attributes': {'internalBuildState': self.beta}}]}
        return {'data': [{'id': 'build'}] if self.linked else []}

    def check(self):
        return monitor.check_build(self.api, 'app', self.group, '1.0.1', '10.1')

    def test_ready_build_is_not_readded(self):
        self.assertEqual(self.check()[1], 'build')
        self.assertEqual(self.posts, [])

    def test_wrong_version_never_distributed(self):
        self.version = '1.0.0'
        self.assertIsNone(self.check()[1])
        self.assertEqual(self.posts, [])

    def test_processing_waits(self):
        self.state = 'PROCESSING'
        self.assertIsNone(self.check()[1])

    def test_invalid_build_fails(self):
        self.state = 'INVALID'
        with self.assertRaisesRegex(RuntimeError, 'rejected'):
            self.check()

    def test_missing_compliance_fails(self):
        self.exempt = None
        with self.assertRaisesRegex(RuntimeError, 'compliance'):
            self.check()

    def test_addition_requires_readback(self):
        self.linked = False
        self.assertIsNone(self.check()[1])
        self.assertEqual(len(self.posts), 1)
        self.assertEqual(self.check()[1], 'build')

    def test_automatic_group_waits_without_mutation(self):
        self.linked = False
        self.group['attributes']['hasAccessToAllBuilds'] = True
        self.assertIsNone(self.check()[1])
        self.assertEqual(self.posts, [])


if __name__ == '__main__':
    unittest.main()
