#!/bin/sh
# Headless Defold builds with bob.jar (downloaded for the installed editor's engine SHA).
#   defold/tools/bob.sh build            # desktop build into defold/build (then: dmengine)
#   defold/tools/bob.sh run [args...]    # build + run dmengine (e.g. --config=main.demo=1)
#   defold/tools/bob.sh web              # bundle for the browser into build/defold-web
#   defold/tools/bob.sh mac              # .app bundle into build/defold-mac
#   defold/tools/bob.sh android          # debug .apk (bob's debug keystore) into build/defold-android
#   defold/tools/bob.sh ios              # .app for iOS into build/defold-ios; needs IOS_IDENTITY and
#                                        # IOS_PROVISIONING (a signing identity and .mobileprovision)
# Environment: DEFOLD_APP (default /Applications/Defold.app), DEFOLD_TOOLS (cache dir for
# bob.jar / dmengine, default build/defold-tools).
set -e
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
ENGINE="$DEFOLD_TOOLS/dmengine-$SHA"
# Download to a temporary name and move it into place only on success, so an HTTP error or
# an interrupted transfer never leaves a broken file that later runs would take as cached.
fetch() {
  curl -fsSL -o "$1.part" "$2" || { rm -f "$1.part"; echo "download failed: $2" >&2; exit 1; }
  mv "$1.part" "$1"
}
[ -f "$BOB" ] || fetch "$BOB" "https://d.defold.com/archive/$SHA/bob/bob.jar"
[ -f "$ENGINE" ] || { fetch "$ENGINE" "https://d.defold.com/archive/$SHA/engine/$PLATFORM/dmengine"; chmod +x "$ENGINE"; }
bob() {
  "$JAVA" -Dcom.google.protobuf.use_unsafe_pre22_gencode=true -jar "$BOB" --root "$PROJECT" "$@"
}
cmd=${1:-build}
shift || true
# bob keeps one build directory per project; shader outputs are cached by hash, so a
# platform switch needs a clean build.
rm -rf "$PROJECT/build"
case "$cmd" in
  build) bob --platform "$PLATFORM" --variant debug build ;;
  run) bob --platform "$PLATFORM" --variant debug build && cd "$PROJECT" && exec "$ENGINE" "$@" ;;
  web) bob --platform wasm-web --variant debug --archive --bundle-output "$ROOT/build/defold-web" build bundle ;;
  mac) bob --platform "$PLATFORM" --variant debug --archive --bundle-output "$ROOT/build/defold-mac" build bundle ;;
  android) bob --platform arm64-android --architectures arm64-android --bundle-format apk --variant debug --archive \
    --bundle-output "$ROOT/build/defold-android" build bundle ;;
  ios) bob --platform arm64-ios --architectures arm64-ios --variant debug --archive --identity "$IOS_IDENTITY" \
    --mobileprovisioning "$IOS_PROVISIONING" --bundle-output "$ROOT/build/defold-ios" build bundle ;;
  *) echo "usage: $0 build|run|web|mac|android|ios" >&2; exit 2 ;;
esac
