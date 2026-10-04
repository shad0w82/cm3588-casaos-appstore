#!/usr/bin/env bash
# Build (and optionally publish) the rkmon Docker image from a release of rkmon.
#
#   ./build.sh <version> [--push] [--dry-run]
#
# <version> is the rkmon release to package, like 0.3.1, and the tag of the image. When only this
# packaging changes (Dockerfile, entrypoint.sh, gotty, base image), release it as 0.3.1-2, 0.3.1-3, ...:
# the part before the dash is the rkmon release to download, the number after it is the packaging
# revision (the first packaging of a release has no suffix).
#
# shad0w82/rkmon:<version> contains the binary attached to the release v<rkmon version> of
# https://github.com/isac322/rkmon: the script downloads it with the release's checksums.txt, checks the
# checksum, and puts it in the image described by the Dockerfile next to this script (which also
# compiles gotty from a pinned commit). Nothing is sent to Docker Hub unless --push is given, a version
# that is already on Docker Hub is never overwritten, and a push needs the packaging files committed,
# so the image can be traced to them. --dry-run does every check, downloads included, but prints the
# docker commands instead of running them.
#
# The app is made for the RK3588, so the image is arm64 only. Needs curl, tar and Docker; the CM3588
# is a fine place to run it, since it is arm64 too. RELEASE_BASE and IMAGE can be overridden from the
# environment (for testing).

set -euo pipefail

RELEASE_BASE="${RELEASE_BASE:-https://github.com/isac322/rkmon/releases/download}"
SOURCE_URL="https://github.com/isac322/rkmon"
IMAGE="${IMAGE:-shad0w82/rkmon}"
PLATFORM="linux/arm64"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
usage: ./build.sh <version> [--push] [--dry-run]

  <version>   the rkmon release to package, like 0.3.1; use 0.3.1-2, 0.3.1-3, ... when only the packaging
              (Dockerfile, entrypoint.sh) changes
  --push      after building, push the image to Docker Hub (never overwrites a version)
  --dry-run   run the checks (downloads included) and print the docker commands without running them
EOF
  exit "${1:-0}"
}

VERSION=""; PUSH=0; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --push) PUSH=1 ;;
    --dry-run) DRY=1 ;;
    -*) die "unknown option '$1' (see --help)" ;;
    *) [[ -z "$VERSION" ]] || die "give one version only"; VERSION="$1" ;;
  esac
  shift
done

[[ -n "$VERSION" ]] || usage 1
[[ "$VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-([0-9]+))?$ ]] ||
  die "the version must look like 0.3.1, or 0.3.1-2 for a packaging revision (no leading v), got '$VERSION'"
RKMON_VERSION="${BASH_REMATCH[1]}"
REVISION="${BASH_REMATCH[3]:-}"
if [[ -n "$REVISION" ]] && (( REVISION < 2 )); then
  die "the first packaging of a release has no suffix: revisions start at -2 (got '$VERSION')"
fi
ASSET="rkmon_${RKMON_VERSION}_linux_arm64.tar.gz"

command -v docker >/dev/null || die "docker is required"
command -v curl >/dev/null || die "curl is required (it downloads the release)"
command -v tar >/dev/null || die "tar is required"
if (( ! DRY )); then
  docker info >/dev/null 2>&1 || die "cannot reach the Docker daemon (is it running? is this user in the docker group?)"
fi

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# The commit of the packaging files (this folder), so the image can be traced to them. A push needs
# them committed.
PKG_COMMIT="unknown"
if command -v git >/dev/null && git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1; then
  PKG_COMMIT="$(git -C "$HERE" rev-parse HEAD)"
  if [[ -n "$(git -C "$HERE" status --porcelain -- . 2>/dev/null)" ]]; then
    PKG_COMMIT="$PKG_COMMIT-dirty"
  fi
fi
if (( PUSH )) && [[ "$PKG_COMMIT" == "unknown" || "$PKG_COMMIT" == *-dirty ]]; then
  die "the packaging files in $HERE have uncommitted changes (or this is not a git clone): commit them first, so the pushed image can be traced to them"
fi

GOTTY_VERSION="$(awk -F= '/^ARG GOTTY_VERSION=/ { print $2 }' "$HERE/Dockerfile")"
GOTTY_COMMIT="$(awk -F= '/^ARG GOTTY_COMMIT=/ { print $2 }' "$HERE/Dockerfile")"

# The build context is a temporary folder: Dockerfile, entrypoint.sh, and the verified rkmon files.
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT
cp "$HERE/Dockerfile" "$HERE/entrypoint.sh" "$CTX/"

URL="$RELEASE_BASE/v$RKMON_VERSION"
curl -fsSL "$URL/checksums.txt" -o "$CTX/checksums.txt" ||
  die "the rkmon release v$RKMON_VERSION has no checksums.txt at $URL (does that release exist? $SOURCE_URL/releases)"
WANT="$(awk -v a="$ASSET" '$2 == a { print $1 }' "$CTX/checksums.txt")"
[[ -n "$WANT" ]] || die "checksums.txt of v$RKMON_VERSION does not list $ASSET"
echo "==> downloading $ASSET of rkmon v$RKMON_VERSION"
curl -fsSL "$URL/$ASSET" -o "$CTX/rkmon.tar.gz" || die "could not download $URL/$ASSET"
GOT="$(sha256 "$CTX/rkmon.tar.gz")"
[[ "$GOT" == "$WANT" ]] || die "checksum mismatch for $ASSET: the release says $WANT, the download is $GOT"
echo "    checksum ok (sha256 ${GOT:0:12})"
tar -xzf "$CTX/rkmon.tar.gz" -C "$CTX" rkmon LICENSE || die "$ASSET does not contain the expected files (rkmon, LICENSE)"
[[ -s "$CTX/rkmon" && -s "$CTX/LICENSE" ]] || die "$ASSET has an empty rkmon or LICENSE"
mv "$CTX/LICENSE" "$CTX/rkmon-LICENSE"
chmod 0755 "$CTX/rkmon"
rm -f "$CTX/rkmon.tar.gz" "$CTX/checksums.txt"

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
    echo "[dry-run] would check that $IMAGE:$VERSION is not on Docker Hub yet"
  elif registry_has "$VERSION"; then
    die "$IMAGE:$VERSION is already on Docker Hub. A published version is never overwritten: release a new packaging revision (e.g. $RKMON_VERSION-$(( ${REVISION:-1} + 1 ))) or a new rkmon version."
  fi
fi

run() {
  if (( DRY )); then
    printf '[dry-run]'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

echo "==> $IMAGE:$VERSION  ($PLATFORM)"
run docker build --pull --platform "$PLATFORM" --tag "$IMAGE:$VERSION" \
  --label "org.opencontainers.image.title=rkmon" \
  --label "org.opencontainers.image.description=rkmon (RK3588 hardware monitor by isac322) in a browser web terminal (gotty)" \
  --label "org.opencontainers.image.source=$SOURCE_URL" \
  --label "org.opencontainers.image.version=$VERSION" \
  --label "org.opencontainers.image.licenses=MIT" \
  --label "io.github.shad0w82.rkmon.release=$RKMON_VERSION" \
  --label "io.github.shad0w82.rkmon.release-sha256=$GOT" \
  --label "io.github.shad0w82.rkmon.gotty=$GOTTY_VERSION@$GOTTY_COMMIT" \
  --label "io.github.shad0w82.rkmon.packaging-commit=$PKG_COMMIT" \
  "$CTX"

if (( PUSH )); then
  echo "==> pushing $IMAGE:$VERSION"
  run docker push "$IMAGE:$VERSION"
fi

echo
if (( DRY )); then
  echo "Dry run: the checks passed, nothing was built or pushed."
else
  echo "Built $IMAGE:$VERSION from the binary of rkmon v$RKMON_VERSION."
  if (( PUSH )); then
    echo "Pushed. Now put this line in Apps/rkmon/docker-compose.yml, then commit and push the store:"
  else
    echo "Not pushed. Test it (see README.md), then publish with:  ./build.sh $VERSION --push"
    echo "The line for Apps/rkmon/docker-compose.yml, once it is published:"
  fi
  echo "    image: $IMAGE:$VERSION"
fi
