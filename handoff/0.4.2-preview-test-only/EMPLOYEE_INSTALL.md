# Install Help Center Monitor

You do this once. You do not need Terminal, Python, or the source-code folder.

## Before you start

- macOS 13 or newer
- The approved Help Center Monitor DMG from the release owner
- The Slack access token sent to you **separately through the company password
  manager or approved secret-sharing tool**

Never put the token in email, an ordinary Slack message, or this guide.

## Install

1. Open **Help Center Monitor.dmg**.
2. Drag **Help Center Monitor** onto **Applications**.
3. Eject the disk image, then open **Help Center Monitor** from Applications.
4. Click **Allow** when macOS asks about notifications.
5. Paste the separately supplied Slack token into the secure setup box and
   click **Save**. If the box is not visible, click **Set Up Slack Access**.
6. Make sure the **Monitoring** switch is green and on.

If macOS says the developer cannot be verified, stop and contact the release
owner. Do not bypass the warning; the team release must be signed and notarized.

## Confirm it works

The panel should show:

- **Monitoring** is on
- **Slack connection** says **Monitoring**
- **Slack credentials** says **Secured**
- **Audible alerts** says **Enabled**
- **Last checked** shows a recent time
- The bottom line says it runs automatically at login

If automatic start needs approval, click the menu-bar bell, choose **Allow
Automatic Start…**, and enable Help Center Monitor in **System Settings →
General → Login Items**. Return to the app and confirm the bottom line is green.

Turn up the Mac's output volume and click **Send Test Alert**. You should receive
a notification banner, hear the Glass alert sound, and hear:

> New ticket in help-center

You can now close the panel. No Dock window is expected: the menu-bar bell stays
running, and the app starts automatically at login. Open it later from Spotlight
to enable or disable monitoring.

If any row remains red, use the button beside it or contact the release owner.
