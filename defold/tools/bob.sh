#!/bin/sh
# Headless Defold builds with bob.jar (downloaded for the installed editor's engine SHA).
#   defold/tools/bob.sh build            # desktop build into defold/build (then: the engine of
#                                        # the same VARIANT, dmengine_release by default)
#   defold/tools/bob.sh run [args...]    # build + run the engine (e.g. --config=main.demo=1)
#   defold/tools/bob.sh web              # bundle for the browser into build/defold-web
#   defold/tools/bob.sh mac              # .app bundle into build/defold-mac
#   defold/tools/bob.sh android          # .apk (bob's debug keystore) into build/defold-android
#   defold/tools/bob.sh ios              # .app for iOS into build/defold-ios; needs IOS_IDENTITY and
#                                        # IOS_PROVISIONING (a signing identity and .mobileprovision)
# Environment: DEFOLD_APP (default /Applications/Defold.app), DEFOLD_TOOLS (cache dir for
# bob.jar / dmengine, default build/defold-tools), VARIANT (engine variant of every command:
# release by default -- no profiler, engine log or debug web server, smaller, and no Lua
# `print`, so main/log.lua is silent; debug for the log, `log_level=debug` and the profiler),
# BOB_STALL_SECONDS (see `bob` below).
set -e
VARIANT=${VARIANT:-release}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PROJECT="$ROOT/defold"
DEFOLD_APP=${DEFOLD_APP:-/Applications/Defold.app}
DEFOLD_TOOLS=${DEFOLD_TOOLS:-$ROOT/build/defold-tools}
CONFIG="$DEFOLD_APP/Contents/Resources/config"
SHA=$(sed -n 's/^engine_sha1 = //p' "$CONFIG")
JAVA="$DEFOLD_APP/Contents/Resources/packages/$(ls "$DEFOLD_APP/Contents/Resources/packages" | grep '^jdk' | head -1)/bin/java"
case "$(uname -m)" in
  arm64) PLATFORM=arm64-macos ;;
  *) PLATFORM=x86_64-macos ;;
esac
mkdir -p "$DEFOLD_TOOLS"
BOB="$DEFOLD_TOOLS/bob-$SHA.jar"
case "$VARIANT" in
  debug) ENGINE_NAME=dmengine ;;
  release) ENGINE_NAME=dmengine_release ;;
  *) echo "VARIANT must be debug or release" >&2; exit 2 ;;
esac
ENGINE="$DEFOLD_TOOLS/$ENGINE_NAME-$SHA"
# Download to a temporary name and move it into place only on success, so an HTTP error or
# an interrupted transfer never leaves a broken file that later runs would take as cached.
fetch() {
  curl -fsSL -o "$1.part" "$2" || { rm -f "$1.part"; echo "download failed: $2" >&2; exit 1; }
  mv "$1.part" "$1"
}
[ -f "$BOB" ] || fetch "$BOB" "https://d.defold.com/archive/$SHA/bob/bob.jar"
[ -f "$ENGINE" ] || { fetch "$ENGINE" "https://d.defold.com/archive/$SHA/engine/$PLATFORM/$ENGINE_NAME"; chmod +x "$ENGINE"; }

# bob 1.13.1's BasisU encoder now and then deadlocks in its job pool (a worker misses the
# shutdown wake-up and `join` waits forever, the process idle). When the CPU time of bob and
# all its descendants stops growing for BOB_STALL_SECONDS, bob's native stack is sampled: the
# deadlock (the job pool's destructor joining its workers) kills the process tree and retries
# the build, anything else (a download, a native-extension build server) keeps waiting. The
# build directory is kept, so a retry resumes where the last one stopped.
BOB_STALL_SECONDS=${BOB_STALL_SECONDS:-60}
BOB_ATTEMPTS=3
BOB_IDLE_CENTISECONDS=3  # CPU per second below which bob counts as idle (the JVM's own ticks)
BASISU_DEADLOCK='basisu::job_pool::~job_pool'
descendants() {
  local child
  for child in $(pgrep -P "$1"); do
    echo "$child"
    descendants "$child"
  done
}
cpu_centiseconds() {
  for p in "$1" $(descendants "$1"); do ps -o time= -p "$p"; done |
    awk '{ n = split($1, f, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + f[i]; t += s } END { printf "%d\n", t * 100 }'
}
basisu_deadlocked() {
  sample "$1" 1 2>/dev/null | grep -q "$BASISU_DEADLOCK"
}
running() {
  state=$(ps -o stat= -p "$1" 2>/dev/null) && [ "${state#Z}" = "$state" ]
}
# --texture-compression applies the compressors of render/level.texture_profiles (without it
# bob stores every texture as raw RGBA).
bob() {
  attempt=1
  while :; do
    "$JAVA" -Dcom.google.protobuf.use_unsafe_pre22_gencode=true -jar "$BOB" --root "$PROJECT" --texture-compression "$@" &
    pid=$!
    last=$(cpu_centiseconds "$pid")
    idle=0
    stalled=
    while running "$pid"; do
      sleep 1
      now=$(cpu_centiseconds "$pid")
      if [ $((now - last)) -lt "$BOB_IDLE_CENTISECONDS" ]; then idle=$((idle + 1)); else idle=0; fi
      last=$now
      if [ "$idle" -ge "$BOB_STALL_SECONDS" ]; then
        if ! basisu_deadlocked "$pid"; then
          idle=0
          continue
        fi
        stalled=1
        kill $(descendants "$pid") "$pid" 2>/dev/null || true
        break
      fi
    done
    status=0
    wait "$pid" || status=$?
    if [ -z "$stalled" ]; then
      return "$status"
    fi
    if [ "$attempt" -ge "$BOB_ATTEMPTS" ]; then
      echo "bob deadlocked $attempt times, giving up" >&2
      return 1
    fi
    attempt=$((attempt + 1))
    echo "bob deadlocked in the BasisU encoder, retrying ($attempt/$BOB_ATTEMPTS)" >&2
  done
}
cmd=${1:-build}
shift || true
# bob keeps one build directory per project; shader outputs are cached by hash, so a
# platform switch needs a clean build.
rm -rf "$PROJECT/build"
case "$cmd" in
  build) bob --platform "$PLATFORM" --variant "$VARIANT" build ;;
  run) bob --platform "$PLATFORM" --variant "$VARIANT" build && cd "$PROJECT" && exec "$ENGINE" "$@" ;;
  web) bob --platform wasm-web --variant "$VARIANT" --archive --bundle-output "$ROOT/build/defold-web" build bundle
    # The web template has no icon setting: link the favicon.ico the bundle resources put
    # next to index.html (browsers only probe /favicon.ico at the site root).
    for html in "$ROOT"/build/defold-web/*/index.html; do
      perl -pi -e 's|</title>|</title>\n\t<link rel="icon" href="favicon.ico">|' "$html"
    done ;;
  mac) bob --platform "$PLATFORM" --variant "$VARIANT" --archive --bundle-output "$ROOT/build/defold-mac" build bundle ;;
  android) bob --platform arm64-android --architectures arm64-android --bundle-format apk --variant "$VARIANT" --archive \
    --bundle-output "$ROOT/build/defold-android" build bundle ;;
  ios) bob --platform arm64-ios --architectures arm64-ios --variant "$VARIANT" --archive --identity "$IOS_IDENTITY" \
    --mobileprovisioning "$IOS_PROVISIONING" --bundle-output "$ROOT/build/defold-ios" build bundle ;;
  *) echo "usage: $0 build|run|web|mac|android|ios" >&2; exit 2 ;;
esac
