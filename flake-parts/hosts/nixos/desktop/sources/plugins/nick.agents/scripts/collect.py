#!/usr/bin/env python3
"""Collect Grok and Muse subscription records for the nick.agents panel.

Subscription limits come from the vendors' own CLIs:

* Grok: the `_x.ai/billing` extension on `grok agent stdio` (ACP).
* Muse: `usage/read` / `usage/changed` on `muse serve` (MSP). A fresh
  server has observed nothing, so the collector first tries `usage/read`
  after `session/start` and only then spends one minimal turn.

Token history is read from Hermes' local session database because both
subscriptions are normally driven through Hermes on this machine.

Usage: collect.py <grok|muse> [--force] [--limits-only]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import queue
import random
import shutil
import sqlite3
import subprocess
import threading
import time
import uuid
from pathlib import Path
from typing import Any

AGENTS = {
    "grok": {
        "name": "Grok",
        "provider": "xai-oauth",
        "model_prefix": "grok-",
        "cache_seconds": 180,
        "auth_help": "Run `grok login`, then refresh this panel.",
    },
    "muse": {
        "name": "Muse (Meta AI)",
        "provider": "meta-ai",
        "model_prefix": "muse-",
        "cache_seconds": 1800,
        "auth_help": "Run `muse`, sign in if prompted, then refresh this panel.",
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


def collect_stats(db_path: Path, agent_id: str) -> dict[str, Any]:
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

    try:
        conn = sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True, timeout=5)
    except sqlite3.Error:
        return stats
    try:
        conn.execute("PRAGMA query_only = ON")
        rows = conn.execute(
            """
            SELECT model,
                   date(last_seen, 'unixepoch', 'localtime') AS day,
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
        session_rows = conn.execute(
            """
            SELECT session_id, date(last_seen, 'unixepoch', 'localtime')
            FROM session_model_usage
            WHERE billing_provider = ? OR model LIKE ?
            """,
            (cfg["provider"], cfg["model_prefix"] + "%"),
        ).fetchall()
    except sqlite3.Error:
        return stats
    finally:
        conn.close()

    today_str = today.isoformat()
    sessions_total: set[str] = set()
    sessions_today: set[str] = set()
    active_days: set[str] = set()
    for session_id, day in session_rows:
        sessions_total.add(str(session_id))
        if day:
            active_days.add(str(day))
        if day == today_str:
            sessions_today.add(str(session_id))

    for model, day, calls, inp, outp, cache_r, cache_w in rows:
        inp, outp, cache_r, cache_w = (int(v or 0) for v in (inp, outp, cache_r, cache_w))
        total = inp + outp + cache_r + cache_w
        bucket = stats["modelUsage"].setdefault(str(model), empty_bucket())
        bucket["inputTokens"] += inp
        bucket["outputTokens"] += outp
        bucket["cacheReadInputTokens"] += cache_r
        bucket["cacheCreationInputTokens"] += cache_w
        stats["totalPrompts"] += int(calls or 0)
        if day in recent:
            recent[str(day)] += total
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


class RpcClient:
    """Line-delimited JSON-RPC over a child process' stdio."""

    def __init__(self, command: list[str]):
        self.process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
            cwd="/tmp",
        )
        self.messages: queue.Queue[str] = queue.Queue()
        self.notifications: list[dict[str, Any]] = []
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.messages.put(line)

    def send(self, payload: dict[str, Any]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(payload) + "\n")
        self.process.stdin.flush()

    def wait_for(self, request_id: int, timeout: float) -> dict[str, Any]:
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.messages.get(timeout=max(0.1, deadline - time.time()))
            message = json.loads(line)
            if "id" not in message and message.get("method"):
                self.notifications.append(message)
                continue
            if message.get("id") == request_id:
                if "error" in message:
                    raise RuntimeError(json.dumps(message["error"]))
                return message
        raise TimeoutError(f"request {request_id} timed out")

    def close(self) -> None:
        try:
            self.process.terminate()
            self.process.wait(timeout=5)
        except Exception:
            try:
                self.process.kill()
            except Exception:
                pass


def find_executable(name: str, fallbacks: list[Path]) -> str:
    found = shutil.which(name)
    if found:
        return found
    for candidate in fallbacks:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return name


def uuid7() -> str:
    milliseconds = int(time.time() * 1000) % (2**48)
    value = (
        (milliseconds << 80)
        | (0x7 << 76)
        | (random.getrandbits(12) << 64)
        | (0b10 << 62)
        | random.getrandbits(62)
    )
    return str(uuid.UUID(int=value))


def iso_from_ms(milliseconds: int) -> str:
    return dt.datetime.fromtimestamp(milliseconds / 1000, dt.timezone.utc).isoformat()


def probe_grok() -> dict[str, Any]:
    executable = find_executable(
        "grok", [Path.home() / ".local/bin/grok", Path.home() / ".grok/bin/grok"]
    )
    client = RpcClient([executable, "agent", "stdio"])
    try:
        client.send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": 1,
                    "clientCapabilities": {},
                    "clientInfo": {"name": "nick_agents", "title": "My Agents", "version": "1.0.0"},
                },
            }
        )
        client.wait_for(1, 45)
        client.send({"jsonrpc": "2.0", "id": 2, "method": "_x.ai/billing", "params": {}})
        response = client.wait_for(2, 45)
    finally:
        client.close()

    result = response.get("result") or {}
    config = result.get("config") or {}
    period = config.get("currentPeriod") or {}
    period_type = str(period.get("type") or "")
    if "MONTH" in period_type:
        title = "Monthly"
    elif "DAY" in period_type:
        title = "Daily"
    else:
        title = "Weekly"
    percent = float(config.get("creditUsagePercent") or 0) / 100.0
    resets_at = str(period.get("end") or "")
    limits = []
    if resets_at:
        limits.append(
            {"label": title, "title": title, "percent": percent, "resetsAt": resets_at}
        )
    return {"limits": limits, "tierLabel": str(result.get("subscription_tier") or "")}


def muse_usage_limits(usage: dict[str, Any]) -> list[dict[str, Any]]:
    limits: list[dict[str, Any]] = []
    window = usage.get("window") or {}
    if window:
        duration = int(window.get("windowDurationMins") or 300)
        if duration == 300:
            label = "Session (5-hour)"
        elif duration % 60 == 0:
            label = f"Session ({duration // 60}-hour)"
        else:
            label = f"Session ({duration} min)"
        limits.append(
            {
                "label": label,
                "title": "Session",
                "percent": float(window.get("usedPercent") or 0) / 100.0,
                "resetsAt": iso_from_ms(int(window.get("resetsAtMs") or 0)),
            }
        )
    weekly = usage.get("weekly") or {}
    if weekly:
        limits.append(
            {
                "label": "Weekly",
                "title": "Weekly",
                "percent": float(weekly.get("usedPercent") or 0) / 100.0,
                "resetsAt": iso_from_ms(int(weekly.get("resetsAtMs") or 0)),
            }
        )
    return limits


def probe_muse() -> dict[str, Any]:
    executable = find_executable("muse", [Path.home() / ".local/bin/muse"])
    client = RpcClient([executable, "serve"])
    try:
        client.send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "clientInfo": {"name": "nick_agents", "title": "My Agents", "version": "1.0.0"}
                },
            }
        )
        client.wait_for(1, 60)
        client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        client.send(
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "session/start",
                "params": {"commandId": uuid7()},
            }
        )
        started = client.wait_for(2, 90)
        session = (started.get("result") or {}).get("session") or {}
        session_id = session.get("sessionId") or session.get("id")
        if not session_id:
            raise RuntimeError("muse session/start returned no session id")

        client.send({"jsonrpc": "2.0", "id": 3, "method": "usage/read", "params": {}})
        read = client.wait_for(3, 45)
        usage = (read.get("result") or {}).get("usage")

        if not usage:
            client.send(
                {
                    "jsonrpc": "2.0",
                    "id": 4,
                    "method": "turn/start",
                    "params": {
                        "commandId": uuid7(),
                        "sessionId": session_id,
                        "input": [{"type": "text", "text": "Reply with exactly: ok"}],
                        "reasoningEffort": "none",
                    },
                }
            )
            client.wait_for(4, 180)
            deadline = time.time() + 120
            while time.time() < deadline and not usage:
                for note in client.notifications:
                    if note.get("method") == "usage/changed":
                        usage = note.get("params")
                if usage:
                    break
                try:
                    line = client.messages.get(timeout=min(5, max(0.1, deadline - time.time())))
                    message = json.loads(line)
                    if message.get("method") == "usage/changed":
                        usage = message.get("params")
                    elif message.get("method"):
                        client.notifications.append(message)
                except queue.Empty:
                    pass
            if not usage:
                client.send({"jsonrpc": "2.0", "id": 5, "method": "usage/read", "params": {}})
                read = client.wait_for(5, 45)
                usage = (read.get("result") or {}).get("usage")
        if not usage:
            raise RuntimeError("muse did not report subscription usage")
    finally:
        client.close()
    return {"limits": muse_usage_limits(usage), "tierLabel": ""}


def cache_path(agent_id: str) -> Path:
    base = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return base / "nick.agents" / f"{agent_id}-limits.json"


def load_cache(agent_id: str) -> dict[str, Any] | None:
    try:
        return json.loads(cache_path(agent_id).read_text())
    except Exception:
        return None


def save_cache(agent_id: str, payload: dict[str, Any]) -> None:
    path = cache_path(agent_id)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(payload))
        tmp.replace(path)
    except OSError:
        pass


def collect_limits(agent_id: str, force: bool) -> tuple[list[dict[str, Any]], str, str, bool]:
    cfg = AGENTS[agent_id]
    cached = load_cache(agent_id)
    now = time.time()
    if cached and not force and now - float(cached.get("fetchedAt") or 0) < cfg["cache_seconds"]:
        return cached.get("limits") or [], str(cached.get("tierLabel") or ""), "", False
    try:
        fresh = probe_grok() if agent_id == "grok" else probe_muse()
        payload = {"fetchedAt": now, **fresh}
        save_cache(agent_id, payload)
        return fresh.get("limits") or [], str(fresh.get("tierLabel") or ""), "", False
    except Exception:
        if cached:
            return cached.get("limits") or [], str(cached.get("tierLabel") or ""), "", True
        return [], "", "Limits unavailable", True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("agent", choices=sorted(AGENTS))
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limits-only", action="store_true")
    args = parser.parse_args()

    cfg = AGENTS[args.agent]
    stats = collect_stats(hermes_db(), args.agent)
    limits, tier_label, status_text, retry = collect_limits(args.agent, args.force)
    record = {
        "schemaVersion": 1,
        "id": args.agent,
        "name": cfg["name"],
        "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "ready": stats["totalPrompts"] > 0 or bool(limits),
        "hasLocalStats": True,
        "tierLabel": tier_label,
        "usageStatusText": status_text,
        "authHelpText": cfg["auth_help"] if status_text else "",
        "limits": limits,
    }
    if retry:
        record["retryAdvised"] = True
    record.update(stats)
    print(json.dumps(record, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
