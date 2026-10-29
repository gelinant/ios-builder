#!/usr/bin/env bash
# Publishes $OUT for run.yml: small files to `results/<tag>/`, files over 8 MB to `builds/<tag>/`.
# `builds` is force-pushed as one fresh commit: it only ever holds the latest large artifacts.
set -euo pipefail
tag="$1"
url="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
big=$(mktemp -d)
# 8 MB, not 50: a 24 MB IPA stayed on `results` for every archived run, and the branch grew to
# several gigabytes, which filled the coordinator's disk with 10 GB clones.
find "$OUT" -type f -size +8M -exec mv {} "$big/" \;

push_dir() { # <branch> <srcdir> <single-commit?>
  local branch="$1" from="$2" single="$3"
  rm -rf res
  if [ "$single" = no ] && git clone -q --depth 1 --single-branch --branch "$branch" "$url" res 2>/dev/null; then :; else
    git init -q res; git -C res checkout -q --orphan "$branch"; git -C res remote add origin "$url"
  fi
  rm -rf "res/$tag"; mkdir -p "res/$tag"; cp -R "$from/." "res/$tag/"
  # Keep the branch small: clones on the runner download this tree, and every run used to stay
  # forever. Keep the six most recent directories of this tag (names start with the tag and sort
  # chronologically), which covers the current and previous builds.
  if [ "$branch" = results ]; then
    # A new tag has no directory yet: `ls` failing here must not abort the publish.
    old="$(ls -1d res/"$tag"-* 2>/dev/null | head -n -6 || true)"
    [ -z "$old" ] || rm -rf $old
    # Keep the twelve most recent runs overall, newest first by mtime. Per-tag pruning alone let
    # dozens of distinct lots accumulate and made every shallow clone gigabytes wide.
    old="$(ls -1dt res/*/ 2>/dev/null | tail -n +13 || true)"
    [ -z "$old" ] || rm -rf $old
  fi
  git -C res config user.name ios-builder; git -C res config user.email ios-builder@users.noreply.github.com
  git -C res add -A
  git -C res commit -q -m "$tag: $(cat "$OUT/STATUS" 2>/dev/null || echo done)"     || { echo "nothing to publish for $tag" >&2; return 0; }
  for i in 1 2 3 4 5; do
    if [ "$single" = yes ]; then
      if git -C res push -q -f origin "HEAD:$branch"; then return 0; fi
    else
      if git -C res push -q origin "HEAD:$branch"; then return 0; fi
      # Another run published first, or the branch was pruned and rewritten. Rebase the new tree
      # onto whatever is on the server now instead of failing on a shallow pull --rebase.
      if git -C res fetch -q --depth 1 origin "$branch" 2>/dev/null; then
        git -C res reset -q --soft FETCH_HEAD 2>/dev/null || true
        git -C res add -A || true
        git -C res commit -q -m "$tag: $(cat "$OUT/STATUS" 2>/dev/null || echo done)" || true
      fi
    fi
    sleep $((i * 3))
  done
  echo "publish failed for $tag after 5 attempts" >&2
  return 1
}

push_dir results "$OUT" no
if [ -n "$(ls -A "$big")" ]; then push_dir builds "$big" yes; fi
