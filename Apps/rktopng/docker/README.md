# RkTopNG Docker image

Everything needed to build and publish the image that `Apps/rktopng/docker-compose.yml` runs:
`shad0w82/rktopng` on Docker Hub. The app itself lives in
[shad0w82/cm3588-rktopng](https://github.com/shad0w82/cm3588-rktopng). The image is **not compiled here**: it is made
from the binary attached to a GitHub release of the app, so the image and the release stay tied together.
The app is made for the RK3588, so the image is **arm64 only**.

```
Apps/rktopng/docker/
├── Dockerfile   Alpine + smartmontools + the binary (a few lines, no Go, no Node, no source)
├── build.sh     downloads the release binary, checks its checksum, builds (and optionally pushes) the image
└── README.md    this file
```

> **Do not add a file named `docker-compose.yml` (or `.yaml`) in this folder or below.** CasaOS walks
> every folder under `Apps/` and reads each one that has such a file as another app.

## How the image is tied to the code

```
git tag v0.1.1  ──►  GitHub release v0.1.1  ──►  rktopng-linux-arm64 + SHA256SUMS  ──►  image shad0w82/rktopng:0.1.1
 (app repo)           (make release-publish)      (the same files users download)        (build.sh 0.1.1)
```

`./build.sh 0.1.1` downloads `rktopng-linux-arm64` and `SHA256SUMS` from the release `v0.1.1`, **stops if the
checksum does not match**, and puts that exact file in the image. The image therefore contains, byte for byte,
the binary users can also download from the release. It also records where it came from:

```bash
docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' shad0w82/rktopng:0.1.1   # the commit of the tag
docker inspect --format '{{ index .Config.Labels "io.github.shad0w82.rktopng.binary-sha256" }}' shad0w82/rktopng:0.1.1   # the binary's checksum
```

Rules:

- **Never move or delete a tag or a release that has been published.** `build.sh` refuses to push a version that
  is already on Docker Hub; a fix is a new version.
- Versions are `X.Y.Z` (`0.1.1`), and the compose always names one (`image: shad0w82/rktopng:0.1.1`), never
  `latest`, so what runs is always known.
- Pushing to the app repository does **not** change any published image. Only a new release does.

## One-time setup on the board

```bash
git clone https://github.com/shad0w82/cm3588-casaos-appstore.git ~/cm3588-casaos-appstore
docker login -u shad0w82      # use a Docker Hub access token (Read & Write), not the account password
```

`git`, `curl` and Docker are all it needs. There is nothing to compile on the board.

## Releasing a new version

The order matters: the compose is updated **last**, when the image is already on Docker Hub.

1. **On the Mac, in the app repository (`cm3588-rktopng`)**: test, commit, tag, then build and publish the release.

   ```bash
   git tag v0.1.1 && git push origin main v0.1.1
   make release VERSION=0.1.1            # tests, builds the arm64 binary, writes dist/release/ (nothing leaves the Mac)
   make release-publish VERSION=0.1.1    # creates the public GitHub release with the binary and SHA256SUMS
   ```

   `make release` refuses a dirty tree and a tag that does not point to the current commit, so the binaries
   always come from the tagged code.

2. **On the board, in this store's clone**: get the latest script, build, test, then publish.

   ```bash
   cd ~/cm3588-casaos-appstore && git pull
   cd Apps/rktopng/docker
   ./build.sh 0.1.1                # build only, nothing is pushed
   # ... test the image (next section) ...
   ./build.sh 0.1.1 --push         # same build, then push to Docker Hub
   ```

   The script ends by printing the exact `image:` line for the compose.

3. **On the Mac, in this store repository**: put that line in `Apps/rktopng/docker-compose.yml`, commit and push.

An app that is already installed in CasaOS keeps its own copy of the compose, so it does not change by itself:
update the image from the app's settings, or reinstall it.

## Testing an image before publishing it

Run it on a port the native service does not use (it owns 9888), with the same mounts as the compose:

```bash
docker run --rm --name rktopng-test -p 9899:9888 --privileged \
  -v /proc:/host/proc:ro -v /sys:/host/sys:ro -v /:/host/root:ro \
  -v /etc/os-release:/host/os-release:ro -v /etc/passwd:/host/passwd:ro \
  -e RKTOP_PROC_PATH=/host/proc -e RKTOP_SYS_PATH=/host/sys -e RKTOP_ROOTFS_PATH=/host/root \
  -e RKTOP_OSRELEASE_PATH=/host/os-release -e RKTOP_PASSWD_PATH=/host/passwd \
  shad0w82/rktopng:0.1.1
```

Then open `http://<board>:9899/`, or `curl -s localhost:9899/api/info | head -c 300`. Stop it with Ctrl-C.
To also try the sub-path and the password, add `-e RKTOP_BASE_PATH=/rktopng -e RKTOP_AUTH_USER=... -e RKTOP_AUTH_PASSWORD=...`
(then the address is `http://<board>:9899/rktopng/`).

To try the Dockerfile **before a release exists**, build from a local binary. It is tagged `:dev` and the script
refuses to push it:

```bash
# on the Mac:  make build-arm64 && scp dist/rktopng-linux-arm64 <board>:
./build.sh --binary ~/rktopng-linux-arm64
```

(then `docker run ... shad0w82/rktopng:dev` with the command above.)

`--dry-run` on any of these runs all the checks, downloads included, and prints the docker commands without running them.

## If something goes wrong

| Message | What it means |
|---|---|
| `tag v0.1.1 not found` | Tag and push it from the app repository first (step 1). |
| `the release v0.1.1 has no SHA256SUMS` | The tag exists but the release was not published: `make release` and `make release-publish`. |
| `checksum mismatch` | The downloaded binary is not the one the release lists. Do not use it; check the release assets. |
| `... is already on Docker Hub` | That version was published; release a new version number. |
| `cannot reach the Docker daemon` | Docker is not running, or the user is not in the `docker` group. |
| `denied` / `unauthorized` while pushing | Run `docker login -u shad0w82` again with a valid token. |

## Relation to the app repository

The app repository's `docker-compose.yml` runs the same image (`image: shad0w82/rktopng:<version>`), so people who
use the app without CasaOS get exactly what is built here. There is no Dockerfile there that compiles from source:
development uses Go and Node locally (`make test`, `make dev`, `make build-arm64`), and the image is made only from
a release. Once the image is published, update the version in that compose together with this store's compose.
