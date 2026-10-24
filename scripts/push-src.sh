#!/usr/bin/env bash
# Pushes a snapshot of a Vela checkout to this builder as branch src/<name>, with .github/
# removed so none of the upstream workflows run here.
# Usage: scripts/push-src.sh <vela checkout> <name> [ref]
set -euo pipefail
repo="$1"; name="$2"; ref="${3:-HEAD}"
builder="git@github.com:gelinant/ios-builder.git"
cd "$repo"
sha=$(git rev-parse "$ref")
idx=$(mktemp)
GIT_INDEX_FILE="$idx" git read-tree "$sha"
GIT_INDEX_FILE="$idx" git rm -r -q --cached --ignore-unmatch .github
tree=$(GIT_INDEX_FILE="$idx" git write-tree)
rm -f "$idx"
commit=$(git commit-tree "$tree" -m "src: $(git log -1 --format='%h %s' "$sha")")
git push -f "$builder" "$commit:refs/heads/src/$name"
echo "src/$name -> $commit (from $sha)"
