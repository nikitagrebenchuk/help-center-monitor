# Slack access for Claude Code (this repo)

This project ships a **project-scoped Slack MCP server** so that Claude Code,
when opened in this repo, can read the Upwind Security Slack workspace
(`upwindsecurity.slack.com`) — public channels, joined private channels, DMs,
and group DMs, with the same visibility Nikita has in the browser.

Use it to investigate `#help-center` / `#monitor-first-touch-missing`, look up
how Pylon posts are shaped, check feature discussions, or pull real message
examples while working on the app.

## What provides it

The `slack` entry in [`.mcp.json`](../.mcp.json) at the repo root. It runs
[korotovsky/slack-mcp-server](https://github.com/korotovsky/slack-mcp-server)
via `npx -y slack-mcp-server@latest` (stdio transport, no global install).
Once approved, Claude Code exposes tools named `mcp__slack__*`
(`conversations_history`, `conversations_replies`,
`conversations_search_messages`, `channels_list`, …).

## First-time approval

`.mcp.json` is a **project-scoped** MCP config. The first time you open this
repo, Claude Code asks you to approve the `slack` server before its tools load.
Approve it once (or run `claude mcp` / `/mcp` in an interactive session).

## Credentials (why `.mcp.json` is gitignored)

Auth is **stealth mode** — two Slack session credentials, stored as *literal*
values under `mcpServers.slack.env` in `.mcp.json`:

- `SLACK_MCP_XOXC_TOKEN` — workspace token (`xoxc-…`).
- `SLACK_MCP_XOXD_TOKEN` — the `d` session cookie (`xoxd-…`).

They must be literal (not `${VAR}` placeholders): Claude Code launched from the
Dock is started by `launchd`, which does **not** source `~/.zshrc`, so a
placeholder would resolve to empty and the server would silently fail to
register. Because the file holds live secrets it is **`0600` and gitignored** —
never commit it.

## Refreshing tokens (when Slack calls start failing)

Session credentials invalidate on Slack logout, SSO expiry, or Slack rotating
the cookie. To refresh, re-sign into the Slack **desktop app**, then from the
repo root:

```sh
./bin/slack-refresh-tokens     # pulls xoxc + xoxd from the Slack desktop app,
                               # verifies them, rewrites ~/.zshrc AND this
                               # repo's .mcp.json (chmod 0600)
```

Then restart Claude Code so the MCP server inherits the new values.
`slack-refresh-tokens` is pure Python stdlib + macOS `security`/`openssl`; no
pip deps. First run pops a Keychain prompt — click **Always Allow**.

Quick check without restarting Claude Code:

```sh
curl -s -X POST 'https://slack.com/api/auth.test' \
  -H "Cookie: d=$SLACK_MCP_XOXD_TOKEN" \
  -d "token=$SLACK_MCP_XOXC_TOKEN"
# expect {"ok":true, ...}
```

## Caveats

- **Stealth-mode tokens are technically against Slack ToS.** Low practical risk
  for personal/dev use; flag if scope changes.
- **No bot identity** — anything posted via the API appears as Nikita
  personally. This repo's use is read-only investigation; don't auto-post.
- **DMs/group DMs are in scope.** Don't surface them in shared output unless
  asked.
- `conversations_search_messages` is rate-limited (~20/min); avoid long
  cross-channel keyword sweeps.
