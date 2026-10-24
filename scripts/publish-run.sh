#!/usr/bin/env bash
# Publishes $OUT for run.yml: small files to `results/<tag>/`, files over 50 MB to `builds/<tag>/`.
# `builds` is force-pushed as one fresh commit: it only ever holds the latest large artifacts.
set -euo pipefail
tag="$1"
url="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
big=$(mktemp -d)
find "$OUT" -type f -size +50M -exec mv {} "$big/" \;

push_dir() { # <branch> <srcdir> <single-commit?>
  local branch="$1" from="$2" single="$3"
  rm -rf res
  if [ "$single" = no ] && git clone -q --depth 1 --single-branch --branch "$branch" "$url" res 2>/dev/null; then :; else
    git init -q res; git -C res checkout -q --orphan "$branch"; git -C res remote add origin "$url"
  fi
  rm -rf "res/$tag"; mkdir -p "res/$tag"; cp -R "$from/." "res/$tag/"
  git -C res config user.name ios-builder; git -C res config user.email ios-builder@users.noreply.github.com
  git -C res add -A
  git -C res commit -q -m "$tag: $(cat "$OUT/STATUS" 2>/dev/null || echo done)" || return 0
  for i in 1 2 3 4 5; do
    if [ "$single" = yes ]; then git -C res push -q -f origin "HEAD:$branch" && return 0
    else git -C res push -q origin "HEAD:$branch" && return 0; git -C res pull -q --rebase origin "$branch" || true; fi
    sleep $((i * 3))
  done
  return 1
}

push_dir results "$OUT" no
if [ -n "$(ls -A "$big")" ]; then push_dir builds "$big" yes; fi
