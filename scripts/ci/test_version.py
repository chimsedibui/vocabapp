import unittest
from version import next_version


class VersionTests(unittest.TestCase):
    def test_initial_release_uses_source_version(self):
        self.assertEqual(next_version('0.2.0+2', []), ('0.2.0', 2))

    def test_repeated_push_increments_patch_and_build(self):
        self.assertEqual(next_version('0.2.0+2', ['v0.2.0']), ('0.2.1', 3))

    def test_explicit_minor_and_major(self):
        self.assertEqual(next_version('0.2.3+5', ['v0.2.3'], 'minor'), ('0.3.0', 6))
        self.assertEqual(next_version('0.2.3+5', ['v0.2.3'], 'major'), ('1.0.0', 6))

    def test_manually_selected_newer_version_is_preserved(self):
        self.assertEqual(next_version('0.4.0+8', ['v0.2.3']), ('0.4.0', 8))


if __name__ == '__main__':
    unittest.main()
