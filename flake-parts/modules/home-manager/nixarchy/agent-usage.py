#!/usr/bin/env python3
"""Print the Grok or Muse (Meta AI) usage record as JSON.

Hermes is how both subscriptions are actually spent on this machine, and it
persists per-session model usage in ~/.hermes/state.db
(session_model_usage: billing_provider 'xai-oauth' for Grok, 'meta-ai' for
Muse). Neither xAI nor Meta exposes subscription rate limits to local
tools, so these records carry local token stats only and say so; the
agents panel renders that exactly like Claude's signed-out fallback.

Usage: agent-usage.py <grok|muse> [--force] [--limits-only]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any

AGENTS = {
    "grok": {
        "name": "Grok",
        "provider": "xai-oauth",
        "model_prefix": "grok-",
        "auth_help": (
            "xAI does not expose SuperGrok subscription limits to local "
            "tools, so this tab shows token usage Hermes recorded locally."
        ),
    },
    "muse": {
        "name": "Muse (Meta AI)",
        "provider": "meta-ai",
        "model_prefix": "muse-",
        "auth_help": (
            "Meta AI does not expose Muse subscription limits to local "
            "tools, so this tab shows token usage Hermes recorded locally."
        ),
    },
}


def hermes_db() -> Path:
    override = os.environ.get("HERMES_STATE_DB")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".hermes" / "state.db"


def empty_bucket() -> dict[str, int]:
    return {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 0,
        "cacheCreationInputTokens": 0,
    }


def collect(db_path: Path, agent_id: str) -> dict[str, Any]:
    cfg = AGENTS[agent_id]
    today = dt.datetime.now().date()
    recent_dates = [(today - dt.timedelta(days=off)).isoformat() for off in range(6, -1, -1)]
    recent = {day: 0 for day in recent_dates}

    stats: dict[str, Any] = {
        "todayPrompts": 0,
        "todaySessions": 0,
        "todayTotalTokens": 0,
        "todayTokensByModel": {},
        "recentDays": [{"date": day, "messageCount": 0} for day in recent_dates],
        "modelUsage": {},
        "totalPrompts": 0,
        "totalSessions": 0,
        "activeDays": 0,
        "activeDates": [],
    }
    if not db_path.is_file():
        return stats

    conn = sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True, timeout=5)
    try:
        conn.execute("PRAGMA query_only = ON")
        rows = conn.execute(
            """
            SELECT model,
                   date(last_seen, 'unixepoch', 'localtime') AS day,
                   COUNT(DISTINCT session_id),
                   SUM(api_call_count),
                   SUM(input_tokens),
                   SUM(output_tokens) + SUM(reasoning_tokens),
                   SUM(cache_read_tokens),
                   SUM(cache_write_tokens)
            FROM session_model_usage
            WHERE billing_provider = ? OR model LIKE ?
            GROUP BY model, day
            """,
            (cfg["provider"], cfg["model_prefix"] + "%"),
        ).fetchall()
    except sqlite3.Error:
        return stats
    finally:
        conn.close()

    # Sessions are counted per (model, day) row above; distinct-session
    # totals need their own pass so a session spanning models/days is
    # counted once.
    sessions_total: set[str] = set()
    sessions_today: set[str] = set()
    active_days: set[str] = set()
    today_str = today.isoformat()
    conn = sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True, timeout=5)
    try:
        conn.execute("PRAGMA query_only = ON")
        for session_id, day in conn.execute(
            """
            SELECT session_id, date(last_seen, 'unixepoch', 'localtime')
            FROM session_model_usage
            WHERE billing_provider = ? OR model LIKE ?
            """,
            (cfg["provider"], cfg["model_prefix"] + "%"),
        ):
            sessions_total.add(session_id)
            if day:
                active_days.add(day)
            if day == today_str:
                sessions_today.add(session_id)
    except sqlite3.Error:
        pass
    finally:
        conn.close()

    for model, day, _sess, calls, inp, outp, cache_r, cache_w in rows:
        inp, outp, cache_r, cache_w = (int(v or 0) for v in (inp, outp, cache_r, cache_w))
        total = inp + outp + cache_r + cache_w
        bucket = stats["modelUsage"].setdefault(str(model), empty_bucket())
        bucket["inputTokens"] += inp
        bucket["outputTokens"] += outp
        bucket["cacheReadInputTokens"] += cache_r
        bucket["cacheCreationInputTokens"] += cache_w
        stats["totalPrompts"] += int(calls or 0)
        if day in recent:
            recent[day] += total
        if day == today_str:
            stats["todayPrompts"] += int(calls or 0)
            stats["todayTotalTokens"] += total
            by_model = stats["todayTokensByModel"]
            by_model[str(model)] = by_model.get(str(model), 0) + total

    stats["recentDays"] = [{"date": day, "messageCount": recent[day]} for day in recent_dates]
    stats["totalSessions"] = len(sessions_total)
    stats["todaySessions"] = len(sessions_today)
    stats["activeDates"] = sorted(active_days)
    stats["activeDays"] = len(active_days)
    return stats


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("agent", choices=sorted(AGENTS))
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limits-only", action="store_true")
    args = parser.parse_args()

    cfg = AGENTS[args.agent]
    stats = collect(hermes_db(), args.agent)
    record = {
        "schemaVersion": 1,
        "id": args.agent,
        "name": cfg["name"],
        "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "ready": stats["totalPrompts"] > 0,
        "hasLocalStats": True,
        "tierLabel": "",
        "usageStatusText": "Local stats only",
        "authHelpText": cfg["auth_help"],
        "limits": [],
    }
    record.update(stats)
    print(json.dumps(record, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
