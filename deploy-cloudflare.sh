#!/bin/sh
# Publish the app shell to Cloudflare Pages.
#
# GitHub Pages serves this repo straight from the root, so the shippable files
# cannot be moved into a public/ directory without breaking that. Instead this
# stages a copy containing only what the app actually needs and hands that
# directory to Wrangler -- node_modules/, .git/, the audit markdown and the
# test bundle never leave the Mac.
#
# Usage: ./deploy-cloudflare.sh [--dry-run]
set -eu

PROJECT=scorecard-pwa
ROOT=$(cd "$(dirname "$0")" && pwd)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/scorecard-deploy.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# The app shell, its assets, and the worker that caches them. Keep this in step
# with the SHELL/OPTIONAL arrays in sw.js -- the check below enforces that.
FILES="index.html styles.css app.js ui.js boot.js manifest.json sw.js
       icon-180.png icon-192.png icon-512.png field.png"

for f in $FILES; do
  [ -f "$ROOT/$f" ] || { echo "missing: $f" >&2; exit 1; }
  cp "$ROOT/$f" "$STAGE/$f"
done
mkdir -p "$STAGE/fonts"
cp "$ROOT"/fonts/*.woff2 "$STAGE/fonts/"

# sw.js installs its cache with addAll(), which is all-or-nothing: one 404 in
# the precache list kills the whole install and leaves an installed app with a
# worker in charge and nothing to fall back on. Catch that here, not on the
# iPad in a dugout with no signal.
missing=$(grep -oE "'[A-Za-z0-9_./-]+\.(html|css|js|json|png|woff2)'" "$ROOT/sw.js" \
          | tr -d "'" | sort -u \
          | while read -r asset; do [ -f "$STAGE/$asset" ] || echo "$asset"; done)
if [ -n "$missing" ]; then
  echo "sw.js precaches files that are not being deployed:" >&2
  echo "$missing" >&2
  exit 1
fi

echo "Staging $(find "$STAGE" -type f | wc -l | tr -d ' ') files, $(du -sh "$STAGE" | cut -f1)"

if [ "${1:-}" = "--dry-run" ]; then
  (cd "$STAGE" && find . -type f | sed 's|^\./|  |' | sort)
  exit 0
fi

"$ROOT/node_modules/.bin/wrangler" pages deploy "$STAGE" \
  --project-name "$PROJECT" \
  --branch main \
  --commit-hash "$(git -C "$ROOT" rev-parse HEAD)" \
  --commit-dirty="$([ -z "$(git -C "$ROOT" status --porcelain)" ] && echo false || echo true)"
