"""Exercise revocation against socket fixtures, without credentials or a network."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "flake-parts/hosts/nixos/ssh-control-revoke.sh"


class RevokeTests(unittest.TestCase):
    def test_only_managed_sockets_are_closed_including_legacy_github(self):
        self.assertTrue(SCRIPT.exists(), "Missing SSH connection revoker")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bindir = root / "bin"
            bindir.mkdir()
            log = root / "calls"
            ssh = bindir / "ssh"
            ssh.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_LOG"\n')
            ssh.chmod(0o755)
            sockets = []
            try:
                for name in ["ssh-session-one", "ssh-session-two", "ssh-github-old", "other-agent"]:
                    sock = socket.socket(socket.AF_UNIX)
                    sock.bind(str(root / name))
                    sockets.append(sock)
                (root / "ssh-session-file").write_text("not a socket")
                (root / "ssh-session-link").symlink_to(root / "other-agent")
                env = dict(os.environ, XDG_RUNTIME_DIR=directory, TEST_LOG=str(log),
                           PATH=str(bindir) + ":" + os.environ["PATH"])
                subprocess.run(["bash", str(SCRIPT)], env=env, check=True)
                calls = log.read_text().splitlines()
                self.assertEqual(len(calls), 3)
                for name in ["ssh-session-one", "ssh-session-two", "ssh-github-old"]:
                    self.assertTrue(any(f"-S {root / name} -O exit" in call for call in calls))
                self.assertTrue(all("-F /dev/null" in call for call in calls))
            finally:
                for sock in sockets:
                    sock.close()

    def test_missing_runtime_directory_fails_instead_of_scanning_elsewhere(self):
        self.assertTrue(SCRIPT.exists(), "Missing SSH connection revoker")
        env = os.environ.copy()
        env.pop("XDG_RUNTIME_DIR", None)
        result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
