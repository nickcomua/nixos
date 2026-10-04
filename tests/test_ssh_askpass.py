"""Exercise the askpass wrapper without hardware or real credentials."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "flake-parts/hosts/nixos/ssh-askpass.sh"


class AskpassTests(unittest.TestCase):
    def run_prompt(self, prompt, hint="", status=0):
        self.assertTrue(SCRIPT.exists(), "touch-aware askpass wrapper is missing")
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            askpass = tmp / "askpass"
            askpass.write_text('#!/bin/sh\nprintf synthetic-response\nexit "$TEST_STATUS"\n')
            askpass.chmod(0o700)
            notify = tmp / "notify"
            notify.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$TEST_LOG"\n')
            notify.chmod(0o700)
            wrapper = tmp / "wrapper"
            wrapper.write_text(SCRIPT.read_text().replace("@askpass@", str(askpass)).replace("@notify@", str(notify)))
            log = tmp / "log"
            env = dict(os.environ, SSH_ASKPASS_PROMPT=hint, TEST_STATUS=str(status), TEST_LOG=str(log))
            result = subprocess.run(["bash", str(wrapper), prompt], env=env, capture_output=True, text=True)
            return result, log.read_text() if log.exists() else ""

    def test_pin_then_touch_notification(self):
        result, log = self.run_prompt("Enter PIN and confirm user presence for ED25519-SK key TEST: ")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "synthetic-response")
        self.assertIn("Touch your YubiKey", log)

    def test_touch_only_never_asks_for_password(self):
        result, log = self.run_prompt("Confirm user presence for key TEST", "none")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("Touch your YubiKey", log)

    def test_cancel_does_not_request_touch(self):
        result, log = self.run_prompt("Enter PIN and confirm user presence for key TEST", status=1)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(log, "")

    def test_regular_passphrase_does_not_request_touch(self):
        result, log = self.run_prompt("Enter passphrase for key TEST")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "synthetic-response")
        self.assertEqual(log, "")


if __name__ == "__main__":
    unittest.main()
