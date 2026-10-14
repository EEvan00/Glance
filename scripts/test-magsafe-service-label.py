#!/usr/bin/env python3
"""Regressions for stale BTM identities across signing-team changes."""
import pathlib
import subprocess
import unittest

SCRIPT = pathlib.Path(__file__).with_name('magsafe-service-label.sh')

class MagSafeServiceLabelTests(unittest.TestCase):
    def label(self, team):
        return subprocess.check_output(
            ['bash', str(SCRIPT), 'io.github.EEvan00.Glance', team], text=True
        ).strip()

    def test_certificate_teams_do_not_reuse_a_cached_launch_constraint(self):
        self.assertEqual(self.label('8QXPQ4R5VC'),
                         'io.github.EEvan00.Glance.MagSafeLEDHelper.8QXPQ4R5VC')
        self.assertNotEqual(self.label('36H7N2MMRA'), self.label('8QXPQ4R5VC'))

    def test_adhoc_keeps_the_legacy_package_label(self):
        self.assertEqual(self.label('-'), 'io.github.EEvan00.Glance.MagSafeLEDHelper')

    def test_missing_certificate_team_cannot_silently_reuse_legacy_identity(self):
        for team in ('', 'not set', 'bad/team'):
            result = subprocess.run(['bash', str(SCRIPT), 'io.github.EEvan00.Glance', team],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, team)

if __name__ == '__main__':
    unittest.main()
