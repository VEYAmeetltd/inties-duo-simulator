# INTIES on iPhone Duo (free, in your browser)

Runs INTIES on GitHub's iPhone Duo simulator and streams it to your browser,
so you can test it and take iPhone Duo App Store screenshots from a Windows PC.

## Automatic screenshots (recommended)

GitHub's free Macs have no graphics card, so the live Duo view below can't draw the
folding phone. The **iPhone Duo screenshots** workflow works without one:

1. One-time: **Settings → Secrets and variables → Actions → New repository secret**,
   add `REVIEW_PASSWORD` (the App Review demo password). Optional: `REVIEW_EMAIL`.
2. **Actions → iPhone Duo screenshots → Run workflow**, paste the simulator build link.
3. After ~15 minutes, download **duo-screenshots** from the run. Files are named
   `outer-` / `inner-` (which screen) and `closed-` / `open-` (fold position).

## Live viewer (needs a Mac with a GPU)

1. Go to **Actions → iPhone Duo simulator → Run workflow**.
2. Paste the **simulator build link** from Expo (a `.tar.gz` link) and pick how many minutes.
3. Open the run. After about 5 minutes the **summary** shows a link. Open it.
4. Tap and type on the phone with your mouse and keyboard. Use **Closed / Book / Open** to fold it,
   and the camera button to save screenshots to your PC.
5. Cancel the run when you're done to save minutes.

## Notes

- Uses GitHub's `xcode-27` Mac runner (Apple Silicon) and [serve-sim](https://github.com/EvanBacon/serve-sim) (Apache-2.0).
- The browser link is a temporary Cloudflare quick tunnel. A fresh random token is created every run;
  don't share the link.
- Free minutes: private repos get 2,000 Actions minutes a month and Mac minutes count 10x,
  so roughly 200 Mac minutes a month.
- App Store sizes for iPhone Duo: outer display 1398 × 2034, inner display 2007 × 2853.
- Screenshots taken automatically every 2 minutes, plus logs, are attached to each run as `duo-session`.
