#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f config.json ]]; then
  echo 'Copie config.example.json para config.json e informe API_BASE_URL antes de iniciar.' >&2
  exit 1
fi
flutter pub get
dart tool/bootstrap.dart
flutter run --dart-define-from-file=config.json "$@"
