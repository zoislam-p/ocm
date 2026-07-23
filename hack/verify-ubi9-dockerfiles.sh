#!/usr/bin/env bash
set -euo pipefail

dockerfiles=(
  build/Dockerfile.addon
  build/Dockerfile.placement
  build/Dockerfile.registration
  build/Dockerfile.registration-operator
  build/Dockerfile.work
)

for dockerfile in "${dockerfiles[@]}"; do
  runtime_from="$(awk 'toupper($1) == "FROM" {line=$0} END {print line}' "$dockerfile")"
  if [[ "$runtime_from" != "FROM registry.access.redhat.com/ubi9/ubi:latest" ]]; then
    echo "$dockerfile: runtime stage is not registry.access.redhat.com/ubi9/ubi:latest" >&2
    exit 1
  fi
  if ! grep -Eq '^ENV[[:space:]]+USER_UID=10001$' "$dockerfile" || \
     ! grep -Eq '^USER[[:space:]]+\$\{USER_UID\}$' "$dockerfile"; then
    echo "$dockerfile: runtime stage must use UID 10001" >&2
    exit 1
  fi
done

echo "UBI9 Dockerfile verification passed for ${#dockerfiles[@]} images."
