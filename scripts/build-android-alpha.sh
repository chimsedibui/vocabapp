#!/usr/bin/env bash
set -euo pipefail
vocab_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$vocab_root/scripts/dev-env.sh"
cd "$vocab_root/app"
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
flutter build apk --no-pub --debug --target-platform android-arm64
mkdir -p "$vocab_root/artifacts"
vocab_version="$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+.*/\1/p' pubspec.yaml)"
test -n "$vocab_version"
vocab_apk="$vocab_root/artifacts/VocabApp-$vocab_version-android-arm64-debug.apk"
cp build/app/outputs/flutter-apk/app-debug.apk "$vocab_apk"
(cd "$vocab_root/artifacts" && sha256sum "$(basename "$vocab_apk")" > "$(basename "$vocab_apk").sha256")
printf 'APK: %s\n' "$vocab_apk"
