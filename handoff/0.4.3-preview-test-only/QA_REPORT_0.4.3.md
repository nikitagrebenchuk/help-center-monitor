# Help Center Monitor 0.4.3 QA report

Date: 2026-07-17  
Build: 12

## Reported regressions fixed

- The app now installs a standard macOS Edit menu whose **Paste** item sends
  `paste:` to the active responder with the Command+V shortcut. The secure token
  field is explicitly made first responder before its modal alert begins.
- Notification selection is now routed through the app delegate. Ordinary
  Spotlight/Finder reopen is delayed briefly; a notification response cancels
  or suppresses that reopen and opens Slack. If the race already surfaced a
  panel, only that race-created panel is ordered out. A panel that was already
  open is preserved behind Slack.
- Notification responses with no valid link, including the test notification,
  still suppress the accidental monitor-panel reopen and always complete their
  system callback.

## Automated checks passed

- The generated application menu contains exactly the expected responder-chain
  Paste action with key `v`, Command modifier, and nil target.
- Ordinary reopen still shows the controls after the debounce.
- Reopen followed by notification selection invalidates the pending show.
- Notification selection after a race-created show requests that panel be
  hidden.
- Reopen remains suppressed during notification activation and works again
  after the suppression window.
- Notification selection does not hide a panel that was already visible.
- Existing parser, state, 30-second polling-floor, and mocked Slack pagination
  after HTTP 429 checks continue to pass.
- Release builds complete and execute for both Apple Silicon (`arm64`) and Intel
  (`x86_64`), and the app's ad-hoc development code seal verifies.

## Manual release-owner checks still required

Follow `RELEASE_OWNER_CHECKLIST.md` with the packaged app:

1. Paste a test token into the secure field with Command+V.
2. Close the monitor panel, trigger a real linked ticket notification, click it,
   and confirm Slack opens without the panel appearing in front.
3. Reopen Help Center Monitor from Spotlight and confirm the controls still
   appear normally.

This remains a preview build until it is Developer ID signed, notarized, and
stapled. The shared-token and Slack rate-limit limitations documented in the
0.4.2 report remain unchanged.
