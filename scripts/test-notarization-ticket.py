#!/usr/bin/env python3
"""Exercise bounded ticket-network retries without Apple calls or credentials."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

class TicketRetryTests(unittest.TestCase):
    def run_case(self, codes):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            log = directory / 'calls'
            (directory / 'xcrun').write_text('''#!/usr/bin/env python3
import os, pathlib, sys
p = pathlib.Path(os.environ['FAKE_CALLS'])
calls = p.read_text().splitlines() if p.exists() else []
p.write_text('\u005cn'.join(calls + [' '.join(sys.argv[1:])]) + '\u005cn')
codes = [int(x) for x in os.environ['FAKE_CODES'].split(',')]
sys.exit(codes[min(len(calls), len(codes) - 1)])
''')
            (directory / 'xcrun').chmod(0o755)
            (directory / 'sleep').write_text('#!/bin/sh\nexit 0\n')
            (directory / 'sleep').chmod(0o755)
            env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ['PATH'],
                       FAKE_CALLS=str(log), FAKE_CODES=','.join(map(str, codes)))
            result = subprocess.run(['bash', '-c', 'source "$1"; stapler_with_retry validate "test app.pkg"',
                                     'test', str(ROOT / 'scripts/notarization-ticket.sh')],
                                    env=env, capture_output=True, text=True)
            return result, log.read_text().splitlines() if log.exists() else []

    def test_network_failure_then_success(self):
        result, calls = self.run_case([68, 68, 0])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 3)
        self.assertTrue(all(c == 'stapler validate test app.pkg' for c in calls))

    def test_non_network_failure_is_not_retried(self):
        result, calls = self.run_case([65, 0])
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertEqual(len(calls), 1)

    def test_network_failure_exhausts_bound_and_still_fails(self):
        result, calls = self.run_case([68])
        self.assertEqual(result.returncode, 68, result.stderr)
        self.assertEqual(len(calls), 4)

if __name__ == '__main__':
    unittest.main()
