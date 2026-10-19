# Installing Bakdo

This guide takes you from nothing to a working Bakdo in about 10 minutes, most of it downloads.

- [1. Check your Mac](#1-check-your-mac)
- [2. Install Apple's developer tools](#2-install-apples-developer-tools)
- [3. Get the code](#3-get-the-code)
- [4. Build and install](#4-build-and-install)
- [5. First launch](#5-first-launch)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)

## 1. Check your Mac

You need an **Apple Silicon Mac (M1 or newer)** on **macOS 14 Sonoma or later**, with about **2 GB free**.

Check from  › About This Mac: the *Chip* line should say Apple M-something.

## 2. Install Apple's developer tools

Bakdo is built from source with Swift. You only need Apple's free Command Line Tools, not the full Xcode:

```bash
xcode-select --install
```

Click **Install** in the dialog that appears and wait for it to finish (a few minutes). Check it worked:

```bash
swift --version
```

You should see `Swift version 6.x` or newer. If it's older, update the tools from System Settings › General › Software Update, or run `softwareupdate --list` to see available updates.

> Already have Xcode installed? That works too.

## 3. Get the code

```bash
git clone https://github.com/nikkuAg/bakdo.git
cd bakdo
```

No git? Download the ZIP from the GitHub page (**Code › Download ZIP**), unzip it, and `cd` into the folder in Terminal.

## 4. Build and install

```bash
./scripts/install.sh
```

This runs three steps, which you can also run one at a time:

| Step | Command | What it does |
|---|---|---|
| Setup | `./scripts/setup.sh` | Checks macOS, chip and Swift version, then downloads the pinned **whisper.cpp** and **llama.cpp** frameworks (~130 MB) into `Vendor/`, verifying their SHA-256 checksums |
| Build | `./scripts/build-app.sh` | Compiles a release build, assembles `build/Bakdo.app`, and signs it ad-hoc |
| Install | `./scripts/build-app.sh --install` | Same as Build, then copies the app to `/Applications` (replacing any older copy) |

The first build takes a minute or two. When it's done, Bakdo opens.

## 5. First launch

The welcome screen walks you through four steps:

1. **Welcome.**
2. **Permissions.**
   - **Microphone:** click *Grant* and allow it.
   - **Accessibility:** click *Grant*. macOS opens System Settings › Privacy & Security › **Accessibility**. Switch **Bakdo** on, then come back. The page updates by itself.

     Bakdo needs Accessibility to notice when you hold the dictation key in other apps, and to paste text into them.
3. **Models.** Both models download automatically (~1.9 GB in total) over several parallel connections. The download resumes if you quit halfway, and each file is checksum-verified before use. You can continue as soon as the speech model is ready; the writing (grammar) model can finish in the background.
4. **Try it.** Hold <kbd>space</kbd> in the practice box, or hold <kbd>fn</kbd> anywhere.

### Make the fn / 🌐 key work smoothly

By default macOS uses the Globe key for the emoji picker or input switching. Turn that off:

**System Settings › Keyboard › Press 🌐 key to › Do Nothing**

If you'd rather keep the Globe key as it is, pick **Right ⌥ Option**, **Right ⌘ Command** or **Right ⌃ Control** as the dictation key in Bakdo › Settings › Shortcut.

### Start at login (optional)

Bakdo › Settings › App › **Open at login**.

## Updating

```bash
cd bakdo
git pull
./scripts/install.sh
```

Your history, dictionary, settings and downloaded models are kept.

> **You'll need to re-grant Accessibility after every update.** Builds are signed locally (ad-hoc), so macOS sees each new build as a different app. In System Settings › Privacy & Security › Accessibility, select **Bakdo**, click **−**, then click *Grant* in Bakdo again. (Switching the old entry off and on is not enough.)

## Uninstalling

```bash
# Quit and remove the app
osascript -e 'quit app "Bakdo"'
rm -rf /Applications/Bakdo.app

# Remove models, history, dictionary and training recordings (~2 GB)
rm -rf ~/Library/Application\ Support/Bakdo

# Remove settings
defaults delete app.bakdo.mac
```

Then remove Bakdo from System Settings › Privacy & Security › **Accessibility** and **Microphone** with the **−** button.

## Troubleshooting

**Holding fn does nothing**
- Check Bakdo shows *Ready* in its sidebar, or in the menu bar icon's menu.
- Accessibility must be granted to the *current* build. If Bakdo is already switched on in the list but the app still says *Grant*, remove the entry with **−** and grant again (see [Updating](#updating)).
- Make sure *Press 🌐 key to* is set to **Do Nothing**, or choose a different dictation key in Settings.

**The emoji picker pops up when I dictate:** set *Press 🌐 key to* → **Do Nothing** (see above).

**The pill shows but nothing is typed**
- Accessibility isn't granted to this build. Re-grant it as described above.
- Some password fields and secure inputs block pasting by design.

**"Didn't catch that"** means the clip was too quiet or too short. Speak a little closer to the mic, or pick the right input in Settings › Microphone. Bluetooth headsets switch to a lower-quality call mode while recording; the built-in mic is usually better.

**Wrong words for names or jargon**
- Add them in **Dictionary › Vocabulary**.
- For words it keeps mishearing, add a **Replacement** (e.g. Versal → Vercel).
- Use **Voice training › Check accuracy** to find your most misheard words, and fix them in one click.

**Model download failed or is stuck:** open Settings and use *Try again*. Downloads resume where they stopped. Models live in `~/Library/Application Support/Bakdo/Models`.

**`setup.sh` says Swift is too old:** install the latest Command Line Tools (`softwareupdate --list`, or reinstall them with `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`).

**Build errors after `git pull`:** clear the build cache and try again:

```bash
rm -rf .build build && ./scripts/install.sh
```
