#!/usr/bin/env bash
# Automatic iPhone Duo screenshots of INTIES on a GitHub macOS runner.
# Boots the Duo simulator, installs INTIES, signs in with the App Review demo
# account (Maestro), then opens each screen by deep link and saves screenshots
# of BOTH Duo displays, closed and open. No GPU or live viewer is needed.
set -euo pipefail

APP_URL="${APP_URL:?APP_URL is required}"
XCODE_VERSION="${XCODE_VERSION:-27.2}"
BUNDLE_ID="${BUNDLE_ID:-com.intiesltd.inties}"
SERVE_SIM_VERSION="${SERVE_SIM_VERSION:-0.1.49}"
SCREENS="${SCREENS:-discover matches bookings profile settings settings/themes safety-verification help/faq whats-new system-status profile-preview}"
OUT="${GITHUB_WORKSPACE:-$PWD}/out"
mkdir -p "$OUT/screenshots" "$OUT/logs" "$OUT/maestro"

summary() { echo "$*" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"; echo "$*"; }

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
[ -z "$XCODE_APP" ] && XCODE_APP="$(ls -d /Applications/Xcode_27*.app | sort -V | tail -1)"
sudo xcode-select -s "$XCODE_APP/Contents/Developer"
xcodebuild -version
echo "::endgroup::"

echo "::group::Boot the iPhone Duo simulator"
xcrun simctl list devices available -j > "$OUT/logs/devices.json"
UDID="$(/usr/bin/python3 - "$OUT/logs/devices.json" "$XCODE_VERSION" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))["devices"]
want = sys.argv[2].replace(".", "-")
duos = [(rt, d) for rt, ds in data.items() for d in ds if d["name"] == "iPhone Duo"]
duos.sort(key=lambda x: (want not in x[0], x[0]))
print(duos[0][1]["udid"] if duos else "")
PY
)"
[ -z "$UDID" ] && { echo "No iPhone Duo simulator found"; exit 1; }
echo "UDID $UDID"
booted=""
for attempt in 1 2 3; do
  xcrun simctl boot "$UDID" 2>/dev/null || true
  if with_timeout 240 xcrun simctl bootstatus "$UDID" -b; then booted=1; break; fi
  if xcrun simctl list devices | grep -q "$UDID) (Booted)"; then booted=1; break; fi
  echo "Boot attempt $attempt failed; erasing and retrying."
  xcrun simctl shutdown "$UDID" 2>/dev/null || true; sleep 5
  xcrun simctl erase "$UDID" || true
done
[ -z "$booted" ] && { echo "Could not boot the iPhone Duo"; exit 1; }
open -a "Device Hub" 2>/dev/null || open -a Simulator 2>/dev/null || true
sleep 15
echo "::endgroup::"

# Work out the two display ids (outer 1398x2034, inner 2007x2853) from simctl.
probe="$(xcrun simctl io "$UDID" screenshot /tmp/probe.png 2>&1 || true)"
echo "$probe" > "$OUT/logs/displays.txt"
OUTER_ID="$(echo "$probe" | grep -E '1398x2034|2034x1398' | grep -oE 'display=[0-9]+' | head -1 | cut -d= -f2 || true)"
INNER_ID="$(echo "$probe" | grep -E '2007x2853|2853x2007' | grep -oE 'display=[0-9]+' | head -1 | cut -d= -f2 || true)"
echo "Outer display id: ${OUTER_ID:-?}  Inner display id: ${INNER_ID:-?}"

shoot() { # shoot <name>
  local name="$1"
  if [ -n "$OUTER_ID" ]; then
    xcrun simctl io "$UDID" screenshot --display="$OUTER_ID" "$OUT/screenshots/outer-$name.png" >/dev/null 2>&1 || true
  fi
  if [ -n "$INNER_ID" ]; then
    xcrun simctl io "$UDID" screenshot --display="$INNER_ID" "$OUT/screenshots/inner-$name.png" >/dev/null 2>&1 || true
  fi
  if [ -z "$OUTER_ID$INNER_ID" ]; then
    xcrun simctl io "$UDID" screenshot "$OUT/screenshots/$name.png" >/dev/null 2>&1 || true
  fi
}

SERVE_SIM_STARTED=""
start_serve_sim() {
  # `serve-sim fold` talks to a running serve-sim server; start one in the
  # background (no viewer, local only).
  [ -n "$SERVE_SIM_STARTED" ] && return 0
  export SERVE_SIM_CONTROL=1
  with_timeout 120 npx -y "serve-sim@${SERVE_SIM_VERSION}" --detach "$UDID" \
    >> "$OUT/logs/fold.log" 2>&1 || echo "serve-sim --detach failed (see logs/fold.log)"
  SERVE_SIM_STARTED=1
  sleep 5
}

fold() { # fold <degrees>  0 = closed, 180 = open
  start_serve_sim
  echo "--- fold $1" >> "$OUT/logs/fold.log"
  with_timeout 60 npx -y "serve-sim@${SERVE_SIM_VERSION}" fold "$1" -d "$UDID" \
    >> "$OUT/logs/fold.log" 2>&1 || echo "fold $1 failed (see logs/fold.log)"
  sleep 6
}

confirm_open() {
  # Taps "Open" on the iOS link prompt (and "Not Now" on a save-password sheet).
  with_timeout 90 maestro --device "$UDID" test maestro/confirm-open.yaml \
    >> "$OUT/logs/maestro-open.log" 2>&1 || true
}

echo "::group::Install INTIES"
curl -fsSL "$APP_URL" -o "$RUNNER_TEMP/app.tar.gz"
mkdir -p "$RUNNER_TEMP/app" && tar -xzf "$RUNNER_TEMP/app.tar.gz" -C "$RUNNER_TEMP/app"
APP_PATH="$(find "$RUNNER_TEMP/app" -maxdepth 3 -name '*.app' -type d | head -1)"
xcrun simctl install "$UDID" "$APP_PATH"
echo "::endgroup::"

echo "::group::Sign in with Maestro"
if ! command -v maestro >/dev/null 2>&1; then
  curl -fsSL "https://get.maestro.mobile.dev" | bash >/dev/null
  export PATH="$HOME/.maestro/bin:$PATH"
fi
fold 0
signed_in=1
if ! maestro --device "$UDID" test \
     -e REVIEW_EMAIL="${REVIEW_EMAIL:-app-review@intiesltd.com}" \
     -e REVIEW_PASSWORD="${REVIEW_PASSWORD:-}" \
     --test-output-dir "$OUT/maestro" \
     maestro/login.yaml > "$OUT/logs/maestro.log" 2>&1; then
  echo "Maestro sign-in did not finish; screenshots will show whatever is on screen."
  tail -40 "$OUT/logs/maestro.log" || true
  signed_in=0
fi
echo "::endgroup::"

echo "::group::Screenshots"
for pose in closed open; do
  if [ "$pose" = closed ]; then fold 0; else fold 180; fi
  for route in $SCREENS; do
    name="${pose}-$(echo "$route" | tr '/' '-')"
    xcrun simctl openurl "$UDID" "inties:///$route" >/dev/null 2>&1 || true
    sleep 2
    confirm_open
    sleep 2
    shoot "$name"
  done
done
echo "::endgroup::"

count="$(ls "$OUT/screenshots" | wc -l | tr -d ' ')"
summary "## iPhone Duo screenshots"
summary ""
summary "- Signed in: $([ "$signed_in" = 1 ] && echo yes || echo 'no (check logs/maestro.log)')"
summary "- Outer display id: ${OUTER_ID:-not found}, inner display id: ${INNER_ID:-not found}"
summary "- Screenshots saved: $count (download **duo-screenshots** below)"
summary "- File names: outer-/inner- = which screen, closed-/open- = fold position"
