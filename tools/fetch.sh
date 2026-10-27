#!/usr/bin/env bash
# Mirror one wow-ui-source branch's API docs plus Ketho's name lists into $TESTKIT_HOME/mirror/.
#   bash tools/fetch.sh <branch>             # the Gethe and Ketho commits api/versions.lua records for its flavor
#   bash tools/fetch.sh <branch> --latest    # both branch tips, for a deliberate data bump
#   GETHE_COMMIT=<sha> KETHO_COMMIT=<sha> bash tools/fetch.sh <branch>    # full SHAs; each wins over both
# <branch>: live | classic | classic_era | classic_anniversary | forever
# Raw Blizzard files stay under $TESTKIT_HOME; never copy them into the repo.

set -euo pipefail
export MSYS_NO_PATHCONV=1

GETHE_URL="https://github.com/Gethe/wow-ui-source"
KETHO_REPO="Ketho/BlizzardInterfaceResources"
KETHO_FILES=(GlobalAPI Frames FrameXML WidgetAPI Events Templates)
DOCS_PATH="Interface/AddOns/Blizzard_APIDocumentationGenerated"
MIN_DOC_FILES=400
# Reference only, never loaded by the kit: Blizzard's menu code, read when checking the kit's menu fakes.
REFERENCE_PATHS=("Interface/AddOns/Blizzard_Menu/" "Interface/AddOns/Blizzard_SharedXML/*/UIDropDownMenu.lua" "Interface/AddOns/Blizzard_CombatLog/" "Interface/AddOns/Blizzard_NamePlates/")
USAGE="usage: bash tools/fetch.sh <branch> [--latest]"

die() {
  echo "fetch.sh: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 && -n $1 ]] || die "$USAGE"
branch=$1
latest=false
if [[ $# -eq 2 ]]; then
  [[ $2 == --latest ]] || die "$USAGE"
  latest=true
fi
kit_root=$(cd "$(dirname "$0")/.." && { pwd -W 2>/dev/null || pwd; }) # pwd -W: native path for Windows Lua
home=$(lua -e "package.path='$kit_root/?.lua;'..package.path; print(require('home').dir())" | tr -d '\r')
[[ -n $home ]] || die "could not resolve the testkit home"
# A POSIX-style TESTKIT_HOME (/c/...) reaches native git unconverted under MSYS_NO_PATHCONV, which reads it as C:\c\...
if command -v cygpath >/dev/null; then home=$(cygpath -m "$home"); fi

# "<mirrorCommit> <kethoCommit>" that api/versions.lua records for the flavor built from $branch ("-" when absent).
recorded_commits() {
  lua -e "package.path='$kit_root/?.lua;'..package.path
local Flavors, versions = require('tools.flavors'), dofile('$kit_root/api/versions.lua')
for _, name in ipairs(Flavors.list) do
  if Flavors.get(name).branch == '$branch' then
    local v = versions[name] or {}
    print((v.mirrorCommit or '-') .. ' ' .. (v.kethoCommit or '-'))
  end
end" | tr -d '\r'
}

if $latest; then
  gethe_default=$branch
  ketho_default=$branch
else
  recorded=$(recorded_commits)
  [[ -n $recorded ]] || die "no flavor in tools/flavors.lua builds from branch $branch"
  read -r gethe_default ketho_default <<<"$recorded"
fi
gethe_ref=${GETHE_COMMIT:-$gethe_default}
ketho_ref=${KETHO_COMMIT:-$ketho_default}
[[ $gethe_ref != - ]] || die "api/versions.lua records no Gethe commit for $branch; set GETHE_COMMIT=<sha> or pass --latest"
[[ $ketho_ref != - ]] || die "api/versions.lua records no Ketho commit for $branch; set KETHO_COMMIT=<sha> or pass --latest"

gethe_dir="$home/mirror/gethe/$branch"
ketho_dir="$home/mirror/ketho/$branch"
git_() { git -c core.longpaths=true -C "$gethe_dir" "$@"; }

if [[ ! -d $gethe_dir/.git ]]; then
  echo "Cloning $branch into $gethe_dir"
  mkdir -p "$(dirname "$gethe_dir")"
  git -c core.longpaths=true clone --depth 1 --filter=blob:none --sparse --no-checkout --branch "$branch" "$GETHE_URL" "$gethe_dir"
  echo "COMMIT" >>"$gethe_dir/.git/info/exclude" # keep the recorded commit out of `git status`
fi
echo "Checking out $gethe_ref in $gethe_dir"
# Each COMMIT is written last, so a run that fails partway leaves none rather than one naming the old files.
rm -f "$gethe_dir/COMMIT"
git_ fetch --depth 1 origin "$gethe_ref"
git_ reset --hard FETCH_HEAD
# Every fetch, so an existing mirror picks up paths added here later.
git_ sparse-checkout set --no-cone "/version.txt" "$DOCS_PATH/" "${REFERENCE_PATHS[@]}"

[[ -z $(git_ status --porcelain) ]] || die "checkout of $branch is not clean: $(git_ status --porcelain | head -5)"
doc_count=$(find "$gethe_dir/$DOCS_PATH" -maxdepth 1 -name '*.lua' | wc -l)
((doc_count > MIN_DOC_FILES)) || die "$branch has only $doc_count doc files (expected > $MIN_DOC_FILES)"
git_ rev-parse HEAD >"$gethe_dir/COMMIT"

mkdir -p "$ketho_dir"
rm -f "$ketho_dir/COMMIT"
# Resolve the ref once so every file comes from the same commit, and record it for api/versions.lua.
ketho_commit=$(gh api "repos/$KETHO_REPO/commits/$ketho_ref" --jq .sha | tr -d '\r')
[[ $ketho_commit =~ ^[0-9a-f]{40}$ ]] || die "could not resolve $KETHO_REPO $ketho_ref to a commit: $ketho_commit"
for f in "${KETHO_FILES[@]}"; do
  gh api "repos/$KETHO_REPO/contents/Resources/$f.lua?ref=$ketho_commit" -H "Accept: application/vnd.github.raw" >"$ketho_dir/$f.lua.tmp"
  mv "$ketho_dir/$f.lua.tmp" "$ketho_dir/$f.lua"
done
echo "$ketho_commit" >"$ketho_dir/COMMIT"

echo "OK $branch: $(head -c 40 "$gethe_dir/version.txt" | tr -d '\r\n'), $doc_count doc files, commit $(cat "$gethe_dir/COMMIT"), Ketho commit $ketho_commit"
