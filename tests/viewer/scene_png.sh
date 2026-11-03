#!/usr/bin/env bash
# 3D scene proof: loads tests/viewer/scene_fixture.html in headless Chrome with software WebGL (SwiftShader), dumps the DOM
# to <scratch>/scene.html and a 1280x720 screenshot to <scratch>/scene.png, then runs check_scene.py on both. Not wired
# into CI or unit.sh, which stay --disable-gpu: this one needs GL. Without WebGL the page reports data-gl="none" and the
# check passes on the math-only fallback.
set -euo pipefail
cd "$(dirname "$0")/../.."
S="${1:?usage: scene_png.sh <scratch-dir>}"
CHROME="${CHROME:-C:/Program Files/Google/Chrome/Application/chrome.exe}"
mkdir -p "$S"
URL="file:///$(pwd -W 2>/dev/null || pwd)/tests/viewer/scene_fixture.html"
# A private profile keeps headless Chrome away from the user's running browser.
GL=(--headless=new --enable-unsafe-swiftshader --use-angle=swiftshader --user-data-dir="$S/profile-gl" --virtual-time-budget=8000)
timeout 120 "$CHROME" "${GL[@]}" --dump-dom "$URL" > "$S/scene.html"
timeout 120 "$CHROME" "${GL[@]}" --hide-scrollbars --window-size=1280,720 --screenshot="$S/scene.png" "$URL"
python tests/viewer/check_scene.py "$S/scene.html" "$S/scene.png"
