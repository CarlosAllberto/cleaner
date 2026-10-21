#!/usr/bin/env bash
# Assina (Developer ID), notariza e grampeia o Cleaner. Uso: scripts/release.sh [--dry-run]
set -euo pipefail

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

missing=()
for v in DEVELOPER_ID_APP TEAM_ID NOTARY_PROFILE; do
  [[ -n "${!v:-}" ]] || missing+=("$v")
done
if (( ${#missing[@]} )); then
  echo "Variáveis ausentes: ${missing[*]}" >&2
  exit 1
fi

cd "$(dirname "$0")/.."
OUT=.build/release
APP="$OUT/Build/Products/Release/Cleaner.app"
ZIP="$OUT/Cleaner.zip"

run() {
  echo "+ $*"
  (( DRY )) || "$@"
}

run bash -c 'cd App && xcodegen generate'
run xcodebuild -project App/Cleaner.xcodeproj -scheme Cleaner -configuration Release \
  -derivedDataPath "$OUT" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APP" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" build
run codesign --verify --deep --strict --verbose=2 "$APP"
run ditto -c -k --keepParent "$APP" "$ZIP"
run xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
run xcrun stapler staple "$APP"
run ditto -c -k --keepParent "$APP" "$ZIP" # zip final já com o ticket
run spctl -a -vv "$APP"
run xcrun stapler validate "$APP"

(( DRY )) && echo "dry-run: nada foi assinado." || echo "Pronto: $ZIP"
