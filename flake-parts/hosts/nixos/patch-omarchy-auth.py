"""Add an independent, touch-only U2F flow to the pinned Omarchy lock plugin."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one upstream anchor: {old!r}")
    return text.replace(old, new, 1)


def patch_service(text):
    text = replace_once(text, '  property bool fingerprintConfigured: false',
                        '  property bool securityKeyConfigured: false\n  property bool fingerprintConfigured: false')
    text = replace_once(text, '    if (passwordPam.active) passwordPam.abort()',
                        '    securityKeyRetryTimer.stop()\n    if (securityKeyPam.active) securityKeyPam.abort()\n    if (passwordPam.active) passwordPam.abort()')
    text = replace_once(text, '  function startFingerprint() {', '''  function startSecurityKey() {
    if (!lockRequested || !sessionLock.secure || !securityKeyConfigured || securityKeyPam.active) return
    securityKeyPam.start()
  }

  function startFingerprint() {''')
    text = replace_once(text, '        root.startFingerprint()',
                        '        root.startSecurityKey()\n        root.startFingerprint()')
    # Both the lock surface and the preview use this same view.
    if text.count('fingerprintConfigured: root.fingerprintConfigured') != 2:
        raise ValueError("Expected lock and preview fingerprint bindings")
    text = text.replace('fingerprintConfigured: root.fingerprintConfigured',
                        'securityKeyConfigured: root.securityKeyConfigured\n        fingerprintConfigured: root.fingerprintConfigured')
    text = replace_once(text, '  PamContext {\n    id: passwordPam', '''  FileView {
    path: "/etc/pam.d/omarchy-lock-u2f"
    watchChanges: true
    printErrors: false
    onLoaded: { root.securityKeyConfigured = true; root.startSecurityKey() }
    onLoadFailed: {
      root.securityKeyConfigured = false
      securityKeyRetryTimer.stop()
      if (securityKeyPam.active) securityKeyPam.abort()
    }
    onFileChanged: reload()
  }

  PamContext {
    id: securityKeyPam
    config: "omarchy-lock-u2f"
    user: root.userName
    // Never route a key PIN or an unexpected password prompt into the password flow.
    onResponseRequiredChanged: { if (responseRequired) abort() }
    onCompleted: function(result) {
      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else if (root.securityKeyConfigured) securityKeyRetryTimer.restart()
    }
    onError: function(error) {
      if (root.lockRequested && root.securityKeyConfigured) securityKeyRetryTimer.restart()
    }
  }

  Timer {
    id: securityKeyRetryTimer
    interval: 2000
    repeat: false
    onTriggered: root.startSecurityKey()
  }

  PamContext {
    id: passwordPam''')
    return text


def patch_view(text):
    text = replace_once(text, '  property bool fingerprintConfigured: false',
                        '  property bool securityKeyConfigured: false\n  property bool fingerprintConfigured: false')
    return replace_once(text, 'readonly property string placeholderText: Commons.I18n.t("lock.enterPassword")',
                        'readonly property string placeholderText: securityKeyConfigured ? "Touch key or enter password" : Commons.I18n.t("lock.enterPassword")')


def patch_polkit(text):
    return replace_once(text,
                        '(root.submitted ? I18n.t("polkit.checking") : I18n.t("polkit.enterPassword"))',
                        '(root.submitted ? I18n.t("polkit.checking") : (!root.responseRequired ? "Touch security key" : I18n.t("polkit.enterPassword")))')


def apply(root):
    for relative, transform in (
        ("shell/plugins/lock/Service.qml", patch_service),
        ("shell/plugins/lock/LockView.qml", patch_view),
        ("shell/plugins/polkit/PolkitAgent.qml", patch_polkit),
    ):
        path = root / relative
        path.write_text(transform(path.read_text()))


if __name__ == "__main__":
    apply(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
