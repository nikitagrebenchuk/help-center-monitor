# Preview test only — do not send this build to the team

This folder contains the complete 0.4.2 test package for the release owner's
clean reinstall and end-to-end check.

The DMG is a valid universal app and passed the checks in `QA_REPORT_0.4.2.md`,
but it is ad-hoc signed because this Mac has no Developer ID Application
identity or working notarization profile. A downloaded copy can trigger
Gatekeeper and repeat Keychain approval prompts.

Before sending anything to employees:

1. Build with the company's Developer ID Application identity.
2. Notarize and staple the DMG.
3. Repeat `RELEASE_OWNER_CHECKLIST.md` on a clean Mac or macOS user.
4. Send employees only the signed/notarized DMG and `EMPLOYEE_INSTALL.md`.
5. Send the Slack token separately through the approved password manager or a
   one-time secret link. Never include it in this folder, DMG, guide, email, or
   an ordinary Slack message.
