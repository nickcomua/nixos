"""Exercise the askpass wrapper without hardware or real credentials."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "flake-parts/hosts/nixos/ssh-askpass.sh"


class AskpassTests(unittest.TestCase):
    def run_prompt(self, prompt, hint="", status=0, notify_status=0,
                   notify_id="42", notify_delay=0.0):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            askpass = tmp / "askpass"
            askpass.write_text('#!/bin/sh\nprintf synthetic-response\nexit "$TEST_STATUS"\n')
            askpass.chmod(0o700)
            notify = tmp / "notify"
            notify.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$TEST_LOG"\nsleep "$TEST_DELAY"\n[ "$TEST_NOTIFY_STATUS" = 0 ] || exit "$TEST_NOTIFY_STATUS"\nprintf "%s\\n" "$TEST_ID"\n')
            notify.chmod(0o700)
            close = tmp / "close"
            close.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$TEST_LOG.closed"\n')
            close.chmod(0o700)
            wrapper = tmp / "wrapper"
            source = SCRIPT.read_text()
            for token, value in {"@askpass@": str(askpass), "@notify@": str(notify),
                                 "@gdbus@": str(close), "@sleep@": "sleep"}.items():
                source = source.replace(token, value)
            wrapper.write_text(source)
            log = tmp / "log"
            env = dict(os.environ, SSH_ASKPASS_PROMPT=hint, TEST_STATUS=str(status),
                       TEST_LOG=str(log), TEST_ID=notify_id, TEST_DELAY=str(notify_delay),
                       TEST_NOTIFY_STATUS=str(notify_status))
            with subprocess.Popen(["bash", str(wrapper), prompt], env=env,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True) as proc:
                try:
                    if hint == "none" and notify_status == 0:
                        deadline = time.monotonic() + 3
                        while not log.exists() and proc.poll() is None and time.monotonic() < deadline:
                            time.sleep(0.01)
                        self.assertTrue(log.exists(), "notification was not sent")
                        self.assertIsNone(proc.poll(), "notifier must wait for signing completion")
                        proc.terminate()  # OpenSSH's notify_complete contract.
                    stdout, stderr = proc.communicate(timeout=3)
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.communicate()
                result = subprocess.CompletedProcess(proc.args, proc.returncode, stdout, stderr)
            closed = tmp / "log.closed"
            self.closed = closed.read_text() if closed.exists() else ""
            return result, log.read_text() if log.exists() else ""

    def test_pin_response_is_not_captured_or_given_a_detached_notification(self):
        result, log = self.run_prompt("Enter PIN and confirm user presence for ED25519-SK key TEST: ")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "synthetic-response")
        self.assertEqual(log, "")

    def test_touch_only_closes_exact_notification_on_completion(self):
        result, log = self.run_prompt("Confirm user presence for key TEST", "none")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("Touch your YubiKey", log)
        self.assertIn("org.freedesktop.Notifications.CloseNotification\n42\n", self.closed)

    def test_termination_during_notification_creation_still_closes_it(self):
        result, _ = self.run_prompt("Confirm user presence", "none", notify_delay=0.2)
        self.assertEqual(result.returncode, 0)
        self.assertIn("CloseNotification\n42\n", self.closed)

    def test_notification_failure_does_not_block_signing(self):
        result, _ = self.run_prompt("Confirm user presence", "none", notify_status=1)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.closed, "")

    def test_invalid_notification_id_is_not_sent_to_dbus(self):
        result, _ = self.run_prompt("Confirm user presence", "none", notify_id="not-an-id")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.closed, "")

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
