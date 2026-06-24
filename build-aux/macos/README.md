# macOS Build & Packaging

## One-time setup

**Developer ID certificate**

Open Xcode → Settings → Accounts → Manage Certificates and ensure you have a
**Developer ID Application** certificate. If not, click **+** and create one.
Accept any pending PLA at developer.apple.com first if Xcode shows a warning.

**Notarytool credentials**

Create an app-specific password at appleid.apple.com, then store it in your
Keychain:

```sh
xcrun notarytool store-credentials "notarytool-blackbox" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Your Team ID is at developer.apple.com/account next to your name.

**Add SIGN_IDENTITY to your shell profile**

```sh
security find-identity -v -p codesigning
# Copy the "Developer ID Application: ..." string, then:
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Add that export to `~/.zshrc` so you don't need to set it each time.

**Install packaging dependencies**

```sh
brew install create-dmg
# For --publish:
brew install glab && glab auth login
```

## Running locally

```sh
meson setup builddir
meson compile -C builddir
ninja -C builddir run
```

## Building a release DMG

```sh
./build-aux/macos/package.sh
```

This builds the app, codesigns it with your Developer ID certificate,
notarizes it with Apple, staples the ticket, and produces
`BlackBox-<version>.dmg` in the project root.

Use `--skip-notarize` to skip codesigning and notarization for local testing:

```sh
./build-aux/macos/package.sh --skip-notarize
```

The build scratch directory is `build-pkg/` (gitignored).

## Publishing a release

1. Tag the release and push:

   ```sh
   git tag v<version> && git push origin v<version>
   ```

2. Upload the DMG to the GitLab Package Registry:

   ```sh
   ./build-aux/macos/package.sh --publish
   ```

   This builds the DMG (with notarization) and uploads it. The direct URL is
   printed at the end.

3. Create the release on the
   [GitLab releases page](https://gitlab.gnome.org/raggesilver/blackbox/-/releases)
   and paste the DMG URL as a package asset link.

## How the .app bundle works

The bundle is fully self-contained — no Homebrew installation required.

- `Contents/MacOS/BlackBox` — launcher shell script that sets up the
  environment (GLib schemas, XDG data dirs, icon theme, pixbuf loaders) and
  `exec`s into the real binary
- `Contents/MacOS/blackbox-terminal` — the compiled app binary
- `Contents/Frameworks/` — all non-system dylibs, with load paths rewritten to
  `@executable_path/../Frameworks/`
- `Contents/Resources/` — GSettings schemas, icons, color schemes, GDK-Pixbuf
  loaders, translations
