# Help Center Monitor 0.4.2 QA report

Date: 2026-07-17  
Build: 11

## Passed

- Offline parser, state, enablement, and timestamp checks.
- Mocked Slack multi-page history test: page two returns HTTP 429 once, the
  client waits, retries the same cursor, and returns every message oldest-first.
- Release build succeeds for both `arm64` and `x86_64`.
- Both architecture slices execute `--bundle-check` successfully.
- App bundle plists validate and the ad-hoc development code seal verifies.
- The binary contains the 30-second UI copy and spoken text
  `New ticket in help-center`.
- The DMG structure, SHA-256 checksum, embedded app seal, universal binary, and
  embedded employee guide verify after mounting.
- Local runtime evidence confirmed notification permission, Slack authentication
  as the configured monitor bot, successful test notifications, real ticket
  delivery, and successful Slack HTTP 200 polls about 30.8 seconds apart.
- macOS Background Task Management reported the main app login item as enabled
  and allowed.

## Fixed during the pass

- Changed polling from 60 seconds plus jitter to 30 seconds.
- Changed speech to `New ticket in help-center`.
- Queued rapid audible alerts so speech is not interrupted.
- Preserved Slack pagination across rate limits instead of restarting page one.
- Waited for notification scheduling/fallback before persisting a ticket as seen.
- Made the panel show the real automatic-start state and refresh it after
  returning from System Settings.
- Made fatal Slack credential states visible in the menu-bar icon and panel.
- Made first credential setup re-enable monitoring automatically.
- Skipped messages received while monitoring was deliberately disabled.
- Scoped Keychain read/update/delete operations to the current account.
- Replaced direct executable handoff with LaunchServices behavior.
- Added a supported uninstall-preparation mode for the login item, notifications,
  Keychain credential, preferences, and legacy state.
- Made the app universal for Apple Silicon and Intel Macs.
- Moved the DMG checksum after signing/notarization/stapling and added optional
  DMG code signing.

## Release blockers / limits

- This Mac has no Developer ID signing identity or usable notary profile. The
  generated DMG is an **unsigned, ad-hoc development preview** and must not be
  sent to employees. A rebuild changes its code identity and can cause a
  Keychain approval prompt; the final exact build demonstrated that prompt.
- Slack may enforce a `conversations.history` rate below the requested
  30-second frequency. The app obeys `Retry-After`, so real delivery can take
  60 seconds or longer. Multiple local copies can share that limit.
- No finite QA pass can prove software is 100% bug-free. A true first-install
  notification prompt and login-after-restart flow must be checked on a new
  macOS user, VM, or separate Mac because macOS can retain permission metadata.
- Broad deployment remains safer and more reliable with the previously proposed
  Slack Events backend, where employee Macs do not contain a shared bot token.

## Distribution gate

Before team distribution, use a real Developer ID Application identity and
notary profile with `scripts/package_dmg.sh`, then repeat the release-owner
checklist on a clean Mac. Only the signed, notarized, stapled DMG and employee
guide should be distributed; the token must be delivered separately through an
approved password manager or one-time secret link.
