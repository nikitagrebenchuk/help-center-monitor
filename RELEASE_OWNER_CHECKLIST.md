# Help Center Monitor release-owner check

Use this after receiving the final DMG. Employees do not need this checklist.

## Release gate

- Confirm the DMG is version 0.7.0 and came from the release folder.
- Confirm the unsigned internal DMG contains **Read Me First** and
  **2 - After Warning - Open Privacy & Security**. Distribute it only through a
  trusted internal channel.
- Send the Slack token separately through the company password manager or an
  approved one-time secret link. Never place it in the DMG or installation guide.

## Clean installation test

1. Follow `EMPLOYEE_INSTALL.md` exactly on a Mac that has not approved this
   build. Confirm the Privacy & Security shortcut opens the correct pane and the
   **Open Anyway → Open** flow launches the app.
   Confirm the Slack token can be pasted with **Command+V**; do not use the
   contextual right-click menu for this check.
2. Wait until **Slack connection** says **Monitoring** and **Last checked** has a
   current time before creating the Slack test.
3. Select **Immediate** and click **Send Test Alert**. Confirm the
   banner, Glass sound, and spoken words
   “New ticket in help-center.”
4. Select **Pylon 2 min** and click **Verify Pylon 2-Minute Feed**. Confirm it
   finds a real recent Pylon SLA-breach event in `#wg-first-touch-monitor`, sends
   a labeled test banner, plays Glass, and says “Help Center message unanswered
   for 2 minutes.” Confirm no Slack message was posted by the test.
5. Confirm the Monitoring Bot is a member of both
   `#monitor-first-touch-missing` and `#wg-first-touch-monitor`. The app should
   not require access to `#help-center` or any customer channel for this feature.
6. In **Immediate** mode, post one new top-level test event in
   `#monitor-first-touch-missing`. Do not post it as a thread reply.
7. Under normal successful polling, expect the immediate alert within roughly 30 seconds
   plus network response time. Slack rate limiting, sleep, or an outage can make
   it longer.
8. In **Pylon 2 min** mode, cause a real two-minute first- or next-response SLA
   breach in Pylon. Confirm the app alerts after the breach event reaches
   `#wg-first-touch-monitor`, and that an ordinary non-breach channel message
   does not alert.
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
