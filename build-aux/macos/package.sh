#!/usr/bin/env bash
#
# Builds, codesigns, notarizes, and packages Black Box as a macOS DMG.
# Pass --publish to also create a GitHub release and update the Homebrew tap.
# Pass --skip-notarize to skip notarization (useful for local testing).
#
# Required env vars:
#   SIGN_IDENTITY      — e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARYTOOL_PROFILE — keychain profile name (default: notarytool-blackbox)
#
# Prerequisites: create-dmg, gh (brew install create-dmg gh)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-notarytool-blackbox}"
TAP_REPO="raggesilver/homebrew-tap"
CASK_NAME="blackbox-terminal"

PUBLISH=0
SKIP_NOTARIZE=0
for arg in "$@"; do
  [[ "$arg" == "--publish" ]] && PUBLISH=1
  [[ "$arg" == "--skip-notarize" ]] && SKIP_NOTARIZE=1
done

if [[ $PUBLISH -eq 1 && $SKIP_NOTARIZE -eq 1 ]]; then
  echo "error: --skip-notarize cannot be used with --publish"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERSION="$(grep "version:" "$PROJECT_ROOT/meson.build" | head -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")"

BUILD_DIR="$PROJECT_ROOT/build-pkg"
MESON_DIR="$BUILD_DIR/meson"
STAGING_DIR="$BUILD_DIR/staging"
APP_BUNDLE="$STAGING_DIR/BlackBox.app"
DMG_STAGE="$BUILD_DIR/dmg-stage"
DMG_OUT="$PROJECT_ROOT/BlackBox-$VERSION.dmg"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

check_prereqs() {
  local ok=1

  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: SIGN_IDENTITY is not set."
    echo "       Run: security find-identity -v -p codesigning"
    echo "       Then: export SIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\""
    ok=0
  fi

  if ! command -v create-dmg &>/dev/null; then
    echo "error: create-dmg not found — brew install create-dmg"
    ok=0
  fi

  if ! command -v meson &>/dev/null; then
    echo "error: meson not found — brew install meson"
    ok=0
  fi

  if [[ $PUBLISH -eq 1 ]] && ! command -v gh &>/dev/null; then
    echo "error: gh not found — brew install gh"
    ok=0
  fi

  if [[ $PUBLISH -eq 1 ]]; then
    if ! gh release view "v$VERSION" --repo raggesilver/blackbox &>/dev/null 2>&1; then
      if ! gh api "repos/raggesilver/blackbox/git/ref/tags/v$VERSION" &>/dev/null 2>&1; then
        echo "error: tag v$VERSION not found on GitHub."
        echo "       Push the tag from GitLab first and wait for the mirror to sync:"
        echo "         git push origin v$VERSION"
        ok=0
      fi
    else
      echo "error: GitHub release v$VERSION already exists."
      ok=0
    fi
  fi

  [[ $ok -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

step() { echo; echo "==> $*"; }

build() {
  step "Building ($VERSION)"
  cd "$PROJECT_ROOT"

  local extra_flags=()
  [[ -d "$MESON_DIR" ]] && extra_flags+=(--wipe)

  meson setup "$MESON_DIR" --prefix="$STAGING_DIR" --buildtype=release "${extra_flags[@]}"

  meson compile -C "$MESON_DIR"
  meson install -C "$MESON_DIR"
}

codesign_app() {
  step "Codesigning"
  codesign \
    --deep \
    --force \
    --options runtime \
    --sign "$SIGN_IDENTITY" \
    --timestamp \
    "$APP_BUNDLE"

  echo "Verifying signature..."
  codesign --verify --deep --strict "$APP_BUNDLE"
  spctl --assess --type execute "$APP_BUNDLE" 2>/dev/null || true
}

notarize() {
  step "Notarizing"
  local zip="$BUILD_DIR/BlackBox-notarize.zip"

  rm -f "$zip"
  ditto -c -k --keepParent "$APP_BUNDLE" "$zip"

  xcrun notarytool submit "$zip" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

  step "Stapling notarization ticket"
  xcrun stapler staple "$APP_BUNDLE"
}

make_dmg() {
  step "Creating DMG"
  rm -rf "$DMG_STAGE"
  mkdir -p "$DMG_STAGE"
  cp -r "$APP_BUNDLE" "$DMG_STAGE/"

  rm -f "$DMG_OUT"

  create-dmg \
    --volname "Black Box" \
    --window-size 540 380 \
    --icon-size 128 \
    --icon "BlackBox.app" 140 190 \
    --app-drop-link 400 190 \
    --hide-extension "BlackBox.app" \
    "$DMG_OUT" \
    "$DMG_STAGE"

  DMG_SHA256="$(shasum -a 256 "$DMG_OUT" | awk '{print $1}')"
  echo
  echo "DMG:    $DMG_OUT"
  echo "SHA256: $DMG_SHA256"
}

publish() {
  step "Creating GitHub release (v$VERSION)"
  gh release create "v$VERSION" "$DMG_OUT" \
    --repo "raggesilver/blackbox" \
    --title "v$VERSION" \
    --latest

  step "Updating Homebrew tap ($TAP_REPO)"
  local tap_dir="$BUILD_DIR/homebrew-tap"
  local cask_file="$tap_dir/Casks/$CASK_NAME.rb"

  if [[ -d "$tap_dir" ]]; then
    git -C "$tap_dir" pull --rebase
  else
    gh repo clone "$TAP_REPO" "$tap_dir"
  fi

  sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$cask_file"
  sed -i '' "s/sha256 \".*\"/sha256 \"$DMG_SHA256\"/" "$cask_file"

  git -C "$tap_dir" add "Casks/$CASK_NAME.rb"
  git -C "$tap_dir" commit -m "Update $CASK_NAME to $VERSION"
  git -C "$tap_dir" push
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_prereqs

build
codesign_app
[[ $SKIP_NOTARIZE -eq 0 ]] && notarize
make_dmg

if [[ $PUBLISH -eq 1 ]]; then
  publish
fi
