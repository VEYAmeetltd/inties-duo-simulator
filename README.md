# INTIES on iPhone Duo: automatic screenshots

Takes App Store screenshots of INTIES on GitHub's iPhone Duo simulator, both
screens, folded and open, from a Windows PC.

## How to run

1. One-time: **Settings → Secrets and variables → Actions → New repository secret**,
   add `REVIEW_PASSWORD` (the App Review demo password). Secrets are never shown in
   logs or to visitors, even in a public repository.
2. **Actions → iPhone Duo screenshots → Run workflow**, paste the simulator build link.
3. After ~22 minutes, download **duo-screenshots** from the run. It is deleted after
   1 day. Files are named `outer-` / `inner-` (which screen) and `closed-` / `open-`
   (fold position).

## Notes

- Uses GitHub's standard `xcode-27` Mac runner (Apple Silicon),
  [serve-sim](https://github.com/EvanBacon/serve-sim) (Apache-2.0) to fold the phone,
  and [Maestro](https://maestro.mobile.dev) to sign in.
- Cost: standard GitHub runners are free in public repositories. In a private
  repository each Mac minute uses 10 of the account's included minutes, shared with
  every other repository on the account.
- App Store sizes for iPhone Duo: outer display 1398 × 2034, inner display 2007 × 2853.
