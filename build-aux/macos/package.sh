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
BREW="$(brew --prefix)"

BUILD_DIR="$PROJECT_ROOT/build-pkg"
MESON_DIR="$BUILD_DIR/meson"
STAGING_DIR="$BUILD_DIR/staging"
APP_BUNDLE="$STAGING_DIR/BlackBox.app"
BUNDLE_CONTENTS="$APP_BUNDLE/Contents"
BUNDLE_MACOS="$BUNDLE_CONTENTS/MacOS"
BUNDLE_RESOURCES="$BUNDLE_CONTENTS/Resources"
BUNDLE_FRAMEWORKS="$BUNDLE_CONTENTS/Frameworks"
DMG_STAGE="$BUILD_DIR/dmg-stage"
DMG_OUT="$PROJECT_ROOT/BlackBox-$VERSION.dmg"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

check_prereqs() {
  local ok=1

  if [[ $SKIP_NOTARIZE -eq 0 && -z "$SIGN_IDENTITY" ]]; then
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

# ---------------------------------------------------------------------------
# Resolve the on-disk path for a single dylib reference, or print nothing.
# Usage: resolve_lib <ref> <binary-that-referenced-it>
# ---------------------------------------------------------------------------
resolve_lib() {
  local ref="$1"
  local binary="$2"

  if [[ "$ref" == @rpath/* ]]; then
    local name="${ref#@rpath/}"
    while IFS= read -r rpath; do
      rpath="${rpath%% (offset*}"
      rpath="${rpath#*path }"
      rpath="${rpath//\$\{HOMEBREW_PREFIX\}/$BREW}"
      [ -f "$rpath/$name" ] && { echo "$rpath/$name"; return; }
    done < <(otool -l "$binary" 2>/dev/null | grep -A2 LC_RPATH | grep '^\s*path ')
    # Fallback: scan Homebrew
    find "$BREW/lib" "$BREW/opt" -maxdepth 4 -name "$name" 2>/dev/null | head -1
  elif [[ "$ref" == @loader_path/* ]]; then
    local name="${ref#@loader_path/}"
    local dir; dir="$(dirname "$binary")"
    [ -f "$dir/$name" ] && { echo "$dir/$name"; return; }
  elif [ -f "$ref" ]; then
    echo "$ref"
  fi
}

# ---------------------------------------------------------------------------
# Recursively collect non-system dylib dependencies into a temp file.
# Each line is: <basename><TAB><resolved-path>
# ---------------------------------------------------------------------------
_COLLECTED=""

collect_libs() {
  local binary="$1"
  while IFS= read -r ref; do
    [[ "$ref" == /usr/lib/*         ]] && continue
    [[ "$ref" == /System/Library/*  ]] && continue
    [[ "$ref" == @executable_path/* ]] && continue

    # Use the reference name (e.g. libicuuc.78.dylib) as the bundle filename,
    # NOT the realpath basename (e.g. libicuuc.78.3.dylib). References inside
    # other dylibs use the symlink name, so fix_refs must find it under that name.
    local ref_name
    if [[ "$ref" == @rpath/* ]]; then
      ref_name="${ref#@rpath/}"
    elif [[ "$ref" == @loader_path/* ]]; then
      ref_name="${ref#@loader_path/}"
    else
      ref_name="$(basename "$ref")"
    fi

    grep -qF "$ref_name" "$_COLLECTED" && continue

    local src
    src="$(resolve_lib "$ref" "$binary")"
    [ -z "$src" ] && { echo "  warning: cannot resolve $ref — skipping" >&2; continue; }

    # Resolve symlinks to get the actual file to copy from.
    src="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$src")"

    printf '%s\t%s\n' "$ref_name" "$src" >> "$_COLLECTED"

    collect_libs "$src"
  done < <(otool -L "$binary" 2>/dev/null | tail -n +2 | awk '{print $1}')
}

# ---------------------------------------------------------------------------
# Rewrite dylib references in a binary to point into ../Frameworks/.
# ---------------------------------------------------------------------------
fix_refs() {
  local binary="$1"
  while IFS= read -r ref; do
    [[ "$ref" == /usr/lib/*         ]] && continue
    [[ "$ref" == /System/Library/*  ]] && continue
    [[ "$ref" == @executable_path/* ]] && continue

    local name
    if [[ "$ref" == @rpath/* ]]; then
      name="${ref#@rpath/}"
    elif [[ "$ref" == @loader_path/* ]]; then
      name="${ref#@loader_path/}"
    else
      name="$(basename "$ref")"
    fi

    [ -f "$BUNDLE_FRAMEWORKS/$name" ] || continue
    install_name_tool -change "$ref" "@executable_path/../Frameworks/$name" "$binary" 2>/dev/null || true
  done < <(otool -L "$binary" 2>/dev/null | tail -n +2 | awk '{print $1}')
}

# ---------------------------------------------------------------------------
# Copy the real terminal binary into the bundle.
# ---------------------------------------------------------------------------
bundle_binary() {
  step "Copying blackbox-terminal into bundle"
  cp "$STAGING_DIR/bin/blackbox-terminal" "$BUNDLE_MACOS/blackbox-terminal"
  chmod 755 "$BUNDLE_MACOS/blackbox-terminal"
}

# ---------------------------------------------------------------------------
# Collect all non-system dylibs, copy to Frameworks/, and rewrite load paths.
# ---------------------------------------------------------------------------
bundle_dylibs() {
  step "Bundling dylibs"
  rm -rf "$BUNDLE_FRAMEWORKS"
  mkdir -p "$BUNDLE_FRAMEWORKS"

  _COLLECTED="$(mktemp)"
  collect_libs "$BUNDLE_MACOS/blackbox-terminal"

  local count; count="$(wc -l < "$_COLLECTED" | tr -d ' ')"
  echo "Copying $count dylibs to Frameworks/"

  while IFS=$'\t' read -r name src; do
    cp "$src" "$BUNDLE_FRAMEWORKS/$name"
    chmod 755 "$BUNDLE_FRAMEWORKS/$name"
    install_name_tool -id "@executable_path/../Frameworks/$name" "$BUNDLE_FRAMEWORKS/$name"
  done < "$_COLLECTED"
  rm "$_COLLECTED"
  _COLLECTED=""

  echo "Fixing dylib references..."
  fix_refs "$BUNDLE_MACOS/blackbox-terminal"
  for lib in "$BUNDLE_FRAMEWORKS/"*.dylib; do
    [ -f "$lib" ] && fix_refs "$lib"
  done
}

# ---------------------------------------------------------------------------
# Bundle GSettings schemas, color schemes, and icons into Resources/share/.
# ---------------------------------------------------------------------------
bundle_resources() {
  step "Bundling resources"

  # GSettings schemas: merge the app's schemas with GTK/Adwaita's from Homebrew,
  # then compile. Both sets are required for settings lookups to succeed.
  local schema_dir="$BUNDLE_RESOURCES/share/glib-2.0/schemas"
  mkdir -p "$schema_dir"
  cp "$STAGING_DIR/share/glib-2.0/schemas/"*.xml "$schema_dir/" 2>/dev/null || true
  cp "$BREW/share/glib-2.0/schemas/"*.xml         "$schema_dir/" 2>/dev/null || true
  glib-compile-schemas "$schema_dir/"

  # Color schemes — the app searches XDG_DATA_DIRS (set by the launcher).
  local schemes_dir="$BUNDLE_RESOURCES/share/blackbox/schemes"
  mkdir -p "$schemes_dir"
  cp -r "$STAGING_DIR/share/blackbox/schemes/." "$schemes_dir/"

  # Icons — start with Homebrew's theme base, then overlay the app's own icons
  # from the staging dir (app icon, action symbolics, etc.).
  # Regenerate icon-theme.cache for both themes; without it GTK cannot find icons.
  mkdir -p "$BUNDLE_RESOURCES/share/icons"
  [ -d "$BREW/share/icons/hicolor" ] && \
    cp -r "$BREW/share/icons/hicolor" "$BUNDLE_RESOURCES/share/icons/"
  [ -d "$BREW/share/icons/Adwaita" ] && \
    cp -r "$BREW/share/icons/Adwaita" "$BUNDLE_RESOURCES/share/icons/"
  [ -d "$STAGING_DIR/share/icons" ] && \
    cp -r "$STAGING_DIR/share/icons/." "$BUNDLE_RESOURCES/share/icons/"
  gtk-update-icon-cache -f -t "$BUNDLE_RESOURCES/share/icons/hicolor" 2>/dev/null || true
  gtk-update-icon-cache -f -t "$BUNDLE_RESOURCES/share/icons/Adwaita"  2>/dev/null || true

  # Locale files (best-effort; the app falls back to English if absent).
  if [ -d "$STAGING_DIR/share/locale" ]; then
    mkdir -p "$BUNDLE_RESOURCES/share/locale"
    cp -r "$STAGING_DIR/share/locale/." "$BUNDLE_RESOURCES/share/locale/"
  fi
}

codesign_app() {
  step "Codesigning"

  # Sign nested dylibs and frameworks before signing the bundle.
  # --deep is deprecated and can cause notarization rejection.
  if [[ -d "$APP_BUNDLE/Contents/Frameworks" ]]; then
    find "$APP_BUNDLE/Contents/Frameworks" \
      \( -name "*.framework" -o -name "*.dylib" \) | while read -r item; do
      codesign --force --options runtime --sign "$SIGN_IDENTITY" --timestamp "$item"
    done
  fi

  if [[ -d "$APP_BUNDLE/Contents/MacOS" ]]; then
    find "$APP_BUNDLE/Contents/MacOS" -type f | while read -r item; do
      codesign --force --options runtime --sign "$SIGN_IDENTITY" --timestamp "$item"
    done
  fi

  codesign \
    --force \
    --options runtime \
    --sign "$SIGN_IDENTITY" \
    --timestamp \
    "$APP_BUNDLE"

  echo "Verifying signature..."
  codesign --verify --deep --strict "$APP_BUNDLE"
  spctl --assess --type execute "$APP_BUNDLE" 2>/dev/null || true
}

codesign_dmg() {
  step "Codesigning DMG"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_OUT"

  step "Notarizing DMG"
  xcrun notarytool submit "$DMG_OUT" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

  step "Stapling notarization ticket to DMG"
  xcrun stapler staple "$DMG_OUT"
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

  grep -q 'version "' "$cask_file" || { echo "error: could not find version field in $cask_file"; exit 1; }
  grep -q 'sha256 "' "$cask_file" || { echo "error: could not find sha256 field in $cask_file"; exit 1; }
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
bundle_binary
bundle_dylibs
bundle_resources
[[ $SKIP_NOTARIZE -eq 0 ]] && codesign_app
[[ $SKIP_NOTARIZE -eq 0 ]] && notarize
make_dmg
[[ $SKIP_NOTARIZE -eq 0 ]] && codesign_dmg

if [[ $PUBLISH -eq 1 ]]; then
  publish
fi
