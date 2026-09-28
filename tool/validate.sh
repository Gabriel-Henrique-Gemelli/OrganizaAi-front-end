#!/usr/bin/env bash
set -euo pipefail
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --release --no-tree-shake-icons
