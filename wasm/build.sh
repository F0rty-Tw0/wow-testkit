#!/usr/bin/env bash
# Builds host/worker_bundle.js: stock Lua 5.1.5 plus wasm/tk_host.c compiled to one JS file by emcc, then bundled with
# the kit and host/worker.js (wasm/bundle.py). Needs emcc on PATH (source $EMSDK/emsdk_env.sh).
# Env: TK_WASM_CACHE (tarball and build output, default wasm/.cache), TK_LUA_SHA256 (the tarball's expected sha256),
# TK_EMCC_ANY=1 (build with an emcc other than EMCC_PINNED, which otherwise stops the build with exit 3).
set -euo pipefail
cd "$(dirname "$0")/.."

LUA_URL=https://www.lua.org/ftp/lua-5.1.5.tar.gz
LUA_SHA256=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333
EMCC_PINNED=6.0.13
CACHE="${TK_WASM_CACHE:-wasm/.cache}"
TARBALL="$CACHE/lua-5.1.5.tar.gz"
WANT="${TK_LUA_SHA256:-$LUA_SHA256}"

mkdir -p "$CACHE"
if [[ ! -f $TARBALL ]]; then
  curl -fsSL -o "$TARBALL.part" "$LUA_URL"
  mv "$TARBALL.part" "$TARBALL"
fi
GOT="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
if [[ $GOT != "$WANT" ]]; then
  echo "sha256 mismatch: got $GOT, want $WANT"
  exit 1
fi

# emcc's launcher needs the python emsdk bundles; Git Bash only has the Windows Store stub as python3.
EMSDK="${EMSDK:-$HOME/emsdk}"
if [[ -z ${EMSDK_PYTHON:-} ]]; then
  for candidate in "$EMSDK"/python/*/python.exe; do
    [[ -x $candidate ]] && export EMSDK_PYTHON="$candidate"
  done
fi
if ! command -v emcc > /dev/null; then
  echo "emcc not found: source \$EMSDK/emsdk_env.sh"
  exit 2
fi
VERSION="$(emcc --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [[ $VERSION != "$EMCC_PINNED" ]]; then
  if [[ ${TK_EMCC_ANY:-} != 1 ]]; then
    echo "emcc $VERSION, pinned $EMCC_PINNED: install the pinned emsdk, or set TK_EMCC_ANY=1 to build anyway"
    exit 3
  fi
  echo "warning: emcc $VERSION, pinned $EMCC_PINNED (TK_EMCC_ANY=1)"
fi

rm -rf "$CACHE/lua-5.1.5"
(cd "$CACHE" && tar xzf lua-5.1.5.tar.gz)
SRC="$CACHE/lua-5.1.5/src"
SOURCES=()
for file in "$SRC"/*.c; do
  case "$(basename "$file")" in lua.c | luac.c | print.c) ;; *) SOURCES+=("$file") ;; esac
done

# WORKERFS and IDBFS are exported as runtime methods: with -lworkerfs.js -lidbfs.js alone they are not on the module.
emcc -O2 -sSINGLE_FILE=1 -sMODULARIZE=1 -sENVIRONMENT=worker -sFORCE_FILESYSTEM=1 -lworkerfs.js -lidbfs.js \
  -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=1048576 -sEXPORTED_RUNTIME_METHODS=FS,ccall,WORKERFS,IDBFS \
  -sEXPORTED_FUNCTIONS=_tk_init,_tk_open,_tk_call,_tk_drain,_tk_shutdown \
  -I "$SRC" "${SOURCES[@]}" wasm/tk_host.c -o "$CACHE/tk_lua.js"

python wasm/bundle.py
echo "built host/worker_bundle.js ($(stat -c %s host/worker_bundle.js) bytes)"
