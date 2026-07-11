# Build and install locally

WoC Player Count is currently distributed as source code. There is no official prebuilt `.app`,
ZIP, or DMG to download. Building it on your own Mac is free and does not require a paid Apple
Developer Program membership, a Developer ID certificate, or notarization credentials.

## Requirements

- macOS 14 or newer
- a full Xcode 16 or newer installation
- an internet connection for cloning the repository and for the app's live data

The standalone Command Line Tools are not sufficient because they do not include
`xcstringstool`, which compiles the app's localized interface. Open Xcode once after installing it
so macOS can finish installing its components.

## Install and launch

In Terminal, run:

```bash
git clone https://github.com/FernandoX7/woc-widget.git
cd woc-widget
./install.sh
```

If the preflight says full Xcode is not selected, run the command it prints, then try again:

```bash
sudo xcode-select --switch /Applications/Xcode.app
```

If Xcode is installed somewhere else, replace `/Applications/Xcode.app` with its actual path. Do
not run `install.sh` or `build.sh` with `sudo`.

The installer:

1. confirms macOS 14+ and a usable full Xcode installation;
2. compiles the app from the checked-out source for the current Mac;
3. assembles and ad-hoc signs the local app bundle;
4. replaces only `WoC Player Count.app` at the selected destination; and
5. quits an older running copy and launches the newly built one.

It does not request an Apple account, use any installed distribution identity, or read notarization
credentials. Replacing the app does not remove its settings or locally observed player history.

## Where the app is installed

On a first install, the installer tries these locations in order:

1. `/Applications/WoC Player Count.app`
2. `~/Applications/WoC Player Count.app` when the system Applications directory is not writable and
   no system-wide copy already exists

It validates the destination before compiling. An existing app is replaced only when its bundle
identity matches WoC Player Count and the replacement can be completed safely. The new copy is
staged and signature-verified first; a failed activation is rolled back. If no safe Applications
directory is available, the installer exits with an explanation instead of creating a duplicate or
launching a bundle from the checkout.

Later installs update whichever of those two locations already contains the app. If copies exist in
both places, the installer asks you to keep one and remove the other before it proceeds.

The installed path is printed in Terminal. A custom absolute destination is also available:

```bash
WOC_INSTALL_DIR="$HOME/Applications" ./install.sh
```

An explicitly selected `WOC_INSTALL_DIR` does not fall back to a different directory if it cannot
be used. Keeping the app in an Applications directory is recommended for reliable Launch at Login
behavior.

WoC Player Count is a menu-bar app and intentionally has no Dock icon. After launch, look for its
world-and-signal icon on the right side of the menu bar. Use the power button in the popover footer
to quit.

## Update

There is no automatic updater. Return to the checkout and rebuild the latest source:

```bash
cd /path/to/woc-widget
git pull --ff-only
./install.sh
```

The installer replaces the application bundle and relaunches it. Preferences and history remain in
their normal per-user storage. If `git pull --ff-only` reports local commits or changed files,
preserve those changes before updating; do not delete them just to force the pull.

For a specific tagged source version, check out that tag before installing:

```bash
git fetch --tags
git checkout TAG_NAME
./install.sh
```

Return to the current default branch later with `git switch main`.

## Safe first launch

A bundle produced by `install.sh` is ad-hoc signed on the same Mac that runs it. It is not signed by
Developer ID and is not notarized for redistribution. Normally it opens immediately because it was
built locally.

If macOS blocks the first launch, do not disable Gatekeeper and do not run commands that remove
security attributes globally. Instead:

1. read the final installed path printed by `install.sh`;
2. reveal that exact `WoC Player Count.app` in Finder;
3. Control-click that exact app, choose **Open**, and confirm **Open**; or
4. immediately after the blocked attempt, use **System Settings → Privacy & Security → Open
   Anyway** only for that exact app you just built.

Do not approve an app bundle received from another person. Clone or inspect this repository and
build your own copy instead.

## Troubleshooting

### Full Xcode is not selected

Check the active developer directory and tools:

```bash
xcode-select -p
xcodebuild -version
xcrun --find xcstringstool
./install.sh --check
```

If the path is `/Library/Developer/CommandLineTools`, select full Xcode:

```bash
sudo xcode-select --switch /Applications/Xcode.app
```

Open Xcode once if it asks to install components or accept its license, then run `./install.sh`
again.

### The app did not go into `/Applications`

Do not rerun the whole installer with `sudo`. Read its final status line: it may have safely used
`~/Applications`. You can launch the per-user copy with:

```bash
open "$HOME/Applications/WoC Player Count.app"
```

If an older protected copy remains in `/Applications`, the installer deliberately refuses to create
a second per-user copy. Quit the old copy and remove only that exact app in Finder (or ask an
administrator to replace it), then reinstall. This avoids ambiguous copies in Launch Services.

### The build succeeded but no window appeared

This app has no Dock icon or normal application window. Look in the menu bar. If the icon is hidden,
close or rearrange other menu-bar items, then relaunch the exact path printed by the installer.

### Verify the local bundle

Use the path printed by the installer. For the normal system installation:

```bash
codesign --verify --strict --verbose=2 "/Applications/WoC Player Count.app"
```

A successful verification produces no error. This confirms bundle integrity; it does not turn the
local ad-hoc signature into a Developer ID or notarized distribution signature.

## Other build commands

The friendly installer calls the repository's lower-level build path. Contributors can also use:

```bash
./build.sh run       # compile, install, and relaunch
./build.sh           # compile and install without relaunching
./build.sh bundle    # keep a production bundle under build/ without installing
./build.sh check     # type-check the complete app source
./build.sh preview   # launch the synthetic-data preview; never install it
swift test           # run deterministic WoCKit tests
```

## Uninstall

1. Quit WoC Player Count from its popover footer.
2. Remove `WoC Player Count.app` from `/Applications` or `~/Applications`.
3. If enabled, remove its item in **System Settings → General → Login Items**.

The source checkout can then be deleted normally. Settings and history are intentionally retained
so reinstalling does not silently erase them. To remove that data too, run:

```bash
rm -rf "$HOME/Library/Application Support/WoCWidget"
defaults delete io.github.fernandox7.wocplayercount 2>/dev/null || true
```

These last commands permanently remove the app's local history and preferences for the current
macOS user.
