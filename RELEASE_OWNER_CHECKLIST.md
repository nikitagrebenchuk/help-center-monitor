# Help Center Monitor release-owner check

Use this after receiving the final DMG. Employees do not need this checklist.

## Release gate

- Confirm the DMG is version 0.8.3 and came from the release folder.
- Confirm the unsigned internal DMG contains **Read Me First** and
  **2 - After Warning - Open Privacy & Security**. Distribute it only through a
  trusted internal channel.
- Confirm managed Macs have the AWS CLI, an active `prod-read-only` SSO session,
  and `secretsmanager:GetSecretValue` access limited to
  `/production/monitoring/help-center-monitor`. Keep the Slack token available
  through the company password manager only as a fallback. Never place it in the
  DMG or installation guide.

## Clean installation test

1. Follow `EMPLOYEE_INSTALL.md` exactly on a Mac that has not approved this
   build. Confirm the Privacy & Security shortcut opens the correct pane and the
   **Open Anyway → Open** flow launches the app.
   Confirm Slack access loads automatically from AWS without displaying a paste
   prompt. Separately test the failure path and confirm the fallback token can be
   pasted with **Command+V**; do not use the contextual right-click menu for this
   check.
2. Wait until **Slack connection** says **Monitoring** and **Last checked** has a
   current time before creating the Slack test.
3. Click **Send Test Alert**. Confirm the banner, Glass sound, and spoken words
   “New message in the alert channel.”
4. Enable **Team voice-overs**, click **Test Team Voice Alert**, and confirm a
   teammate recording replaces the system voice while Glass still plays. Turn
   the switch off and confirm the next test uses the default voice again.
5. Confirm the Monitoring Bot is a member of `#help-center` (`C07ES26GU2D`) and
   `#dispatcher` (`C0BJLB6NYQ7`). No other channel membership is required for
   monitoring.
6. Post one new top-level test event in each monitored channel. Do not post
   either event as a thread reply. Confirm that each message produces its own
   alert and that the notification title identifies the correct source channel.
7. Under normal successful polling, expect the alert within roughly 30 seconds
   plus network response time. Slack rate limiting, sleep, or an outage can make
   it longer.
8. Post in a third Slack channel and confirm the app does not alert.
9. Close the monitor panel, click the notification, and confirm that it opens
   the correct Slack message without reopening or leaving the monitor panel in
   front of Slack.
10. Turn monitoring off, post another test, wait 35 seconds, and confirm no alert.
   Turn monitoring back on; messages posted while off should not alert later.
11. Log out and back in (or restart the Mac). Confirm the menu-bar bell returns
   without manually opening the app, then repeat **Send Test Alert**.

A reinstall on the same macOS account may retain the prior notification choice.
Use a new macOS user, VM, or separate Mac to validate the true first-ever
permission prompt.
