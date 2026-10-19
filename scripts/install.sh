#!/bin/bash
# One command to go from a fresh clone to a running Bakdo:
# checks requirements, downloads dependencies, builds Bakdo.app, installs it to /Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/setup.sh
./scripts/build-app.sh --install
open /Applications/Bakdo.app
printf "\n\033[32m✓ Bakdo is installed and running.\033[0m\n"
echo "  Follow the welcome screen to grant Microphone + Accessibility; the speech models (~1.9 GB) download automatically."
