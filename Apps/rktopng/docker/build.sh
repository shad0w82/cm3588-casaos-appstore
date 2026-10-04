#!/usr/bin/env bash
# Build (and optionally publish) the RkTopNG Docker image from a GitHub release of the app.
#
#   ./build.sh <version> [--push] [--dry-run]   release build: the binary of the release v<version>
#   ./build.sh --binary <file> [--dry-run]      test build from a local binary; tagged :dev, never pushed
#
# shad0w82/rktopng:<version> contains, byte for byte, the binary attached to the release v<version> of
# https://github.com/shad0w82/rktopng: the script downloads it together with the release's SHA256SUMS,
# checks the checksum and puts it in a minimal Alpine image (see the Dockerfile next to this script).
# Nothing is compiled here. Nothing is sent to Docker Hub unless --push is given, and a version that
# is already on Docker Hub is never overwritten. --dry-run does every check, downloads included, but
# prints the docker commands instead of running them.
#
# The app is made for the RK3588, so the image is arm64 only. Needs git, curl and Docker; the CM3588 is a
# fine place to run it, since it is arm64 too. RELEASE_BASE, REPO_URL and IMAGE can be overridden from the
# environment (for testing).

set -euo pipefail

RELEASE_BASE="${RELEASE_BASE:-https://github.com/shad0w82/rktopng/releases/download}"
REPO_URL="${REPO_URL:-https://github.com/shad0w82/rktopng.git}"
SOURCE_URL="https://github.com/shad0w82/rktopng"
IMAGE="${IMAGE:-shad0w82/rktopng}"
PLATFORM="linux/arm64"
ASSET="rktopng-linux-arm64"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage: ./build.sh <version> [--push] [--dry-run]
       ./build.sh --binary <file> [--dry-run]

  <version>        like 0.1.1 (no leading v); uses the binary of the GitHub release v<version>
  --push           after building, push the image to Docker Hub (never overwrites a version)
  --binary <file>  test build from a local binary (e.g. dist/rktopng-linux-arm64), tagged :dev, never pushed
  --dry-run        run the checks (downloads included) and print the docker commands without running them
EOF
  exit "${1:-0}"
}

VERSION=""; BINARY=""; PUSH=0; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --push) PUSH=1 ;;
    --dry-run) DRY=1 ;;
    --binary)
      [[ -n "${2:-}" && "${2:-}" != -* ]] || die "--binary needs the path of a binary"
      BINARY="$2"; shift ;;
    -*) die "unknown option '$1' (see --help)" ;;
    *) [[ -z "$VERSION" ]] || die "give one version only"; VERSION="$1" ;;
  esac
  shift
done

if [[ -n "$BINARY" ]]; then
  [[ -z "$VERSION" ]] || die "--binary is a test build: give a binary or a version, not both"
  (( ! PUSH )) || die "a --binary build is never pushed: release a version and use it instead"
  [[ -s "$BINARY" ]] || die "$BINARY does not exist or is empty"
else
  [[ -n "$VERSION" ]] || usage 1
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the version must look like 0.1.1 (no leading v), got '$VERSION'"
fi

command -v docker >/dev/null || die "docker is required"
if [[ -z "$BINARY" ]]; then
  command -v git >/dev/null || die "git is required (it looks up the commit of the release tag)"
  command -v curl >/dev/null || die "curl is required (it downloads the release)"
fi
if (( ! DRY )); then
  docker info >/dev/null 2>&1 || die "cannot reach the Docker daemon (is it running? is this user in the docker group?)"
fi

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Print the commit a ref points to, or nothing if the ref does not exist. For an annotated tag
# git lists the commit it points to as <ref>^{}; for a lightweight tag, as <ref>.
resolve() {
  git ls-remote "$REPO_URL" "$1" "$1^{}" 2>/dev/null |
    awk -v r="$1" '$2 == r "^{}" { peeled = $1 } $2 == r { plain = $1 } END { print (peeled != "" ? peeled : plain) }'
}

# The build context is a temporary folder: this Dockerfile and the verified binary, named "rktopng".
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT
cp "$HERE/Dockerfile" "$CTX/Dockerfile"

if [[ -n "$BINARY" ]]; then
  cp "$BINARY" "$CTX/rktopng"
  TAG="dev"; LABEL_VERSION="dev"; SHA="local"
  BIN_SHA="$(sha256 "$CTX/rktopng")"
  echo "==> test binary $BINARY (sha256 ${BIN_SHA:0:12})"
else
  TAG="$VERSION"; LABEL_VERSION="$VERSION"
  SHA="$(resolve "refs/tags/v$VERSION")"
  [[ -n "$SHA" ]] || die "tag v$VERSION not found in $REPO_URL. From the app repository: git tag v$VERSION && git push origin main v$VERSION"
  URL="$RELEASE_BASE/v$VERSION"
  curl -fsSL "$URL/SHA256SUMS" -o "$CTX/SHA256SUMS" ||
    die "the release v$VERSION has no SHA256SUMS at $URL. From the app repository: make release VERSION=$VERSION && make release-publish VERSION=$VERSION"
  WANT="$(awk -v a="$ASSET" '$2 == a { print $1 }' "$CTX/SHA256SUMS")"
  [[ -n "$WANT" ]] || die "SHA256SUMS of v$VERSION does not list $ASSET"
  echo "==> downloading $ASSET of v$VERSION"
  curl -fsSL "$URL/$ASSET" -o "$CTX/rktopng" || die "could not download $URL/$ASSET"
  BIN_SHA="$(sha256 "$CTX/rktopng")"
  [[ "$BIN_SHA" == "$WANT" ]] || die "checksum mismatch for $ASSET: the release says $WANT, the download is $BIN_SHA"
  echo "    checksum ok (sha256 ${BIN_SHA:0:12})"
  rm -f "$CTX/SHA256SUMS"
fi
chmod 0755 "$CTX/rktopng"

# 0 = this tag is already on the registry, 1 = it is not; any other failure stops the script.
registry_has() {
  local out
  if out="$(docker manifest inspect "$IMAGE:$1" 2>&1)"; then return 0; fi
  if grep -q -i -E 'no such manifest|manifest unknown|not found|does not exist|pull access denied|requested access to the resource is denied' <<<"$out"; then
    return 1
  fi
  die "could not check Docker Hub for $IMAGE:$1: $out"
}

if (( PUSH )); then
  if (( DRY )); then
    echo "[dry-run] would check that $IMAGE:$TAG is not on Docker Hub yet"
  elif registry_has "$TAG"; then
    die "$IMAGE:$TAG is already on Docker Hub. A published version is never overwritten: release a new version number."
  fi
fi

run() {
  if (( DRY )); then
    printf '[dry-run]'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

echo "==> $IMAGE:$TAG  ($PLATFORM)"
run docker build --pull --platform "$PLATFORM" --tag "$IMAGE:$TAG" \
  --label "org.opencontainers.image.title=RkTopNG" \
  --label "org.opencontainers.image.description=Dashboard and Prometheus exporter for the FriendlyElec CM3588 / Rockchip RK3588" \
  --label "org.opencontainers.image.source=$SOURCE_URL" \
  --label "org.opencontainers.image.revision=$SHA" \
  --label "org.opencontainers.image.version=$LABEL_VERSION" \
  --label "org.opencontainers.image.licenses=MIT" \
  --label "io.github.shad0w82.rktopng.binary-sha256=$BIN_SHA" \
  "$CTX"

if (( PUSH )); then
  echo "==> pushing $IMAGE:$TAG"
  run docker push "$IMAGE:$TAG"
fi

echo
if (( DRY )); then
  echo "Dry run: the checks passed, nothing was built or pushed."
elif [[ -n "$BINARY" ]]; then
  echo "Built $IMAGE:dev from $BINARY for testing. It is not pushed and cannot be."
else
  echo "Built $IMAGE:$VERSION from the binary of release v$VERSION (commit ${SHA:0:12})."
  if (( PUSH )); then
    echo "Pushed. Now put this line in Apps/rktopng/docker-compose.yml, then commit and push the store:"
  else
    echo "Not pushed. Test it (see README.md), then publish with:  ./build.sh $VERSION --push"
    echo "The line for Apps/rktopng/docker-compose.yml, once it is published:"
  fi
  echo "    image: $IMAGE:$VERSION"
fi
