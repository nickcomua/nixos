import importlib.util
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("omarchy_auth", ROOT / "flake-parts/hosts/nixos/patch-omarchy-auth.py")
assert spec is not None and spec.loader is not None
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)
SOURCE = Path(os.environ["OMARCHY_SOURCE"])


class SecurityKeyLockTests(unittest.TestCase):
    def test_automatic_key_flow_is_separate_from_password_and_fingerprint(self):
        text = auth.patch_service((SOURCE / "shell/plugins/lock/Service.qml").read_text())
        self.assertIn('config: "omarchy-lock-u2f"', text)
        self.assertIn('config: "omarchy-lock-password"', text)
        self.assertIn('config: "omarchy-lock-fingerprint"', text)
        self.assertIn('if (!lockRequested || !sessionLock.secure || !securityKeyConfigured || securityKeyPam.active) return', text)
        self.assertIn('root.startSecurityKey()\n        root.startFingerprint()', text)
        self.assertIn('if (securityKeyPam.active) securityKeyPam.abort()', text)
        self.assertIn('if (result === PamResult.Success) root.finishUnlock()', text)
        self.assertIn('onResponseRequiredChanged: { if (responseRequired) abort() }', text)
        self.assertEqual(text.count('securityKeyConfigured: root.securityKeyConfigured'), 2)

    def test_view_explains_key_or_password(self):
        text = auth.patch_view((SOURCE / "shell/plugins/lock/LockView.qml").read_text())
        self.assertIn('"Touch key or enter password"', text)

    def test_secure_lock_revokes_shared_ssh_connections(self):
        text = auth.patch_service((SOURCE / "shell/plugins/lock/Service.qml").read_text())
        self.assertIn('sshConnectionRevoke.running = true', text)
        self.assertIn('command: ["/run/current-system/sw/bin/ssh-control-revoke"]', text)
        self.assertIn('if (secure) {\n        sshConnectionRevoke.running = true', text)

    def test_polkit_does_not_claim_password_while_pam_waits_for_key(self):
        text = auth.patch_polkit((SOURCE / "shell/plugins/polkit/PolkitAgent.qml").read_text())
        self.assertIn('!root.responseRequired ? "Touch security key" : I18n.t("polkit.enterPassword")', text)

    def test_ssh_touch_notification_closes_when_sender_withdraws_it(self):
        text = auth.patch_notifications((SOURCE / "shell/plugins/notifications/Service.qml").read_text())
        self.assertIn('if (notification.appName === "SSH security key" && service.rowIndexFor(key) >= 0)', text)
        self.assertIn('service.closeToast(key, "closed")\n        return', text)

    def test_upstream_drift_fails_loudly(self):
        with self.assertRaises(ValueError):
            auth.patch_service("changed upstream source")
        with self.assertRaises(ValueError):
            auth.patch_notifications("changed upstream source")


if __name__ == "__main__":
    unittest.main()
