#!/bin/bash
# One command to go from a fresh clone to a running Inscribo:
# checks requirements, downloads dependencies, builds Inscribo.app, installs it to /Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/setup.sh
./scripts/build-app.sh --install
open /Applications/Inscribo.app
printf "\n\033[32m✓ Inscribo is installed and running.\033[0m\n"
echo "  Follow the welcome screen to grant Microphone + Accessibility; the speech models (~1.9 GB) download automatically."
