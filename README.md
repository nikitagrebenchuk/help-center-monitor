# Help Center Monitor

A native macOS menu-bar application that alerts support teammates either when a
new customer-message event appears or when Pylon reports that a two-minute first
or next response SLA was breached.

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

That is the intended production experience. The current local preview still
needs a one-time Slack credential; it now collects that credential inside the
app and stores it directly in Keychain, so Terminal commands are never needed.
For an employee-wide release, use the event-service architecture described
below so no Slack token is distributed to employee Macs at all. From then on,
macOS launches the app automatically; the employee only uses the visible
control window or the menu-bar enable/disable item. Give employees
[EMPLOYEE_INSTALL.md](EMPLOYEE_INSTALL.md), not the developer instructions below.

## What the application does

- Uses one **Monitoring** switch and a two-choice **Alert mode** control.
- **Immediate** watches `#monitor-first-touch-missing` (`C0BHCB96XM5`) and
  alerts on every new customer-message event.
- **Pylon 2 min** watches `#wg-first-touch-monitor` (`C0BD2LDGYSZ`) and alerts
  only on Pylon's verified two-minute SLA-breach events. Pylon determines both
  first-response and next-response breaches.
- Alerts only on new top-level messages, not thread replies or channel events.
- Shows the customer and issue number in a native macOS notification.
- Plays the original, distinctive macOS **Glass** sound at full volume.
  Immediate mode announces **“New ticket in help-center”**; Pylon mode announces
  **“Help Center message unanswered for 2 minutes.”** Multiple alerts are queued
  so speech does not interrupt itself.
- Shows a direct in-app fallback alert if macOS notification permission is
  blocked, so a detected ticket is never silently discarded.
- Opens the customer Slack or Microsoft Teams link when available, with Pylon
  and the feed message as fallbacks.
- Remembers the last-seen Slack timestamp across restarts and sleep/wake cycles.
- Rechecks immediately when the Mac wakes or the user session becomes active.
- Stores the Slack bot token in macOS Keychain, never in the app bundle.
- Honors Slack `Retry-After` rate limits and retries network failures forever.
- Stays installed and running when monitoring is disabled, but makes no Slack
  requests until the user enables it again. Messages received while disabled
  are intentionally skipped instead of producing an alert flood later.

The app reuses a token already stored under the existing Keychain service name
`help-center-monitor`, so users of the original Python script normally do not
need to enter the token again. It also imports the last-seen timestamp from
`~/.help-center-monitor-state.json` the first time it starts.

## Alert modes: Immediate or Pylon 2 min

Keep **Monitoring** enabled, then choose one mode:

- **Immediate:** reads only `#monitor-first-touch-missing` and alerts for every
  new top-level customer-message event.
- **Pylon 2 min:** reads only `#wg-first-touch-monitor` and alerts for every
  top-level Pylon event containing an issue number and **SLA breached**. The app
  does not independently decide whether a teammate replied.

The two-minute channel is the source of truth. In this mode the app never reads
`#help-center`, a customer Slack channel, a Microsoft Teams conversation, or a
Pylon Assignee field. This avoids treating customer follow-ups, customer
self-replies, or unrelated assignment changes as an Upwind response. It also
means the app handles first-response and next-response breaches identically and
can alert for Pylon-managed Teams tickets without reading Teams.

Switching modes starts the newly selected feed from the current time, preventing
historical backlog alerts. Disabling Monitoring also skips messages received
while disabled. Retired locally queued assignee-based checks are removed during
the one-time migration.

### Verify the Pylon feed

Select **Pylon 2 min**, then click **Verify Pylon 2-Minute Feed** in the control
window or menu-bar menu. The read-only check:

1. Reads a bounded recent sample from `#wg-first-touch-monitor` using the
   Monitoring Bot.
2. Confirms that a real Pylon issue/SLA-breach event is present.
3. Sends a labeled Pylon two-minute test notification with the production Glass
   sound and spoken announcement.

It does not post to Slack or inspect `#help-center`, Pylon assignees, customer
channels, or customer threads.

## Latency, credentials, and permissions

The local preview polls immediately at startup, then waits 30 seconds between
successful checks. An event in either source feed therefore takes 0–30 seconds
to be noticed under normal conditions—about 15 seconds on average—plus
Slack/network response time. For Pylon mode, this polling latency begins after
Pylon creates its two-minute breach event. A Slack rate limit, sleep, or network
outage can make this longer. The panel states the normal interval instead of
implying that the connection is real-time.

The token is never hard-coded or written to preferences. The in-app secure
field creates a generic password in macOS Keychain with
`AfterFirstUnlockThisDeviceOnly`, meaning it stays on that Mac and is available
only after the user has unlocked it. A pre-existing legacy Keychain item keeps
its original access policy when updated. Keychain storage is appropriate for a
pilot, but a shared bot token copied to every employee Mac increases the number
of places where that secret can be accessed. It is not the recommended
broad-deployment architecture.

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

This builds and installs the app at:

```text
~/Applications/Help Center Monitor.app
```

On first launch of the local preview:

1. Allow notifications when macOS asks.
2. If Slack access is not already configured, use **Set Up Slack Access** in the
   panel and paste the `xoxb-` token into the secure field. Do not use Terminal.
3. If the menu says **Allow Automatic Start…**, click it and enable
   Help Center Monitor in **System Settings → General → Login Items**.

After that, no command needs to be run again. The app starts automatically at
every login and internally retries Slack and network failures.

If the old Python monitor is still running in a terminal, stop it after the
native app reports **Status: Monitoring**. If the old optional LaunchAgent was
installed, remove or unload `~/Library/LaunchAgents/io.upwind.help-center-monitor.plist`
after confirming the new app works; otherwise both monitors will poll Slack.

## Menu-bar controls

- **Monitoring Enabled / Disabled** — the main on/off toggle.
- **Alert Mode: Immediate / Pylon-Verified 2 Minutes** — opens the control panel
  to switch the trusted source feed.
- **Verify Pylon 2-Minute Feed…** — available in Pylon mode and validates the
  real source feed before sending a labeled local test alert.
- **Status** — authentication, connectivity, rate-limit, or configuration state.
- **Last checked** — time of the most recent successful Slack check.
- **Notifications Enabled / Fix Notifications…** — reports macOS permission
  separately from Slack connectivity and opens the correct System Settings pane.
- **Send Test Alert** — either sends a banner or immediately explains
  why macOS blocked it.
- **Replace Slack Token…** — securely changes the Keychain token.
- **Allow Automatic Start…** — appears only if macOS approval is still needed.

Opening Help Center Monitor from Spotlight always opens the same controls in a
visible window. Closing the window does not stop the background monitor. The
window reads the real macOS login-item status and warns instead of claiming
automatic start is enabled when approval or registration is missing.

The app intentionally has no normal Quit command. Disable monitoring from its
menu when alerts are not wanted. macOS still allows administrators to stop or
disable the background item in System Settings.

## Build and verify

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

The checks cover Slack markdown cleanup, attachment fallback text, issue and
sender extraction, reply/event filtering, Pylon SLA-breach recognition,
Slack/Teams/Pylon deep-link selection, migration to the two supported modes,
per-channel last-seen persistence, bounded Pylon-feed verification, and recovery
of multi-page Slack history after a mocked HTTP 429. They also verify the
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
├── Keychain-backed Slack credential
├── persistent enablement and last-seen state
└── macOS main-app login item
    ├── starts automatically at login
    └── polls Slack only while monitoring is enabled
```

The installed app registers itself with Apple's `SMAppService.mainApp`. It is a
single process: Spotlight reopening, the control window, menu-bar item,
notifications, and monitoring loop all belong to the same application. Version
0.7.0 replaces the locally inferred 1–10 minute assignee check with two explicit
source feeds: immediate events and Pylon-verified two-minute first/next-response
SLA breaches. It removes old pending timers during migration and never reads
`#help-center` or customer threads in Pylon mode. Version 0.6.3 added a native
Internet Location for the one-click Privacy & Security shortcut in unsigned
internal DMGs. The app also includes the recognizable support-alert icon, compact status-card UI,
correctly sized toggle, 30-second polling, visible credential and real login-item
readiness, in-app Keychain setup, persistent notification-permission guidance,
queued Glass/speech alerts, rate-aware pagination, and the spoken “New ticket in
help-center” alert. It also restores standard Command+V paste in the secure token
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
