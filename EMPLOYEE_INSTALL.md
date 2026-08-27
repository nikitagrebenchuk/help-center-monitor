# Install Help Center Monitor

You do this once. You do not need Terminal, Python, or the source-code folder.

## Before you start

- macOS 13 or newer
- The approved Help Center Monitor DMG from the release owner
- The standard AWS CLI and an active `prod-read-only` SSO session on your managed
  Mac

The app loads Slack access automatically. If that fails, obtain the fallback
token through the company password manager or approved secret-sharing tool.
Never put the token in email, an ordinary Slack message, or this guide.

## Install

1. Open **Help Center Monitor.dmg**.
2. Drag **Help Center Monitor** onto **Applications**. If macOS asks whether to
   replace an existing copy, choose **Replace**.
3. Open **Help Center Monitor** from Applications.
4. If macOS says **Help Center Monitor Not Opened**, click **Done**. Do not click
   **Move to Trash**.
5. Return to the disk image and open **2 - After Warning - Open Privacy &
   Security**.
6. In the Security section, click **Open Anyway** beside Help Center Monitor.
   Authenticate with Touch ID or your Mac login password, then click **Open**.
   If the app opened normally in step 3, skip steps 4–6.
7. Eject the disk image.
8. Click **Allow** when macOS asks about notifications.
9. Wait while the app loads Slack access automatically from AWS Secrets Manager.
   Only if the secure fallback box appears, paste the separately supplied token
   with **Command+V**, then click **Save**.
10. Make sure the **Monitoring** switch is green and on. The panel should say it
    watches `#help-center` and `#dispatcher`.

The Privacy & Security approval is required once for this internal unsigned
build. A newly rebuilt version may require the same approval again.

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

> New message in the alert channel

To use the team recordings instead, enable **Team voice-overs** in the app and
click **Test Team Voice Alert**. Each alert will choose a recording randomly.

You can now close the panel. No Dock window is expected: the menu-bar bell stays
running, and the app starts automatically at login. Open it later from Spotlight
to enable or disable monitoring.

If any row remains red, use the button beside it or contact the release owner.
