#!/usr/bin/env python3
"""Offline regression tests for exact, canonical application-icon packaging."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
# User-approved public 2.0.1 Build 19 icon. Changing it requires a product decision.
APPROVED_SHA256 = 'ea75fc84611281f4a5efd9664c89407f3e8bba6a0febd2317766fbebdad37817'


class AppIconTests(unittest.TestCase):
    def test_canonical_icon_is_the_approved_public_release_asset(self):
        source = ROOT / 'Support/AppIcon.icns'
        self.assertTrue(source.is_file(), 'Approved release icon must be the checked-in canonical asset')
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), APPROVED_SHA256)

    def test_old_svg_cannot_be_selected_again(self):
        self.assertFalse((ROOT / 'Support/AppIcon.svg').exists(), 'Retired icon source must be removed')

    def run_packager(self, alteration=None):
        script = ROOT / 'scripts/package-app-icon.sh'
        self.assertTrue(script.is_file(), 'Missing canonical-icon packager')
        with tempfile.TemporaryDirectory(prefix='GlanceIconTest-') as folder:
            fixture = Path(folder)
            (fixture / 'scripts').mkdir()
            (fixture / 'Support').mkdir()
            target = fixture / 'Resources'
            target.mkdir()
            shutil.copy2(script, fixture / 'scripts/package-app-icon.sh')
            shutil.copy2(ROOT / 'Support/AppIcon.icns', fixture / 'Support/AppIcon.icns')
            shutil.copy2(ROOT / 'Support/AppIcon.sha256', fixture / 'Support/AppIcon.sha256')
            if alteration == 'changed':
                with (fixture / 'Support/AppIcon.icns').open('ab') as file:
                    file.write(b'changed')
            elif alteration == 'missing':
                (fixture / 'Support/AppIcon.icns').unlink()
                (fixture / 'Support/AppIcon.svg').write_text('<svg/>')
            result = subprocess.run(['bash', str(fixture / 'scripts/package-app-icon.sh'), str(target)],
                                    text=True, capture_output=True)
            icon = target / 'AppIcon.icns'
            return result, icon.read_bytes() if icon.exists() else None

    def test_packaging_preserves_approved_icon_bytes(self):
        result, data = self.run_packager()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(hashlib.sha256(data).hexdigest(), APPROVED_SHA256)

    def test_changed_icon_blocks_packaging(self):
        result, data = self.run_packager('changed')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checksum', result.stderr.lower())
        self.assertIsNone(data)

    def test_missing_icon_never_falls_back_to_old_svg(self):
        result, data = self.run_packager('missing')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing', result.stderr.lower())
        self.assertIsNone(data)


if __name__ == '__main__':
    unittest.main()
