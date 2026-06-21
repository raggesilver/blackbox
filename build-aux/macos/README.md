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
brew install create-dmg gh
```

## Running locally

```sh
meson setup builddir
meson compile -C builddir
meson run -C builddir run
```

## Building a release DMG

```sh
./build-aux/macos/package.sh
```

This builds the app, codesigns it with your Developer ID certificate,
notarizes it with Apple, staples the ticket, and produces
`BlackBox-<version>.dmg` in the project root.

The build scratch directory is `build-pkg/` (gitignored). It is wiped and
rebuilt on each run.

## Publishing a release

```sh
./build-aux/macos/package.sh --publish
```

In addition to building the DMG, this:

1. Creates a GitHub release at `raggesilver/blackbox` and uploads the DMG
2. Updates the version and SHA256 in the Homebrew tap
   (`raggesilver/homebrew-tap`) and pushes the change

The tap repo is cloned into `build-pkg/homebrew-tap/` on first run and
pulled on subsequent runs.

## How the .app bundle works

The `.app` is a thin launcher — `Contents/MacOS/BlackBox` — that sets up the
required environment variables (GLib schemas, XDG data dirs, Adwaita CSS
overlay) and then `execv`s into the `blackbox-terminal` binary installed by
Homebrew. The actual app binary is provided by the `blackbox-terminal` formula,
which Homebrew installs automatically as a cask dependency.
