#!/bin/zsh

set -euo pipefail

versioned_candidates=("${(@f)$(find /Applications -maxdepth 1 -type d -name 'Xcode_*.app' ! -iname '*beta*' -print | sort -V)}")

if (( ${#versioned_candidates[@]} > 0 )); then
  selected_xcode=${versioned_candidates[-1]}
elif [[ -d /Applications/Xcode.app ]]; then
  selected_xcode=/Applications/Xcode.app
else
  echo "error: could not find a stable Xcode installation under /Applications" >&2
  exit 1
fi

echo "Selecting Xcode at $selected_xcode"
sudo xcode-select -s "$selected_xcode/Contents/Developer"
xcodebuild -version
