# Help Center Monitor

A native macOS menu-bar application that alerts support teammates when a new
top-level message appears in either `#help-center` (`C07ES26GU2D`) or
`#dispatcher` (`C0BJLB6NYQ7`).

After the one-time installation, the user does not run Python or Terminal
commands. A macOS login item starts the app automatically whenever the user logs
in. The menu-bar bell is the control surface: click **Monitoring Enabled** to
turn Slack polling on or off.

## Employee experience

Employees must not clone this repository or run any script. They receive one
`Help Center Monitor.dmg` file:

1. Open the DMG.
2. Drag the app to Applications and attempt to open it once.
3. For the current unsigned internal build, click **Done** in Gatekeeper, use
   the DMG's **2 - After Warning - Open Privacy & Security** shortcut, then
   choose **Open Anyway → Open**.
4. Allow macOS notifications.

That is the intended production experience. The app first loads the Slack bot
token automatically from AWS Secrets Manager using the standard
`prod-read-only` SSO profile, then caches it in Keychain. It shows the secure
paste field only when AWS retrieval fails and no previously cached token is
available, so Terminal commands are never needed during normal setup.
For an employee-wide release, use the event-service architecture described
below so no Slack token is distributed to employee Macs at all. From then on,
macOS launches the app automatically; the employee only uses the visible
control window or the menu-bar enable/disable item. Give employees
[EMPLOYEE_INSTALL.md](EMPLOYEE_INSTALL.md), not the developer instructions below.

## What the application does

- Uses one **Monitoring** switch for two fixed Slack sources:
  `#help-center` (`C07ES26GU2D`) and `#dispatcher` (`C0BJLB6NYQ7`).
- Makes no monitoring requests to any other Slack channel.
- Alerts only on new top-level messages, not thread replies or channel events.
- Shows the source channel, customer, and issue number in a native macOS
  notification. A new message in each channel produces a separate alert.
- Plays the original, distinctive macOS **Glass** sound at full volume and
  announces **“New message in the alert channel.”** An optional **Team
  voice-overs** switch replaces that system announcement with a randomly chosen,
  volume-matched teammate recording. Multiple alerts are queued so recordings do
  not interrupt each other, and an unavailable clip falls back to the system voice.
- Shows a direct in-app fallback alert if macOS notification permission is
  blocked, so a detected ticket is never silently discarded.
- Opens the customer Slack or Microsoft Teams link when available, with Pylon
  and the feed message as fallbacks.
- Remembers the last-seen Slack timestamp across restarts and sleep/wake cycles.
- Rechecks immediately when the Mac wakes or the user session becomes active.
- Loads the Slack bot token from AWS Secrets Manager and caches it in macOS
  Keychain, never in the app bundle or preferences.
- Honors Slack `Retry-After` rate limits and retries network failures forever.
- Stays installed and running when monitoring is disabled, but makes no Slack
  requests until the user enables it again. Messages received while disabled
  are intentionally skipped instead of producing an alert flood later.

On each app launch with monitoring enabled, credential resolution follows this
order:

1. Read `/production/monitoring/help-center-monitor` from AWS Secrets Manager in
   `us-east-1` with the `prod-read-only` profile.
2. If AWS retrieval fails, reuse a token stored under the existing Keychain
   service name `help-center-monitor`.
3. Only if both are unavailable, show the secure manual-paste fallback.

The AWS secret may be the plain `xoxb-…` value or JSON containing that value.
The app also imports the last-seen timestamp from
`~/.help-center-monitor-state.json` the first time it starts.

## Monitored Slack channels

The production sources are fixed to `#help-center` (`C07ES26GU2D`) and
`#dispatcher` (`C0BJLB6NYQ7`). Every new top-level message in either channel
produces an alert. Thread replies, edits, joins, topic changes, and other Slack
channel events do not. Each channel has its own persisted last-seen timestamp,
so activity in one channel never consumes or suppresses alerts from the other.

The first time the app sees either source, it starts that channel from the
current time so existing messages do not produce a backlog of alerts. Disabling
Monitoring also skips messages received while disabled.

## Latency, credentials, and permissions

The local preview polls immediately at startup, then waits 30 seconds between
successful checks. An event in either monitored channel therefore takes 0–30
seconds to be noticed under normal conditions—about 15 seconds on average—plus
Slack/network response time. A Slack rate limit, sleep, or network outage can
make this longer. The panel states the normal interval instead of implying that
the connection is real-time.

The token is never hard-coded, printed to logs, or written to preferences. The
app invokes the locally installed AWS CLI so it can reuse the managed Mac's
existing AWS SSO session without embedding long-lived AWS credentials. The
`prod-read-only` role must allow `secretsmanager:GetSecretValue` for only
`/production/monitoring/help-center-monitor`. A successful result is stored as a
generic password in macOS Keychain with
`AfterFirstUnlockThisDeviceOnly`, meaning it stays on that Mac and is available
only after the user has unlocked it. A pre-existing legacy Keychain item keeps
its original access policy when updated. If the AWS CLI is unavailable, the SSO
session has expired, access is denied, the request times out, or the secret is
malformed, the app falls back to Keychain and then to the secure paste field.
Keychain storage is appropriate for a pilot, but a shared bot token present on
every employee Mac increases the number of places where that secret can be
accessed. It is not the recommended broad-deployment architecture.

For production, Slack should send `message.channels` Events API callbacks to a
small company-managed service. That service stores Slack secrets in the cloud
secret manager and streams only sanitized alert events to authenticated desktop
clients. This removes the Slack token from employee Macs and changes detection
from once-per-minute polling to event-driven delivery in seconds.

macOS does not allow an app to grant notification permission to itself. The app
requests it, shows a persistent red **System notifications — Needs attention**
row when blocked, opens the correct Settings pane, and reopens the panel on
launch until the problem is resolved. Managed company Macs can instead receive
notification and login-item configuration through MDM.

## Developer installation

Requirements: macOS 13 or newer and Apple Command Line Tools or Xcode.

```bash
./scripts/install_app.sh
```

This replaces the existing installation in `/Applications` or
`~/Applications`. A first developer installation is placed at:

```text
~/Applications/Help Center Monitor.app
```

On first launch of the local preview:

1. Allow notifications when macOS asks.
2. The app automatically loads Slack access through the `prod-read-only` AWS
   profile. If that fails and no token is cached, paste the fallback `xoxb-`
   token into the secure field. Do not use Terminal.
3. If the menu says **Allow Automatic Start…**, click it and enable
   Help Center Monitor in **System Settings → General → Login Items**.

After that, no command needs to be run again. The app starts automatically at
every login and internally retries Slack and network failures.

Teammates updating an older copy that was installed from this repository should
use the shorter [TEAM_UPDATE.txt](TEAM_UPDATE.txt) guide. The update replaces the
app at the same path and retains the existing Keychain token, notification
permission, and login-item path.

If the old Python monitor is still running in a terminal, stop it after the
native app reports **Status: Monitoring**. If the old optional LaunchAgent was
installed, remove or unload `~/Library/LaunchAgents/io.upwind.help-center-monitor.plist`
after confirming the new app works; otherwise both monitors will poll Slack.

## Menu-bar controls

- **Monitoring Enabled / Disabled** — the main on/off toggle.
- **Team Voice Alerts Enabled / Disabled** — randomly uses a bundled teammate
  recording instead of the system-spoken announcement. This is off by default.
- **Sources: #help-center and #dispatcher** — shows both fixed production
  sources.
- **Status** — authentication, connectivity, rate-limit, or configuration state.
- **Last checked** — time of the most recent successful Slack check.
- **Notifications Enabled / Fix Notifications…** — reports macOS permission
  separately from Slack connectivity and opens the correct System Settings pane.
- **Send Test Alert** — either sends a banner or immediately explains
  why macOS blocked it.
- **Replace Slack Token…** — manually overrides the Keychain token when
  troubleshooting the automatic AWS flow.
- **Allow Automatic Start…** — appears only if macOS approval is still needed.

Opening Help Center Monitor from Spotlight always opens the same controls in a
visible window. Closing the window does not stop the background monitor. The
window reads the real macOS login-item status and warns instead of claiming
automatic start is enabled when approval or registration is missing.

The app intentionally has no normal Quit command. Disable monitoring from its
menu when alerts are not wanted. macOS still allows administrators to stop or
disable the background item in System Settings.

## Build and verify

Prepare one recording or a whole directory before building:

```bash
swift scripts/process_team_voices.swift \
  --output Resources/TeamVoices \
  /path/to/recordings
```

The processor accepts common phone and desktop audio formats, converts them to
mono, trims leading and trailing silence, applies light speech compression,
normalizes active speech to −19 dBFS, caps peaks, and adds short fades at the cut
points. It uses `ffmpeg` when available for phone-exported AAC files; set
`HCM_FFMPEG_PATH` when it is installed in a nonstandard location. Processed
files in `Resources/TeamVoices` are copied into the app bundle automatically.

Build an ad-hoc signed development app:

```bash
./scripts/build_app.sh
```

The result is a universal Apple Silicon + Intel app at
`dist/Help Center Monitor.app`.

Run the offline core checks:

```bash
./scripts/self_test.sh
```

The checks cover AWS plain-text/JSON secret parsing, Slack markdown cleanup,
attachment fallback text, issue and
sender extraction, reply/event filtering, Pylon metadata recognition,
Slack/Teams/Pylon deep-link selection, retired mode-state cleanup,
per-channel last-seen persistence, bounded history reads, and recovery of
multi-page Slack history after a mocked HTTP 429. They also verify the
Command+V Paste menu contract and the notification-versus-ordinary-reopen state
machine. They never read the real Keychain token or call Slack.

If a local Command Line Tools installation contains mismatched Swift and SDK
versions, select a compatible installed SDK explicitly:

```bash
HCM_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  ./scripts/build_app.sh
```

## Distribution

Create the employee-facing drag-and-drop DMG:

```bash
./scripts/package_dmg.sh
```

Without an Apple Developer ID, the default DMG is ad-hoc signed. Distribute it
only through a trusted internal channel. Each teammate must approve it once in
**System Settings → Privacy & Security**; the DMG includes a shortcut that opens
that pane directly after the required first launch attempt. See
[EMPLOYEE_INSTALL.md](EMPLOYEE_INSTALL.md) for the exact flow. A newly rebuilt
unsigned version may require approval again.

If Developer ID access becomes available later, sign the app and notarize the
DMG to remove the Gatekeeper approval steps:

```bash
HCM_SIGN_IDENTITY="Developer ID Application: Your Company (TEAMID)" \
HCM_NOTARY_PROFILE="help-center-monitor-notary" \
  ./scripts/package_dmg.sh
```

The notary profile is created once by the release owner with Apple's
`notarytool store-credentials`. These credentials stay in that person's
Keychain and never enter the application.

For truly zero-touch installation and upgrades, publish the signed app or a
signed installer through the company's device-management system. The MDM can
place it in Applications for every employee; no employee needs the repository
or a Terminal command.

## Architecture

```text
Help Center Monitor.app
├── visible control window and menu-bar UI
├── native notifications
├── normalized teammate voice-over library with random playback
├── AWS Secrets Manager-backed Slack credential with Keychain/manual fallback
├── persistent enablement and last-seen state
└── macOS main-app login item
    ├── starts automatically at login
    └── polls Slack only while monitoring is enabled
```

The installed app registers itself with Apple's `SMAppService.mainApp`. It is a
single process: Spotlight reopening, the control window, menu-bar item,
notifications, and monitoring loop all belong to the same application. Version
0.8.3 expands the bundled, normalized teammate voice-over library to ten
recordings. Version 0.8.0
added the persisted, opt-in teammate voice-over library, random nonrepeating
selection, safe system-voice fallback, and the batch audio preparation pipeline.
Version 0.7.1 replaced the earlier source modes with `C0BJLB6NYQ7` as the only
production Slack source and removed retired alert-mode state during migration.
The current source list adds `#help-center` (`C07ES26GU2D`) alongside that
dispatcher channel, with independent last-seen state and alerts for both.
Version 0.6.3 added a native
Internet Location for the one-click Privacy & Security shortcut in unsigned
internal DMGs. The app also includes the recognizable support-alert icon, compact status-card UI,
correctly sized toggle, 30-second polling, visible credential and real login-item
readiness, in-app Keychain setup, persistent notification-permission guidance,
queued Glass/speech alerts, rate-aware pagination, and the spoken alert-channel
announcement. It also restores standard Command+V paste in the secure token
field and prevents notification clicks from reopening the control panel before
Slack. The app unregisters the earlier experimental helper-agent architecture
during migration.

## Operational limits

- A local app cannot alert while the Mac is powered off or fully asleep. Messages
  that arrive during sleep are found after wake.
- Slack can limit `conversations.history` for some app installations to roughly
  one request per minute. The app attempts the requested 30-second
  interval, honors HTTP 429 `Retry-After`, and preserves pagination progress;
  the effective interval can therefore be 60 seconds or longer on that tier.
- Several users running separate local copies with the same Slack app can share
  that app/workspace rate limit. A hosted Slack Events service is the appropriate
  next step if this is deployed to a larger team.

## Legacy Python script

`help_center_monitor.py` remains in the repository as the original command-line
implementation and as a behavioral reference. New users should install the
native app instead.
