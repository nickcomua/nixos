"""Integration tests using isolated homes; never touches the logged-in desktop."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('desktop', Path(__file__).parents[1] / 'flake-parts/modules/home-manager/nixarchy/config.py')
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)


class DesktopTests(unittest.TestCase):
    plugin_manifest = json.dumps({
        'schemaVersion': 1,
        'id': 'example',
        'name': 'Example',
        'version': '1.0.0',
        'author': 'Test',
        'license': 'MIT',
        'description': 'Test plugin',
        'kinds': ['overlay'],
        'entryPoints': {'overlay': 'Main.qml'},
    })

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.snapshot = self.root / 'snapshot'

    def put(self, rel, content):
        p = self.home / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        return p

    def capture(self):
        return d.capture(self.home, self.snapshot, pin=False)

    def test_roundtrip_plugins_theme_assets_and_enablement(self):
        self.put('.config/omarchy/shell.json', '{"plugins":{"example":{"enabled":true}}}')
        self.put('.config/omarchy/plugins/example/manifest.json', self.plugin_manifest)
        self.put('.config/omarchy/plugins/example/Main.qml', 'Item { property int value: 42 }')
        self.put('.config/omarchy/themes/custom/colors.toml', 'accent = "#123456"')
        self.put('.local/state/omarchy/current/theme.name', 'custom\n')
        asset = self.put('Pictures/background.png', 'image-fixture')
        (self.home / '.local/state/omarchy/current/background').symlink_to(asset)
        m = self.capture()
        d.read_manifest(self.snapshot)
        fresh = self.root / 'fresh'
        d.install(fresh, self.snapshot, m, d.resolve_sources(self.snapshot, m, {}))
        self.assertEqual(d.differences(fresh, m), [])
        self.assertEqual((fresh / '.local/state/omarchy/current/background').read_bytes(), asset.read_bytes())
        second = self.root / 'second'
        self.assertEqual(d.capture(fresh, second, pin=False), m)

    def test_nixi_agent_and_ddc_bus_settings_roundtrip(self):
        nixi = '{"agent":"codex","model":"gpt-6-astra","reasoningEffort":"low"}'
        ddc = '[global]\noptions: --ignore-bus 11\n'
        self.put('.config/omarchy/nixi.json', nixi)
        self.put('.config/ddcutil/ddcutilrc', ddc)
        manifest = self.capture()
        fresh = self.root / 'fresh'
        d.install(fresh, self.snapshot, manifest, {})
        self.assertEqual(json.loads((fresh / '.config/omarchy/nixi.json').read_text())['agent'], 'codex')
        self.assertEqual((fresh / '.config/ddcutil/ddcutilrc').read_text(), ddc)

    def test_seed_preserves_edits_restore_removes_extras_and_backup_keeps_them(self):
        path = '.config/omarchy/shell.json'
        self.put(path, '{"bar":"saved"}')
        m = self.capture()
        self.put(path, '{"bar":"edited"}')
        self.put('.config/omarchy/plugins/new/manifest.json', '{"id":"new"}')
        d.install(self.home, self.snapshot, m, {})
        self.assertIn(path, d.differences(self.home, m))
        backup = d.backup(self.home)
        d.install(self.home, self.snapshot, m, {}, overwrite=True)
        self.assertEqual(d.differences(self.home, m), [])
        self.assertFalse((self.home / '.config/omarchy/plugins/new').exists())
        self.assertEqual(json.loads((backup / 'files' / path).read_text()), {'bar': 'edited'})

    def test_invalid_config_does_not_replace_previous_export(self):
        self.put('.config/omarchy/shell.json', '{}')
        self.capture()
        original = (self.snapshot / 'manifest.json').read_bytes()
        self.put('.config/omarchy/shell.json', '{broken')
        with self.assertRaises(ValueError):
            d.capture(self.home, self.root / 'staging', pin=False)
        self.assertEqual((self.snapshot / 'manifest.json').read_bytes(), original)

    def test_credentials_and_unrelated_app_data_not_exported(self):
        self.put('.codex/auth.json', '{"token":"private"}')
        self.put('.config/floorp/profile', 'private')
        self.put('.config/omarchy/shell.json', '{}')
        m = self.capture()
        self.assertEqual(set(m['files']), {'.config/omarchy/shell.json'})
        self.put('.config/omarchy/shell.json', '{"plugin":{"api_key":"private"}}')
        with self.assertRaisesRegex(ValueError, 'credential-like'):
            d.capture(self.home, self.root / 'secret-stage', pin=False)

    def test_external_source_symlink_rejected(self):
        root = self.home / '.config/omarchy/plugins/example'
        self.put('.config/omarchy/plugins/example/manifest.json', self.plugin_manifest)
        private = self.put('.ssh/private', 'private')
        (root / 'escape').symlink_to(private)
        with self.assertRaisesRegex(ValueError, 'escapes'):
            self.capture()

    def test_clean_pin_reused_without_network_then_modified_source_vendored(self):
        self.put('.config/omarchy/plugins/example/manifest.json', self.plugin_manifest)
        src = self.put('.config/omarchy/plugins/example/Main.qml', 'Item {}')
        old = {'sources': {'plugins/example': dict(kind='git', url='https://example.test/plugin', rev='a'*40,
               hash='fixed', contentHash=d.tree_hash(src.parent))}}
        with patch.object(d, 'output', side_effect=AssertionError('unexpected network')):
            m = d.capture(self.home, self.snapshot, old)
        self.assertEqual(m['sources'], old['sources'])
        src.write_text('Item { property int changed: 1 }')
        m = d.capture(self.home, self.root / 'changed', old)
        self.assertEqual(m['sources']['plugins/example']['kind'], 'local')

    def test_snapshot_tampering_and_path_traversal_rejected(self):
        self.put('.config/omarchy/shell.json', '{}')
        m = self.capture()
        (self.snapshot / 'files/.config/omarchy/shell.json').write_text('{"edited":true}')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            d.read_manifest(self.snapshot)
        m['files'] = {'../../outside': 'bad'}
        d.json_write(self.snapshot / 'manifest.json', m)
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            d.read_manifest(self.snapshot)

    def test_lua_syntax_validated(self):
        self.put('.config/hypr/bindings.lua', 'this is not Lua !')
        with self.assertRaises(d.subprocess.CalledProcessError):
            self.capture()

    def test_restore_can_back_up_broken_live_json(self):
        self.put('.config/omarchy/shell.json', '{}')
        m = self.capture()
        self.put('.config/omarchy/shell.json', '{broken')
        saved = d.backup(self.home)
        d.install(self.home, self.snapshot, m, {}, overwrite=True)
        self.assertEqual((saved / 'files/.config/omarchy/shell.json').read_text(), '{broken')
        self.assertEqual(d.differences(self.home, m), [])

    def test_restored_store_sources_are_writable(self):
        src = self.root / 'store'
        src.mkdir()
        (src / 'Main.qml').write_text('Item {}')
        (src / 'Main.qml').chmod(0o444)
        dest = self.root / 'live'
        d.copy_tree(src, dest)
        self.assertTrue((dest / 'Main.qml').stat().st_mode & 0o200)

    def test_app_apply_updates_imported_snapshot_without_exporting_other_edits(self):
        repo = self.root / 'repo'
        snapshot = repo / d.SNAPSHOT_REL
        self.put('.config/omarchy/shell.json', '{"saved":true}')
        d.capture(self.home, snapshot, pin=False)
        self.put('.config/omarchy/shell.json', '{"saved":false}')
        self.put('.config/nixarchy/apps.nix', '{ programs.nixarchy.apps.firefox.enable = true; }')
        original = d.run
        calls = []
        def checked_run(*args, **kwargs):
            calls.append(args)
            if args[0] in ('jj', 'nh') or args[:2] == ('nix', 'eval'):
                return None
            return original(*args, **kwargs)
        with patch.object(d, 'run', side_effect=checked_run):
            d.apply_apps(self.home, repo)
        m = d.read_manifest(snapshot)
        self.assertIn('.config/nixarchy/apps.nix', m['files'])
        self.assertEqual(json.loads((snapshot / 'files/.config/omarchy/shell.json').read_text()), {'saved': True})
        self.assertEqual(calls[-1], ('nh', 'os', 'switch', str(repo), '--hostname', 'nixos',
                                     '--elevation-strategy', '/run/wrappers/bin/pkexec'))

    def test_baseline_snapshot_valid(self):
        baseline = Path(__file__).parents[1] / d.SNAPSHOT_REL
        d.read_manifest(baseline)

    def test_jsonc_comments_preserve_urls_and_reject_bad_syntax(self):
        p = self.put('.config/omarchy/extensions/test.jsonc',
                     '{ // comment\n "url": "https://example.test/a,b}", /* block */ "items": [1,], }')
        d.validate(p)
        p.write_text('{"bad": }')
        with self.assertRaises(ValueError):
            d.validate(p)


if __name__ == '__main__':
    unittest.main()
