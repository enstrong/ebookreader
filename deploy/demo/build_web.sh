#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
flutter_bin="${FLUTTER:-flutter}"
stage="$(mktemp -d "${TMPDIR:-/tmp}/ebookreader-demo.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
for source in lib web pubspec.yaml pubspec.lock analysis_options.yaml; do
  cp -R "$repo_root/$source" "$stage/$source"
done
# Git does not retain the empty covers directory used by the native app.
if [[ -d "$repo_root/assets" ]]; then
  cp -R "$repo_root/assets" "$stage/assets"
fi
mkdir -p "$stage/assets/covers"
# The native app's .env can contain credentials; it never enters the public build.
printf '# Public demo uses same-origin API requests.\n' > "$stage/.env"
cd "$stage"
"$flutter_bin" pub get --offline
"$flutter_bin" build web --release --dart-define=DEMO_MODE=true --pwa-strategy=none
mkdir -p "$repo_root/build/web"
rsync -a --delete "$stage/build/web/" "$repo_root/build/web/"
rm -f "$repo_root/build/web/assets/.env"
