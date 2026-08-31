#!/usr/bin/env bash
#
# Ejecuta la batería de tests del modelo. Los mismos que corren en CI.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NOISE="CoreSimulator|SimServiceContext|DVTErrorPresenter|IDERunDestination|Unable to load simulator|^Domain:|^Code:|^Failure Reason:|^Recovery Suggestion:|^--$|^$"

xcodebuild test -project Present.xcodeproj -scheme Present -destination "platform=macOS" \
  2> >(grep -vE "$SIM_NOISE" >&2) \
  | grep -E "\.swift.*(error|warning):|Test Case .* failed|Executed .* tests|^\*\* TEST" \
  || true
