"""Exercise the signing wrapper without credentials or physical hardware."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "flake-parts/hosts/nixos/gpg-sign.sh"


class SigningTest(unittest.TestCase):
    def run_wrapper(self, args, agent_reply="OK"):
        self.assertTrue(WRAPPER.exists(), "Nix-managed signing wrapper is missing")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for command, body in {
                "gpg-connect-agent": 'printf "%s\\n" "$GNUPGHOME" "$@" >> "$TRACE"; printf "%s\\n" "$AGENT_REPLY"',
                "gpg": 'printf "%s\\n" "$GNUPGHOME" "$@" >> "$TRACE"',
            }.items():
                executable = root / command
                executable.write_text("#!/bin/sh\n" + body + "\n")
                executable.chmod(0o755)
            trace = root / "trace"
            env = dict(os.environ, HOME=str(root), GNUPGHOME="/stale/signing",
                       PATH=f"{root}:{os.environ['PATH']}", TRACE=str(trace),
                       AGENT_REPLY=agent_reply)
            result = subprocess.run(["bash", str(WRAPPER), *args],
                                    env=env, capture_output=True, text=True)
            lines = trace.read_text().splitlines()
            return result, lines, str(root / ".gnupg")

    def test_signing_uses_one_home_and_relearns_the_inserted_card(self):
        result, lines, home = self.run_wrapper(["-bsau", "test-key"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lines, [home, "SCD SERIALNO", "LEARN --force", "/bye",
                                home, "--pinentry-mode", "ask", "-bsau", "test-key"])

    def test_missing_card_fails_without_attempting_a_signature(self):
        result, lines, home = self.run_wrapper(["--detach-sign"],
                                              "ERR 100696144 No such device")
        self.assertEqual(result.returncode, 1)
        self.assertIn("cannot access the OpenPGP YubiKey", result.stderr)
        self.assertEqual(lines, [home, "SCD SERIALNO", "LEARN --force", "/bye"])

    def test_verification_does_not_require_a_card(self):
        result, lines, home = self.run_wrapper(["--verify", "signature", "message"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lines, [home, "--pinentry-mode", "ask", "--verify",
                                "signature", "message"])


if __name__ == "__main__":
    unittest.main()
