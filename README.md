# Strapify Picklist for iPhone

A native shell around https://picklist.strapify.com.au. Everything on screen is the live web
picklist, so **a picklist deploy updates the app instantly with no new build**.

What the shell adds:
- **Apple's own barcode scanner** (VisionKit) in place of the web camera: real autofocus and macro,
  laid exactly over the scan screen's camera area, so the result line, alerts and ✕ are unchanged.
  `public/js/scan.js` (picklist 3.513+) switches to it when `window.__nativeScanAvailable` is true.
- Full-screen layout like the Home Screen PWA on every screen, iPhone Duo folded and open
  (built with Xcode 27 on the `xcode-27` runner; the page owns the safe areas).
- Stays signed in; Shopify admin and other outside links open outside the app.

A new build (Actions > testflight > Run workflow) is only needed for native changes.
Signing: same team/certificate/API key as Messenger; profile "Picklist App Store".
