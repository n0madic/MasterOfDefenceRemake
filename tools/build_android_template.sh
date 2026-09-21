#!/usr/bin/env bash
# Build a trimmed Android export template (arm64, release) from the Godot sources.
#
#   tools/build_android_template.sh /path/to/godot-src [output-dir]
#
# The template drops everything the game does not use: 2D physics, navigation, XR and the
# import-time or networking modules. What stays: both renderers (Vulkan for the Mobile
# renderer on phones, OpenGL for gl_compatibility), GDScript, WebP (the imported textures),
# Ogg Vorbis, FreeType + the fallback text server (the debug Label and Control text), 3D
# physics (mouse picking). The "Android Custom" export preset points at the result.
#
# Needs: scons (`pip install scons`), JDK 17 (`brew install openjdk@17`), the Android SDK
# with cmdline-tools (scons installs the NDK it wants under $ANDROID_HOME/ndk).
set -euo pipefail

GODOT_SRC=${1:?usage: $0 GODOT_SRC [OUT_DIR]}
OUT_DIR=${2:-$(cd "$(dirname "$0")/.." && pwd)/build/templates}
JOBS=${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export JAVA_HOME=${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null || echo /opt/homebrew/opt/openjdk@17)}

DISABLED_MODULES=(
  astcenc basis_universal bcdec betsy bmp camera csg cvtt dds enet etcpak fbx gltf gridmap
  hdr interactive_music jolt_physics jpg jsonrpc ktx lightmapper_rd mbedtls meshoptimizer
  mobile_vr mp3 msdfgen multiplayer navigation_2d navigation_3d noise objectdb_profiler
  openxr raycast regex svg text_server_adv tga theora tinyexr upnp vhacd visual_shader
  webrtc websocket webxr xatlas_unwrap zip godot_physics_2d
)

SCONS_ARGS=(
  platform=android target=template_release arch=arm64
  production=yes optimize=size
  vulkan=yes opengl3=yes
  disable_physics_2d=yes disable_navigation_2d=yes disable_navigation_3d=yes disable_xr=yes
  module_text_server_fb_enabled=yes
  generate_android_binaries=yes
)
for m in "${DISABLED_MODULES[@]}"; do
  SCONS_ARGS+=("module_${m}_enabled=no")
done

cd "$GODOT_SRC"
# Swappy frame pacing, bundled with the official templates; the build refuses to run without it.
test -d thirdparty/swappy-frame-pacing || python3 misc/scripts/install_swappy_android.py
scons -j"$JOBS" "${SCONS_ARGS[@]}" swappy=yes

mkdir -p "$OUT_DIR"
cp bin/android_release.apk "$OUT_DIR/android_release.apk"
ls -l "$OUT_DIR/android_release.apk"
