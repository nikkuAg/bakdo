#!/bin/bash
# Checks the toolchain and downloads the prebuilt whisper.cpp and llama.cpp frameworks Bakdo links
# against (pinned versions, verified by SHA-256). Safe to run again; finished steps are skipped.
set -euo pipefail
cd "$(dirname "$0")/.."

red() { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
fail() { red "✗ $*"; exit 1; }

# --- Requirements -----------------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || fail "Bakdo is a macOS app."
[[ "$(uname -m)" == "arm64" ]] || fail "Bakdo needs an Apple Silicon Mac (M1 or newer)."
macos_major=$(sw_vers -productVersion | cut -d. -f1)
(( macos_major >= 14 )) || fail "Bakdo needs macOS 14 Sonoma or newer (you have $(sw_vers -productVersion))."

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  red "✗ Apple's command line developer tools are missing."
  echo "  Install them with:  xcode-select --install"
  echo "  then run this script again."
  exit 1
fi
swift_version=$(swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1.\2/p' | head -1)
swift_major=${swift_version%%.*}
(( ${swift_major:-0} >= 6 )) || fail "Swift 6 or newer is required (found ${swift_version:-none}). Update with: softwareupdate --list, or install the latest Xcode / Command Line Tools."
green "✓ macOS $(sw_vers -productVersion), Apple Silicon, Swift $swift_version"

# --- Frameworks -------------------------------------------------------------------------------
fetch() {
  local name="$1" url="$2" sha="$3"
  if [[ -d "Vendor/build-apple/$name.xcframework" ]]; then
    green "✓ $name.xcframework already present"
    return
  fi
  echo "↓ Downloading $name.xcframework…"
  local tmp
  tmp=$(mktemp -d)
  curl -fL --retry 3 --progress-bar -o "$tmp/$name.zip" "$url"
  local got
  got=$(shasum -a 256 "$tmp/$name.zip" | cut -d' ' -f1)
  [[ "$got" == "$sha" ]] || { rm -rf "$tmp"; fail "$name download is corrupted (checksum mismatch). Run the script again."; }
  mkdir -p Vendor
  unzip -q -o "$tmp/$name.zip" -d Vendor
  rm -rf "$tmp"
  [[ -d "Vendor/build-apple/$name.xcframework" ]] || fail "$name.xcframework not found after unzip."
  green "✓ $name.xcframework installed"
}

fetch whisper \
  "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip" \
  "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"
fetch llama \
  "https://github.com/ggml-org/llama.cpp/releases/download/b11707/llama-b11707-xcframework.zip" \
  "a276f9366d6b16feff34b1851ec9ffbda629be7c4a3c6fda4923b172ea6a4a93"

green "✓ Setup complete. Next: ./scripts/build-app.sh --install"
