#!/usr/bin/env bash
# Mirror one wow-ui-source branch's API docs plus Ketho's name lists into $TESTKIT_HOME/mirror/.
#   bash tools/fetch.sh <branch>    # live | classic | classic_era | classic_anniversary | forever
# Raw Blizzard files stay under $TESTKIT_HOME; never copy them into the repo.

set -euo pipefail
export MSYS_NO_PATHCONV=1

GETHE_URL="https://github.com/Gethe/wow-ui-source"
KETHO_REPO="Ketho/BlizzardInterfaceResources"
KETHO_FILES=(GlobalAPI Frames FrameXML WidgetAPI Events Templates)
DOCS_PATH="Interface/AddOns/Blizzard_APIDocumentationGenerated"
MIN_DOC_FILES=400

die() {
  echo "fetch.sh: $*" >&2
  exit 1
}

[[ $# -eq 1 && -n $1 ]] || die "usage: bash tools/fetch.sh <branch>"
branch=$1
kit_root=$(cd "$(dirname "$0")/.." && { pwd -W 2>/dev/null || pwd; }) # pwd -W: native path for Windows Lua
home=$(lua -e "package.path='$kit_root/?.lua;'..package.path; print(require('home').dir())" | tr -d '\r')
[[ -n $home ]] || die "could not resolve the testkit home"

gethe_dir="$home/mirror/gethe/$branch"
ketho_dir="$home/mirror/ketho/$branch"
git_() { git -c core.longpaths=true -C "$gethe_dir" "$@"; }

if [[ -d $gethe_dir/.git ]]; then
  echo "Updating $gethe_dir"
  git_ fetch --depth 1 origin "$branch"
  git_ reset --hard "origin/$branch"
else
  echo "Cloning $branch into $gethe_dir"
  mkdir -p "$(dirname "$gethe_dir")"
  git -c core.longpaths=true clone --depth 1 --filter=blob:none --sparse --branch "$branch" "$GETHE_URL" "$gethe_dir"
  git_ sparse-checkout set --no-cone "version.txt" "$DOCS_PATH/"
  echo "COMMIT" >>"$gethe_dir/.git/info/exclude" # keep the recorded commit out of `git status`
fi

[[ -z $(git_ status --porcelain) ]] || die "checkout of $branch is not clean: $(git_ status --porcelain | head -5)"
doc_count=$(find "$gethe_dir/$DOCS_PATH" -maxdepth 1 -name '*.lua' | wc -l)
((doc_count > MIN_DOC_FILES)) || die "$branch has only $doc_count doc files (expected > $MIN_DOC_FILES)"
git_ rev-parse HEAD >"$gethe_dir/COMMIT"

mkdir -p "$ketho_dir"
for f in "${KETHO_FILES[@]}"; do
  gh api "repos/$KETHO_REPO/contents/Resources/$f.lua?ref=$branch" -H "Accept: application/vnd.github.raw" >"$ketho_dir/$f.lua.tmp"
  mv "$ketho_dir/$f.lua.tmp" "$ketho_dir/$f.lua"
done

echo "OK $branch: $(head -c 40 "$gethe_dir/version.txt" | tr -d '\r\n'), $doc_count doc files, commit $(cat "$gethe_dir/COMMIT")"
