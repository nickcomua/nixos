"""Exercise the memory-warning script without creating real memory pressure."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'flake-parts/hosts/nixos/memory-warning.sh'


class MemoryWarningTests(unittest.TestCase):
    def test_warning_cooldown_and_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            notify = root / 'notify'
            notify.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$NOTIFY_LOG"\n')
            notify.chmod(0o755)
            script = root / 'warning.sh'
            script.write_text(SCRIPT.read_text().replace('@notify@', str(notify)))
            meminfo = root / 'meminfo'
            log = root / 'notifications'
            env = dict(os.environ, XDG_RUNTIME_DIR=directory, NOTIFY_LOG=str(log))

            def check(available, swap_free, swap_total=1000):
                meminfo.write_text(f'MemTotal: 1000 kB\nMemAvailable: {available} kB\nSwapTotal: {swap_total} kB\nSwapFree: {swap_free} kB\n')
                subprocess.run(['bash', str(script), str(meminfo)], env=env, check=True)

            check(500, 500)
            self.assertFalse(log.exists())
            check(100, 100)
            self.assertIn('Memory pressure', log.read_text())
            check(100, 100)
            self.assertEqual(len(log.read_text().splitlines()), 1)
            check(500, 500)
            check(100, 100)
            self.assertEqual(len(log.read_text().splitlines()), 2)
            check(500, 500)
            check(100, 500)
            self.assertEqual(len(log.read_text().splitlines()), 3)
            check(500, 500)
            check(500, 100)
            self.assertEqual(len(log.read_text().splitlines()), 4)
            check(500, 500)
            check(100, 0, swap_total=0)
            self.assertEqual(len(log.read_text().splitlines()), 5)


if __name__ == '__main__':
    unittest.main()
