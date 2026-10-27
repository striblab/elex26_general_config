#!/bin/bash
# Election-night results update, end to end:
#
#   1. Runs the R pipeline (scraper/mapperscripter.Rmd) against the SoS feed
#   2. Checks every race's GeoJSON: present, fresh, simplified, valid
#   3. Commits and pushes store/ in this repo (GitHub Pages data links)
#   4. Copies the data into the map app and refreshes its directory.json
#   5. Runs the map app's precision and directory-stats scripts, then builds
#   6. Deploys the map app to production and confirms S3 took the upload
#
# Stops at the first failure. Safe to rerun: every pass overwrites everything
# with the SoS feed's latest numbers.
#
# Usage:
#   ./update-results.sh               full run
#   ./update-results.sh --no-push     skip step 3
#   ./update-results.sh --no-deploy   skip step 6
#
# The map app is expected at ~/elex26_general; set MAP_DIR to use another
# folder. Its folder name must stay elex26_general, since the deploy script
# names the S3 path after it.

set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"
MAP_DIR="${MAP_DIR:-$HOME/elex26_general}"
S3_BUCKET="static.startribune.com"
S3_PREFIX="news/projects/all/$(basename "$MAP_DIR")"
# Simplified race files run ~5-8 MB; unsimplified ones ~33 MB.
MAX_GEOJSON_MB=15

PUSH=1
DEPLOY=1
for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    --no-deploy) DEPLOY=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nFAILED: %s\n' "$1" >&2; exit 1; }

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
# Marks the start of this run, so stale files from an earlier one can't pass.
touch "$WORK_DIR/started"

step "Checking tools and folders"
for cmd in Rscript mapshaper node npm git; do
  command -v "$cmd" >/dev/null || fail "$cmd isn't on PATH. (mapshaper: npm install -g mapshaper)"
done
[ -d "$MAP_DIR/scripts" ] || fail "No map app at $MAP_DIR (set MAP_DIR)"
if [ "$DEPLOY" = 1 ]; then
  command -v aws >/dev/null || fail "The AWS CLI isn't installed"
  aws sts get-caller-identity --profile default >/dev/null || fail "No working AWS credentials in the default profile"
fi
if [ "$PUSH" = 1 ]; then
  git -C "$CONFIG_DIR" pull --ff-only --quiet || fail "Couldn't fast-forward $CONFIG_DIR from GitHub"
fi

# Each race's data file, from the configurator's race list.
RACE_FILES="$(node -e '
  const races = require(process.argv[1]).races;
  console.log(races.map((r) => r.precincts.split("/").pop()).join("\n"));
' "$CONFIG_DIR/src/directory.json")"

step "Running the R pipeline (a few minutes)"
cd "$CONFIG_DIR/scraper"
Rscript -e "knitr::purl('mapperscripter.Rmd', output='$WORK_DIR/run.R', quiet=TRUE)" >/dev/null
Rscript "$WORK_DIR/run.R" >"$WORK_DIR/pipeline.log" 2>&1 || {
  tail -20 "$WORK_DIR/pipeline.log" >&2
  fail "The R pipeline stopped (last lines above)"
}

step "Checking each race's GeoJSON"
while read -r file; do
  path="$CONFIG_DIR/store/$file"
  [ -f "$path" ] || fail "$file is missing from store/"
  [ "$path" -nt "$WORK_DIR/started" ] || fail "$file wasn't rewritten by this run"
  mb=$(( $(wc -c <"$path") / 1000000 ))
  [ "$mb" -le "$MAX_GEOJSON_MB" ] || fail "$file is ${mb} MB, so it wasn't simplified (is mapshaper on PATH?)"
  node -e '
    const g = require(process.argv[1]);
    const n = g.features.filter((f) => f.properties.total_votes > 0).length;
    console.log(`    ${process.argv[2].padEnd(28)} ${g.features.length} precincts, ${n} with votes`);
    if (n === 0) console.log("    ^ WARNING: no votes yet in this race");
  ' "$path" "$file" || fail "$file isn't valid GeoJSON"
done <<<"$RACE_FILES"

if [ "$PUSH" = 1 ]; then
  step "Committing and pushing store/"
  cd "$CONFIG_DIR"
  git add store
  if git diff --cached --quiet; then
    echo "    No data changes since the last update"
  else
    git commit --quiet -m "Results update $(date '+%Y-%m-%d %H:%M')"
  fi
  git push --quiet
else
  step "Skipping push (--no-push)"
fi

step "Copying the data into the map app"
cp "$CONFIG_DIR"/store/*-results-geo.json "$CONFIG_DIR"/store/*-results-geo.csv "$MAP_DIR/public/data/"
# Rebuild the map's directory.json from the configurator's race list, so new
# or changed races carry over; build-directory-stats.mjs then adds the stats.
node -e '
  const fs = require("fs");
  const races = require(process.argv[1]).races.map((r) => ({
    index: r.index, office: r.office, district: r.district,
    latitude: r.latitude, longitude: r.longitude, overlay: r.overlay, name: r.name,
    precincts: r.precincts.split("/").pop()
  }));
  fs.writeFileSync(process.argv[2], JSON.stringify({ races }));
' "$CONFIG_DIR/src/directory.json" "$MAP_DIR/public/data/directory.json"

step "Preparing and building the map app"
cd "$MAP_DIR"
node scripts/truncate-geometry-precision.mjs >/dev/null
node scripts/build-directory-stats.mjs >/dev/null
npm run build >"$WORK_DIR/build.log" 2>&1 || {
  tail -20 "$WORK_DIR/build.log" >&2
  fail "The map app build failed (last lines above)"
}

if [ "$DEPLOY" = 1 ]; then
  step "Deploying to s3://$S3_BUCKET/$S3_PREFIX"
  # strib-deploy.sh prints "Deploy complete!" even when every upload fails,
  # so its log is checked for AWS errors instead of trusting its exit code.
  npm run deploy-production 2>&1 | tee "$WORK_DIR/deploy.log"
  if grep -Eq 'fatal error|upload failed|An error occurred|AccessDenied' "$WORK_DIR/deploy.log"; then
    fail "The deploy hit AWS errors (see the log above); the live map may be partly updated"
  fi

  step "Confirming S3 has the new data"
  for key in index.html data/directory.json; do
    modified=$(aws s3api head-object --profile default --bucket "$S3_BUCKET" \
      --key "$S3_PREFIX/$key" --query LastModified --output text) ||
      fail "Couldn't read $key back from S3"
    node -e '
      const modified = new Date(process.argv[1]);
      const started = new Date(Number(process.argv[2]) * 1000);
      if (modified < started) process.exit(1);
    ' "$modified" "$(stat -f %m "$WORK_DIR/started")" ||
      fail "$key on S3 is older than this run ($modified)"
    echo "    $key updated $modified"
  done
else
  step "Skipping deploy (--no-deploy)"
fi

step "Done"
