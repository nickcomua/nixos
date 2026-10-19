import importlib.util
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "flake-parts/modules/home-manager/nixarchy/agent-usage.py"
PATCHER = ROOT / "flake-parts/hosts/nixos/patch-omarchy-agent-usage.py"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AgentUsageCollectorTest(unittest.TestCase):
    def setUp(self):
        self.mod = load("agent_usage", COLLECTOR)
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "state.db"
        conn = sqlite3.connect(self.db)
        conn.execute(
            """CREATE TABLE session_model_usage (
                 session_id TEXT, model TEXT, billing_provider TEXT,
                 billing_base_url TEXT, billing_mode TEXT, task TEXT,
                 api_call_count INTEGER, input_tokens INTEGER,
                 output_tokens INTEGER, cache_read_tokens INTEGER,
                 cache_write_tokens INTEGER, reasoning_tokens INTEGER,
                 estimated_cost_usd REAL, actual_cost_usd REAL,
                 cost_status TEXT, cost_source TEXT,
                 first_seen REAL, last_seen REAL)"""
        )
        import datetime as dt

        today = dt.datetime.now().replace(hour=12).timestamp()
        old = today - 3 * 86400
        rows = [
            ("s1", "grok-4.7", "xai-oauth", 5, 100, 50, 10, 0, 5, today),
            ("s1", "grok-4.7", "xai-oauth", 2, 40, 10, 0, 0, 0, old),
            ("s2", "muse-wonder-1.0", "meta-ai", 3, 200, 80, 20, 0, 10, today),
            ("s3", "gpt-6.1-sol", "openai-codex", 9, 999, 999, 0, 0, 0, today),
        ]
        for sid, model, prov, calls, i, o, cr, cw, r, ts in rows:
            conn.execute(
                "INSERT INTO session_model_usage VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid, model, prov, "", "", "", calls, i, o, cr, cw, r, 0, 0, "", "", ts, ts),
            )
        conn.commit()
        conn.close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_grok_record_counts_only_xai(self):
        stats = self.mod.collect(self.db, "grok")
        self.assertEqual(stats["totalPrompts"], 7)
        self.assertEqual(stats["totalSessions"], 1)
        self.assertEqual(stats["todayPrompts"], 5)
        self.assertEqual(stats["modelUsage"]["grok-4.7"]["outputTokens"], 65)
        self.assertNotIn("gpt-6.1-sol", stats["modelUsage"])

    def test_muse_record_counts_only_meta(self):
        stats = self.mod.collect(self.db, "muse")
        self.assertEqual(stats["totalPrompts"], 3)
        self.assertEqual(stats["todayTotalTokens"], 310)

    def test_missing_db_is_empty_not_error(self):
        stats = self.mod.collect(Path(self.tmp.name) / "nope.db", "grok")
        self.assertEqual(stats["totalPrompts"], 0)

    def test_cli_prints_record_contract(self):
        import os

        env = dict(os.environ, HERMES_STATE_DB=str(self.db))
        out = subprocess.run(
            [sys.executable, str(COLLECTOR), "muse", "--force"],
            capture_output=True, text=True, env=env, check=True,
        )
        record = json.loads(out.stdout)
        self.assertEqual(record["id"], "muse")
        self.assertTrue(record["ready"])
        self.assertEqual(record["limits"], [])


class AgentUsagePatchTest(unittest.TestCase):
    def test_patch_widens_glob_once(self):
        mod = load("patch_agent_usage", PATCHER)
        upstream = (
            'for collector in "$OMARCHY_PATH"/bin/omarchy-agent-usage-*; do\n'
            "  [[ -x $collector ]] || continue\n"
            '  agent="${collector##*/omarchy-agent-usage-}"\n'
            '  [[ $agent == "update" ]] && continue\n'
        )
        patched = mod.patch_update(upstream)
        self.assertIn("/etc/profiles/per-user/", patched)
        self.assertIn("_seen_agents", patched)
        self.assertEqual(mod.patch_update(patched), patched)


if __name__ == "__main__":
    unittest.main()
