#!/bin/zsh
# Regenerates Swift types. Requires protoc and protoc-gen-swift (build from swift-protobuf).
set -euo pipefail
cd "$(dirname "$0")"
PLUGIN="${PROTOC_GEN_SWIFT:?set PROTOC_GEN_SWIFT to the protoc-gen-swift binary}"
OUT=../GoogleTVKit/Sources/GoogleTVKit/Protocol/Generated
mkdir -p "$OUT"
protoc --plugin=protoc-gen-swift="$PLUGIN" --swift_out="$OUT" \
  --swift_opt=Visibility=Public polo.proto remotemessage.proto
