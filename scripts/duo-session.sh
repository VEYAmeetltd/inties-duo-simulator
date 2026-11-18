#!/usr/bin/env bash
# Boots the iPhone Duo simulator on a GitHub macOS runner, installs an INTIES
# simulator build, and streams it to a browser with serve-sim through a
# temporary Cloudflare quick tunnel. Everything here is free and needs no
# extra accounts.
set -euo pipefail

APP_URL="${APP_URL:?APP_URL is required}"
MINUTES="${MINUTES:-30}"
XCODE_VERSION="${XCODE_VERSION:-27.2}"
BUNDLE_ID="${BUNDLE_ID:-com.intiesltd.inties}"
SERVE_SIM_VERSION="${SERVE_SIM_VERSION:-0.1.49}"
OUT="${GITHUB_WORKSPACE:-$PWD}/out"
mkdir -p "$OUT/screenshots" "$OUT/logs"

summary() { echo "$*" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"; echo "$*"; }

# macOS has no `timeout`; run a command and kill it after N seconds.
with_timeout() {
  local secs="$1"; shift
  "$@" & local pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) & local watcher=$!
  local rc=0
  wait "$pid" || rc=$?
  kill "$watcher" 2>/dev/null || true
  return "$rc"
}

echo "::group::Select Xcode $XCODE_VERSION"
XCODE_APP="$(ls -d /Applications/Xcode_${XCODE_VERSION}*.app 2>/dev/null | head -1 || true)"
if [ -z "$XCODE_APP" ]; then
  echo "Xcode $XCODE_VERSION not found, available:"; ls -d /Applications/Xcode*.app
  XCODE_APP="$(ls -d /Applications/Xcode_27*.app | sort -V | tail -1)"
fi
sudo xcode-select -s "$XCODE_APP/Contents/Developer"
xcodebuild -version
echo "::endgroup::"

echo "::group::Find the iPhone Duo simulator"
xcrun simctl list runtimes | tee "$OUT/logs/runtimes.txt"
xcrun simctl list devices available -j > "$OUT/logs/devices.json"
UDID="$(/usr/bin/python3 - "$OUT/logs/devices.json" "$XCODE_VERSION" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))["devices"]
want = sys.argv[2].replace(".", "-")
duos = [(rt, d) for rt, ds in data.items() for d in ds if d["name"] == "iPhone Duo"]
duos.sort(key=lambda x: (want not in x[0], x[0]), reverse=False)
print(duos[0][1]["udid"] if duos else "")
PY
)"
if [ -z "$UDID" ]; then
  echo "No 'iPhone Duo' simulator on this image. Device types:"; xcrun simctl list devicetypes
  exit 1
fi
echo "iPhone Duo UDID: $UDID"
echo "::endgroup::"

echo "::group::Boot the simulator"
# A fresh simulator's first-boot "Data Migration" can fail on CI machines;
# when it does, wipe the device and boot it again (up to 3 attempts).
booted=""
for attempt in 1 2 3; do
  xcrun simctl boot "$UDID" 2>/dev/null || true
  if with_timeout 240 xcrun simctl bootstatus "$UDID" -b; then booted=1; break; fi
  echo "Boot attempt $attempt failed; erasing the simulator and retrying."
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  sleep 5
  xcrun simctl erase "$UDID" || true
done
if [ -z "$booted" ]; then
  # Data migration can report failure while the device is actually usable.
  if xcrun simctl list devices | grep -q "$UDID) (Booted)"; then
    echo "Boot status reported a failure, but the device is booted; continuing."
  else
    echo "Could not boot the iPhone Duo simulator."; exit 1
  fi
fi
# Xcode 27 shows simulators in Device Hub; keyboard forwarding needs its window.
open -a "Device Hub" 2>/dev/null || open -a Simulator 2>/dev/null || true
sleep 10
xcrun simctl io "$UDID" enumerate | tee "$OUT/logs/displays.txt" || true
echo "::endgroup::"

echo "::group::Install INTIES"
curl -fsSL "$APP_URL" -o "$RUNNER_TEMP/app.tar.gz"
mkdir -p "$RUNNER_TEMP/app" && tar -xzf "$RUNNER_TEMP/app.tar.gz" -C "$RUNNER_TEMP/app"
APP_PATH="$(find "$RUNNER_TEMP/app" -maxdepth 3 -name '*.app' -type d | head -1)"
echo "App: $APP_PATH"
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID" || true
sleep 8
xcrun simctl io "$UDID" screenshot "$OUT/screenshots/00-launch.png" || true
echo "::endgroup::"

echo "::group::Start serve-sim and the browser link"
TOKEN="$(openssl rand -hex 24)"
export SERVE_SIM_CONTROL=1
npx -y "serve-sim@${SERVE_SIM_VERSION}" "$UDID" --port 3200 --auth-token "$TOKEN" \
  > "$OUT/logs/serve-sim.log" 2>&1 &
for i in $(seq 1 60); do
  curl -s -o /dev/null http://localhost:3200 && break
  sleep 2
done
brew list cloudflared >/dev/null 2>&1 || brew install cloudflared >/dev/null
cloudflared tunnel --no-autoupdate --url http://localhost:3200 > "$OUT/logs/cloudflared.log" 2>&1 &
PUBLIC_URL=""
for i in $(seq 1 60); do
  PUBLIC_URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$OUT/logs/cloudflared.log" | head -1 || true)"
  [ -n "$PUBLIC_URL" ] && break
  sleep 2
done
if [ -z "$PUBLIC_URL" ]; then
  echo "Tunnel did not start:"; cat "$OUT/logs/cloudflared.log"; exit 1
fi
summary "## iPhone Duo is running"
summary ""
summary "Open this link in your browser (it stays up for about ${MINUTES} minutes):"
summary ""
summary "**${PUBLIC_URL}/#token=${TOKEN}**"
summary ""
summary "Use the Closed / Book / Open buttons to fold the phone, and the camera button to save screenshots to your PC."
summary "To finish early, cancel this run in GitHub."
echo "::endgroup::"

# Keep the phone up, saving a screenshot of whatever is showing every 2 minutes
# so there's a record even if nobody is watching.
END=$(( $(date +%s) + MINUTES * 60 ))
n=1
while [ "$(date +%s)" -lt "$END" ]; do
  sleep 120
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/$(printf '%02d' "$n")-auto.png" >/dev/null 2>&1 || true
  n=$((n + 1))
done
summary ""
summary "Session ended. Screenshots and logs are attached to this run as 'duo-session'."
