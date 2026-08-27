#!/usr/bin/env python3
"""
help-center monitor — local desktop alerts for the dedicated Slack alert channel.

Polls the dedicated Slack alert channel (C0BJLB6NYQ7) with a bot token
and fires a native macOS notification whenever a NEW top-level message (= new
Pylon ticket thread) appears. No server, no dependencies — Python 3 stdlib only.

Run it in a terminal and leave it running:

    python3 help_center_monitor.py

Stop with Ctrl-C.

Token lookup order:
  1. SLACK_BOT_TOKEN environment variable
  2. macOS Keychain item:  security find-generic-password -s help-center-monitor -w
See README.md for setup.
"""

import argparse
import json
import os
import random
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# The only production source for audible alerts.
DEFAULT_CHANNEL = "C0BJLB6NYQ7"
WORKSPACE_URL = "https://upwindsecurity.slack.com"
API_BASE = os.environ.get("SLACK_API_BASE", "https://slack.com/api")
STATE_FILE = Path(os.environ.get("HCM_STATE_FILE", str(Path.home() / ".help-center-monitor-state.json")))
KEYCHAIN_SERVICE = "help-center-monitor"

# Non-Marketplace Slack apps get ~1 request/min on conversations.history.
# The script honors 429 Retry-After automatically, so a too-low interval
# degrades gracefully, but keep >= 60 (raise it if several people run this
# with the same token at the same time).
DEFAULT_INTERVAL = 60

# History messages that are not new tickets.
IGNORED_SUBTYPES = {
    "channel_join", "channel_leave", "channel_topic", "channel_purpose",
    "channel_name", "channel_archive", "channel_unarchive",
    "bot_add", "bot_remove", "reminder_add", "tombstone",
    "message_changed", "message_deleted", "thread_broadcast",
    "huddle_thread", "channel_canvas_updated", "sh_room_created",
}


def log(msg: str) -> None:
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)


# ---------------------------------------------------------------- token

def get_token() -> str:
    token = os.environ.get("SLACK_BOT_TOKEN", "").strip()
    if token:
        return token
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    sys.exit(
        "No Slack token found.\n"
        "Either:  export SLACK_BOT_TOKEN=xoxb-...\n"
        "Or store it once in the macOS Keychain (recommended, see README):\n"
        f'  read -s TOKEN && security add-generic-password -s {KEYCHAIN_SERVICE} '
        '-a "$USER" -w "$TOKEN" -U && unset TOKEN'
    )


# ---------------------------------------------------------------- slack api

def api_call(method: str, token: str, **params) -> dict:
    """POST a Slack Web API method. Returns the parsed JSON payload.
    Rate-limit (HTTP 429) is returned as {'ok': False, 'error': 'ratelimited',
    'retry_after': N} instead of raising."""
    url = f"{API_BASE}/{method}"
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(
        url, data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        if e.code == 429:
            try:
                retry_after = int(e.headers.get("Retry-After", "60"))
            except ValueError:
                retry_after = 60
            return {"ok": False, "error": "ratelimited", "retry_after": retry_after}
        raise


FATAL_ERRORS = {
    "invalid_auth": "The token is invalid. Check SLACK_BOT_TOKEN / the Keychain item.",
    "account_inactive": "The token belongs to a deactivated app/account.",
    "token_revoked": "The token was revoked. Get a fresh one from the app config.",
    "not_in_channel": "The bot is not a member of the channel. In Slack, open the "
                      "channel and run:  /invite @<bot name>   then restart.",
    "channel_not_found": "Channel ID is wrong, or the bot cannot see this channel.",
    "missing_scope": "The bot token lacks a history OAuth scope (channels:history for "
                     "public channels, groups:history for private). Add it in the Slack "
                     "app config (OAuth & Permissions) and reinstall the app.",
}


def auth_check(token: str) -> dict:
    """auth.test with retry on network blips / rate limits; exits only on
    genuinely fatal token problems."""
    delay = 5
    while True:
        try:
            ident = api_call("auth.test", token)
        except (urllib.error.URLError, OSError, ValueError) as e:
            log(f"WARN: cannot reach Slack ({e}); retrying in {delay}s.")
            time.sleep(delay)
            delay = min(delay * 2, 60)
            continue
        if ident.get("ok"):
            return ident
        err = ident.get("error", "unknown")
        if err == "ratelimited":
            wait = min(ident.get("retry_after", 30), 120)
            log(f"auth.test rate-limited; waiting {wait}s.")
            time.sleep(wait)
            continue
        sys.exit(f"auth.test failed with '{err}': "
                 f"{FATAL_ERRORS.get(err, 'check the token and try again.')}")


# ---------------------------------------------------------------- message parsing

_SHORTCODE = re.compile(r":[a-z0-9_+\-']+:")          # :rotating_light:
_LINK = re.compile(r"<([^>|]+)\|([^>]+)>")            # <url|label> -> label
_BARE_LINK = re.compile(r"<(https?://[^>]+)>")        # <url> -> url
_MENTION = re.compile(r"<[@#!][^>]+>")                # <@U123>, <#C1|x>, <!here>
_ISSUE = re.compile(r"Issue #(\d+)", re.IGNORECASE)
_PLACEHOLDER = "no preview available"


def slack_to_plain(text) -> str:
    """Turn Slack mrkdwn into a readable one-line string for a notification."""
    if not isinstance(text, str):
        return ""
    text = _LINK.sub(r"\2", text)        # keep the human label of a link
    text = _BARE_LINK.sub(r"\1", text)
    text = _MENTION.sub("", text)
    text = _SHORTCODE.sub("", text)       # drop :emoji: codes
    text = text.replace("*", "").replace("`", "").replace("_", " ")
    return " ".join(text.split())         # collapse whitespace/newlines


def _collect_text(node, out: list) -> None:
    """Recursively harvest human-readable text out of Slack blocks."""
    if isinstance(node, dict):
        t = node.get("text")
        if isinstance(t, str) and t.strip():
            out.append(t.strip())
        for key, value in node.items():
            if key != "text":
                _collect_text(value, out)
    elif isinstance(node, list):
        for item in node:
            _collect_text(item, out)


def message_text(msg: dict) -> str:
    # The top-level `text` field is the fullest, cleanest summary for the Pylon
    # first-touch feed; fall back to attachments/blocks for other channels
    # (e.g. raw #help-center, where `text` is empty).
    t = slack_to_plain(msg.get("text"))
    if t:
        return t
    for att in msg.get("attachments") or []:
        for key in ("title", "text", "fallback"):
            val = att.get(key)
            if isinstance(val, str) and val.strip() and _PLACEHOLDER not in val.lower():
                return slack_to_plain(val)
    if msg.get("blocks"):
        raw = []
        _collect_text(msg["blocks"], raw)
        cleaned = slack_to_plain(" ".join(raw))
        if cleaned:
            return cleaned
    return "(no text)"


def message_sender(msg: dict) -> str:
    # Pylon posts tickets as bot messages whose `username` is the customer name.
    return (
        msg.get("username")
        or (msg.get("bot_profile") or {}).get("name")
        or msg.get("user")
        or "unknown"
    )


def issue_number(msg: dict):
    m = _ISSUE.search(msg.get("text") or "")
    return m.group(1) if m else None


def _harvest_urls(node, urls: list) -> None:
    if isinstance(node, dict):
        u = node.get("url")
        if isinstance(u, str) and u.startswith("http"):
            urls.append(u)
        for key, value in node.items():
            if key == "text" and isinstance(value, str):
                urls += [m.group(1) for m in _LINK.finditer(value)]
                urls += [m.group(1) for m in _BARE_LINK.finditer(value)]
            else:
                _harvest_urls(value, urls)
    elif isinstance(node, list):
        for item in node:
            _harvest_urls(item, urls)


def best_link(msg: dict, channel: str) -> str:
    """The most useful link to click. For the Pylon feed that's the "View in
    Slack" deep link to the customer's actual message; then the Pylon issue;
    else a permalink to the monitored message itself."""
    urls = []
    _harvest_urls(msg.get("attachments") or [], urls)
    _harvest_urls(msg.get("blocks") or [], urls)
    for u in urls:
        if "slack.com/archives" in u:
            return u
    for u in urls:
        if "usepylon.com" in u or "pylon" in u.lower():
            return u
    return permalink(channel, msg["ts"])


def permalink(channel: str, ts: str) -> str:
    return f"{WORKSPACE_URL}/archives/{channel}/p{ts.replace('.', '')}"


# ---------------------------------------------------------------- alerting

OSA_NOTIFY = (
    "on run argv\n"
    "  display notification (item 1 of argv) with title (item 2 of argv) "
    "sound name (item 3 of argv)\n"
    "end run"
)
# `with timeout` keeps the unattended dialog from dying with AppleEvent error
# -1712 after ~2 min; `giving up after` auto-dismisses it after 4h so
# unacknowledged dialogs don't pile up forever.
OSA_DIALOG = (
    "on run argv\n"
    "  with timeout of 86400 seconds\n"
    "    tell application \"System Events\"\n"
    "      activate\n"
    "      display dialog (item 1 of argv) with title (item 2 of argv) "
    "buttons {\"OK\"} default button \"OK\" with icon caution "
    "giving up after 14400\n"
    "    end tell\n"
    "  end timeout\n"
    "end run"
)

_dialog_procs = []  # Popen handles of modal dialogs, reaped on later alerts


def alert(title: str, body: str, opts) -> None:
    """Fire the local alert. Never raises — an alerting hiccup must not kill the loop."""
    for proc in _dialog_procs[:]:          # reap finished dialog processes
        if proc.poll() is not None:
            _dialog_procs.remove(proc)
    try:
        # "--" stops osascript from parsing a body that starts with "-" as options.
        r = subprocess.run(
            ["osascript", "-e", OSA_NOTIFY, "--", body[:250], title, opts.sound],
            capture_output=True, text=True, timeout=15,
        )
        if r.returncode != 0:
            log(f"WARN: notification failed (rc={r.returncode}): {r.stderr.strip()}")
    except (OSError, subprocess.TimeoutExpired) as e:
        log(f"WARN: notification failed: {e}")
    if opts.speak:
        try:
            subprocess.run(["say", "New help center ticket"], capture_output=True,
                           timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            pass
    if opts.dialog:
        try:
            # Popen: the modal dialog must not block the polling loop.
            _dialog_procs.append(subprocess.Popen(
                ["osascript", "-e", OSA_DIALOG, "--",
                 f"{title}\n\n{body[:500]}", "Help Center"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            ))
        except OSError as e:
            log(f"WARN: dialog failed: {e}")


# ---------------------------------------------------------------- state

def load_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    try:
        tmp = STATE_FILE.with_suffix(".tmp")
        with open(tmp, "w") as f:
            json.dump(state, f)
        tmp.replace(STATE_FILE)
    except OSError as e:
        log(f"WARN: could not persist state ({e}); duplicate alerts possible after restart.")


# ---------------------------------------------------------------- core loop

# Hard safety valve against a broken/stuck pagination cursor. 500 pages x 15
# messages is far more channel traffic than #help-center sees in months; the
# 429 handler paces the loop at ~1 page/min, so a big backlog just takes a
# few minutes to drain rather than being dropped.
MAX_PAGES = 500


def fetch_new_messages(token: str, channel: str, oldest: str):
    """Fetch everything strictly newer than `oldest`.

    Returns (ticket_msgs, floor_ts):
      ticket_msgs — top-level ticket-shaped messages, oldest first;
      floor_ts    — highest raw ts seen (advance the dedup floor to it), or
                    None if the fetch didn't complete (nothing may be skipped).
    On ANY transient error returns ([], None) so the whole window is re-fetched
    cleanly next cycle — never a partial, unfiltered result.
    """
    messages, cursor, pages = [], None, 0
    while True:
        params = {"channel": channel, "oldest": oldest, "limit": 15}
        if cursor:
            params["cursor"] = cursor
        try:
            resp = api_call("conversations.history", token, **params)
        except (urllib.error.URLError, OSError, ValueError) as e:
            log(f"WARN: network error talking to Slack ({e}); will retry next cycle.")
            return [], None
        if not resp.get("ok"):
            err = resp.get("error", "unknown")
            if err == "ratelimited":
                wait = min(resp.get("retry_after", 60), 300)
                log(f"Rate-limited by Slack; waiting {wait}s "
                    f"(tip: raise --interval if several people run this token).")
                time.sleep(wait)
                continue
            if err in FATAL_ERRORS:
                sys.exit(f"Slack API error '{err}': {FATAL_ERRORS[err]}")
            log(f"WARN: Slack API error '{err}'; will retry next cycle.")
            return [], None
        messages.extend(resp.get("messages") or [])
        next_cursor = (resp.get("response_metadata") or {}).get("next_cursor")
        pages += 1
        if not (resp.get("has_more") and next_cursor):
            break
        if next_cursor == cursor or pages >= MAX_PAGES:
            log(f"WARN: pagination did not converge after {pages} pages; "
                f"will retry next cycle.")
            return [], None
        cursor = next_cursor

    ticket_msgs = []
    floor = None
    for msg in messages:
        ts = msg.get("ts")
        if not ts:
            continue
        if floor is None or float(ts) > float(floor):
            floor = ts
        if msg.get("subtype") in IGNORED_SUBTYPES or msg.get("hidden"):
            continue
        if msg.get("thread_ts") and msg["thread_ts"] != ts:
            continue  # a reply, not a new thread
        ticket_msgs.append(msg)
    ticket_msgs.sort(key=lambda m: float(m["ts"]))
    return ticket_msgs, floor


def run(opts) -> None:
    token = get_token()

    ident = auth_check(token)
    log(f"Authenticated as '{ident.get('user', '?')}' in workspace "
        f"'{ident.get('team', '?')}'.")

    state = load_state()
    chan_state = state.get(opts.channel) or {}
    last_ts = chan_state.get("last_ts")
    if last_ts:
        log(f"Resuming from last seen message ts={last_ts}.")
    else:
        last_ts = f"{time.time():.6f}"
        state[opts.channel] = {"last_ts": last_ts}
        save_state(state)
        log("First run: alerting only on messages from now on.")

    log(f"Monitoring channel {opts.channel} every {opts.interval}s. Ctrl-C to stop.")
    while True:
        try:
            new_msgs, floor_ts = fetch_new_messages(token, opts.channel, last_ts)
            for msg in new_msgs:
                sender = message_sender(msg)
                text = message_text(msg)
                link = best_link(msg, opts.channel)
                issue = issue_number(msg)
                title = f"Needs first touch — {sender}"
                if issue:
                    title += f" (#{issue})"
                log(f"NEW TICKET from {sender}"
                    f"{f' (#{issue})' if issue else ''}: {text[:160]}")
                log(f"  -> {link}")
                alert(title, text, opts)
                last_ts = msg["ts"]
                state[opts.channel] = {"last_ts": last_ts}
                save_state(state)
            # Advance the floor past non-ticket messages (joins, topic changes,
            # ...) too, so they aren't re-fetched every cycle forever.
            if floor_ts and float(floor_ts) > float(last_ts):
                last_ts = floor_ts
                state[opts.channel] = {"last_ts": last_ts}
                save_state(state)
        except KeyboardInterrupt:
            raise
        except SystemExit:
            raise
        except Exception as e:  # never let one bad cycle kill the monitor
            log(f"WARN: unexpected error in poll cycle ({type(e).__name__}: {e}); "
                f"will retry next cycle.")
        time.sleep(opts.interval + random.uniform(0, 3))


def main() -> None:
    p = argparse.ArgumentParser(description="Local desktop alerts for the dedicated Slack alert channel.")
    p.add_argument("--channel", default=DEFAULT_CHANNEL,
                   help=f"Slack channel ID to watch (default {DEFAULT_CHANNEL})")
    p.add_argument("--interval", type=int, default=DEFAULT_INTERVAL,
                   help=f"poll interval seconds (default {DEFAULT_INTERVAL}; keep >= 60)")
    p.add_argument("--sound", default="Glass",
                   help="notification sound name (default Glass; see /System/Library/Sounds)")
    p.add_argument("--speak", action="store_true",
                   help="also announce out loud via the 'say' command")
    p.add_argument("--dialog", action="store_true",
                   help="also pop a modal dialog window (impossible to miss)")
    p.add_argument("--test", action="store_true",
                   help="fire one test notification and exit (no Slack access)")
    p.add_argument("--reset", action="store_true",
                   help="forget the last-seen position before starting")
    opts = p.parse_args()

    if opts.interval < 15:
        p.error("--interval must be >= 15 seconds")

    if opts.test:
        alert("Help-center monitor", "Test notification — if you can see (and hear) "
              "this, alerts will work.", opts)
        print("Test alert sent. If no banner appeared, allow notifications for "
              "'Script Editor'/'osascript' in System Settings > Notifications.")
        return

    if opts.reset:
        state = load_state()
        state.pop(opts.channel, None)
        save_state(state)
        log("State reset.")

    try:
        run(opts)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
