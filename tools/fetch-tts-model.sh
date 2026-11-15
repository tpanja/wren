#!/bin/sh
# Downloads the Kokoro v1.0 (int8) voice model that Wren speaks with, from the
# official sherpa-onnx releases, and keeps only the English files the app uses.
# The model is too large for git; run this once after cloning.
set -eu
cd "$(dirname "$0")/.."
DEST=BundledModels/Kokoro
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -L --fail -o "$TMP/kokoro.tar.bz2" \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2
tar xjf "$TMP/kokoro.tar.bz2" -C "$TMP"
SRC="$TMP/kokoro-int8-multi-lang-v1_0"
rm -rf "$DEST" && mkdir -p "$DEST"
cp "$SRC/model.int8.onnx" "$SRC/voices.bin" "$SRC/tokens.txt" "$SRC/lexicon-us-en.txt" "$SRC/LICENSE" "$DEST/"
cp -R "$SRC/espeak-ng-data" "$DEST/"
echo "Kokoro model in $DEST ($(du -sh "$DEST" | cut -f1))"
