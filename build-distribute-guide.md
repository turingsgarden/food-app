High‑level flow
Update version/build in Xcode.
Archive a Release build.
Upload the archive to App Store Connect.
In App Store Connect, attach the new build to a new version and submit.
1. Update version & build in Xcode
In Xcode, open your project and select the project in the navigator (blue icon).
Select the iOS app target (probably food-app-swift).
Go to the “General” tab:
Version (marketing version) → bump e.g. 1.0.1.
Build → increment by 1, e.g. from 3 to 4.
Make sure:
Bundle Identifier matches the one used on App Store Connect.
Signing & Capabilities → Automatically manage signing is enabled (or correct profiles selected).
Team is your Apple Developer team.
2. Create a Release archive
At the top toolbar, select a real device or “Any iOS Device (arm64)” (not a simulator).
Select the “Any iOS Device (arm64)” or a physical device target and the “Release” scheme if you use multiple schemes.
In the menu: Product → Archive.
Xcode will build and then open the Organizer window when done.
3. Upload the archive from Organizer
In Organizer, select your new archive.
Click “Distribute App”.
Choose App Store Connect → Upload.
Go through the wizard:
Select the correct team.
Keep default options for bitcode (if shown) and symbols.
Make sure there are no signing or bundle identifier errors.
Click “Upload” and wait until it completes successfully.
You can confirm the upload in App Store Connect → My Apps → [Your App] → TestFlight or Activity → Builds after a few minutes.
4. Attach build to a new App Store version
Go to App Store Connect (https://appstoreconnect.apple.com).
My Apps → [Your App] → App Store tab → iOS App.
Click the “+” next to Version or create a New Version (e.g. 1.0.1 matching Xcode).
On that version page:
Under Build, click “Select a build” and pick the new build you just uploaded.
Update What’s New in This Version (e.g. “Improved dashboard: tap recent meals to open nutrition details.”).
Make sure all metadata, screenshots, and compliance fields are complete.
Click “Save”, then “Submit for Review”.
Apple will review the new version; once approved, it will go live per your release settings (manual or automatic).
If you tell me your current version/build values and what you want the next version to be, I can phrase the exact values you should type into Xcode and App Store Connect.s