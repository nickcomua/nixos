"""Tests for the cloned nick.agents Omarchy plugin in the desktop snapshot."""

import importlib.util
import json
from pathlib import Path
import sqlite3
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).parents[1]
PLUGIN = ROOT / "flake-parts/hosts/nixos/desktop/sources/plugins/nick.agents"


def load_collector():
    spec = importlib.util.spec_from_file_location("nick_agents_collect", PLUGIN / "scripts/collect.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AgentsPluginTests(unittest.TestCase):
    def test_manifest_enables_all_five_providers(self):
        manifest = json.loads((PLUGIN / "manifest.json").read_text())
        providers = manifest["barWidget"]["defaults"]["providers"]
        self.assertEqual(set(providers), {"claude", "codex", "fireworks", "grok", "muse"})
        self.assertTrue(all(spec["enabled"] for spec in providers.values()))

    def test_main_uses_plugin_owned_update_script(self):
        main = (PLUGIN / "Main.qml").read_text()
        self.assertIn('Qt.resolvedUrl("scripts/update-usage")', main)
        self.assertNotIn('["omarchy-agent-usage-update"]', main)
        for script in ("update-usage", "collect.py"):
            path = PLUGIN / "scripts" / script
            self.assertTrue(path.is_file())
            self.assertTrue(path.stat().st_mode & stat.S_IXUSR)

    def test_scripts_parse(self):
        collect = load_collector()
        self.assertEqual(set(collect.AGENTS), {"grok", "muse"})
        subprocess.run(["bash", "-n", str(PLUGIN / "scripts/update-usage")], check=True)

    def test_muse_limits_follow_cli_contract(self):
        collect = load_collector()
        limits = collect.muse_usage_limits(
            {
                "window": {"usedPercent": 39, "resetsAtMs": 1792435082000, "windowDurationMins": 300},
                "weekly": {"usedPercent": 48, "resetsAtMs": 1792972800000},
            }
        )
        self.assertEqual([limit["title"] for limit in limits], ["Session", "Weekly"])
        self.assertEqual([limit["percent"] for limit in limits], [0.39, 0.48])
        self.assertTrue(all(limit["resetsAt"].endswith("+00:00") for limit in limits))

    def test_hermes_stats_are_split_by_provider(self):
        collect = load_collector()
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / "state.db"
            conn = sqlite3.connect(db)
            conn.execute(
                """
                CREATE TABLE session_model_usage (
                    session_id TEXT, model TEXT, billing_provider TEXT,
                    api_call_count INTEGER, input_tokens INTEGER,
                    output_tokens INTEGER, reasoning_tokens INTEGER,
                    cache_read_tokens INTEGER, cache_write_tokens INTEGER,
                    last_seen REAL
                )
                """
            )
            now = 1792400000
            conn.executemany(
                "INSERT INTO session_model_usage VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    ("g1", "grok-4", "xai-oauth", 2, 100, 20, 5, 10, 0, now),
                    ("m1", "muse-wonder-1.0", "meta-ai", 3, 200, 30, 0, 0, 0, now),
                ],
            )
            conn.commit()
            conn.close()
            grok = collect.collect_stats(db, "grok")
            muse = collect.collect_stats(db, "muse")
        self.assertEqual(grok["totalPrompts"], 2)
        self.assertEqual(grok["modelUsage"]["grok-4"]["outputTokens"], 25)
        self.assertEqual(muse["totalPrompts"], 3)
        self.assertNotIn("grok-4", muse["modelUsage"])


if __name__ == "__main__":
    unittest.main()
