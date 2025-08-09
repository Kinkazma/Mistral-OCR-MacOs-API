#!/bin/bash
set -e
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen..."
  brew install xcodegen
fi
xcodegen generate
open MistralOCR_Desktop.xcodeproj
