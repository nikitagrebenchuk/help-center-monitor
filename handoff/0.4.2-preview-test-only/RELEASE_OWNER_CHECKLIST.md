# Help Center Monitor release-owner check

Use this after receiving the final DMG. Employees do not need this checklist.

## Release gate

- Confirm the DMG is version 0.4.2 and came from the release folder.
- Confirm it is Developer ID signed, notarized, and stapled. Do not distribute an
  ad-hoc preview build.
- Send the Slack token separately through the company password manager or an
  approved one-time secret link. Never place it in the DMG or installation guide.

## Clean installation test

1. Follow `EMPLOYEE_INSTALL.md` exactly.
2. Wait until **Slack connection** says **Monitoring** and **Last checked** has a
   current time before creating the Slack test.
3. Click **Send Test Alert**. Confirm the banner, Glass sound, and spoken words
   “New ticket in help-center.”
4. Post one new **top-level** test message in the monitored Slack channel. Do not
   post it as a thread reply.
5. Under normal successful polling, expect the alert within roughly 30 seconds
   plus network response time. Slack rate limiting, sleep, or an outage can make
   it longer.
6. Click the notification and confirm that it opens the correct Slack message.
7. Turn monitoring off, post another test, wait 35 seconds, and confirm no alert.
   Turn monitoring back on; messages posted while off should not alert later.
8. Log out and back in (or restart the Mac). Confirm the menu-bar bell returns
   without manually opening the app, then repeat **Send Test Alert**.

A reinstall on the same macOS account may retain the prior notification choice.
Use a new macOS user, VM, or separate Mac to validate the true first-ever
permission prompt.
