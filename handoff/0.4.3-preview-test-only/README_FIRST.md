# Version 0.4.3 preview test

This build fixes two reported behaviors:

- **Command+V** now pastes into the secure Slack-token field.
- Clicking a linked ticket notification opens Slack without reopening the Help
  Center Monitor control panel in front of it.

Follow `RELEASE_OWNER_CHECKLIST.md`, including its explicit checks for both
behaviors. The employee-facing steps are in `EMPLOYEE_INSTALL.md` and are also
embedded inside the DMG as `Install Help Center Monitor.txt`.

This remains an ad-hoc-signed preview because this Mac has no Developer ID
Application identity or notarization profile. Use it for the release-owner test,
but do not send it to employees until it is Developer ID signed, notarized, and
stapled.
