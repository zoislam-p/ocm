#!/usr/bin/env bash
set -euo pipefail

engine="${CONTAINER_ENGINE:-docker}"
registry="${IMAGE_REGISTRY:-ocm-ubi9}"
tag="${IMAGE_TAG:-phase1}"
platform="${PLATFORM:-linux/amd64}"

images=(registration work placement registration-operator addon)
declare -A binaries=(
  [registration]="/registration /server"
  [work]="/work"
  [placement]="/placement"
  [registration-operator]="/registration-operator"
  [addon]="/addon"
)

for name in "${images[@]}"; do
  image="${registry}/${name}:${tag}"
  os="$($engine image inspect "$image" --format '{{.Os}}')"
  arch="$($engine image inspect "$image" --format '{{.Architecture}}')"
  user="$($engine image inspect "$image" --format '{{.Config.User}}')"

  [[ "$os" == "linux" ]] || { echo "$image: expected linux, got $os" >&2; exit 1; }
  [[ "$arch" == "amd64" ]] || { echo "$image: expected amd64, got $arch" >&2; exit 1; }
  [[ "$user" == "10001" ]] || { echo "$image: expected USER 10001, got $user" >&2; exit 1; }

  release="$($engine run --rm --platform "$platform" "$image" /bin/bash -c 'cat /etc/redhat-release')"
  [[ "$release" == *"release 9."* ]] || { echo "$image: expected UBI/RHEL 9, got $release" >&2; exit 1; }

  for binary in ${binaries[$name]}; do
    $engine run --rm --platform "$platform" "$image" /bin/bash -c "test -x '$binary'"
    $engine run --rm --platform "$platform" "$image" "$binary" --help >/dev/null
  done

  echo "PASS $image ($os/$arch, user=$user, $release)"
done

echo "All UBI9 image tests passed."
