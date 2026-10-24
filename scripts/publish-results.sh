#!/usr/bin/env bash
# Copies ./out into the orphan `results` branch as <job>/<run>/ and <job>/latest/, then pushes.
# Usage: publish-results.sh <job>   (needs GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID)
set -euo pipefail
job="$1"
run="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
url="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
rm -rf res
if git clone -q --depth 1 --single-branch --branch results "$url" res 2>/dev/null; then :; else
  git init -q res
  git -C res checkout -q --orphan results
  git -C res remote add origin "$url"
fi
mkdir -p "res/$job/$run"
cp -R out/. "res/$job/$run/"
rm -rf "res/$job/latest"
cp -R "res/$job/$run" "res/$job/latest"
cd res
git config user.name "ios-builder"
git config user.email "ios-builder@users.noreply.github.com"
git add -A
git commit -q -m "$job $run: $(cat "$job/$run/STATUS" 2>/dev/null || echo done)"
for i in 1 2 3 4 5; do
  if git push -q origin HEAD:results; then exit 0; fi
  git pull -q --rebase origin results || true
  sleep $((i * 3))
done
exit 1
