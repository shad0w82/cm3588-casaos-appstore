# rkmon Docker image

Everything needed to build and publish the image that `Apps/rkmon/docker-compose.yml` runs:
`shad0w82/rkmon` on Docker Hub. rkmon itself is [isac322/rkmon](https://github.com/isac322/rkmon); the image is
**not compiled here**: it is made from the binary attached to a release of rkmon, plus gotty (the web terminal),
which is compiled from a pinned commit. The app is made for the RK3588, so the image is **arm64 only**.

```
Apps/rkmon/docker/
├── Dockerfile      Alpine + gotty (compiled) + the rkmon binary + the start script
├── entrypoint.sh   starts gotty with rkmon (login and base path come from the environment)
├── build.sh        downloads the rkmon release, checks its checksum, builds (and optionally pushes) the image
└── README.md       this file
```

> **Do not add a file named `docker-compose.yml` (or `.yaml`) in this folder or below.** CasaOS walks
> every folder under `Apps/` and reads each one that has such a file as another app.

## How the image is tied to its sources

```
rkmon release v0.3.1  ──►  rkmon_0.3.1_linux_arm64.tar.gz + checksums.txt  ──►  image shad0w82/rkmon:0.3.1
 (isac322/rkmon)             (downloaded and checked by build.sh)                (build.sh 0.3.1)
```

`./build.sh 0.3.1` downloads the arm64 tarball and `checksums.txt` of the rkmon release `v0.3.1`, **stops if the
checksum does not match**, and puts that exact binary (and its license) in the image. The image records where
everything came from:

```bash
docker inspect --format '{{ json .Config.Labels }}' shad0w82/rkmon:0.3.1 | tr ',' '\n' | grep io.github
# release            the rkmon version
# release-sha256     the checksum of the rkmon tarball
# gotty              the gotty version and the exact commit it was compiled from
# packaging-commit   the commit of this folder (Dockerfile, entrypoint.sh) the image was built from
```

Versions:

- The image tag is the rkmon release: `0.3.1`. When **only the packaging** changes (Dockerfile, `entrypoint.sh`,
  gotty, the base image), release it as `0.3.1-2`, then `0.3.1-3`, and so on. The part before the dash is the rkmon
  release to download; the first packaging of a release has no suffix.
- **A published version is never overwritten.** `build.sh` refuses to push a tag that is already on Docker Hub.
- The compose always names one version (`image: shad0w82/rkmon:0.3.1`), never `latest`, so what runs is known.
- `0.3.1` and `latest` on Docker Hub were built and pushed by hand before this script existed, from the same
  recipe. They stay as they are (`./build.sh 0.3.1 --push` is refused) and the script never touches `latest`.

Why gotty is compiled and not downloaded: the prebuilt gotty v1.8.0 breaks WebSocket basic-auth, v1.7.2 does not.
The build also gives the login a unique realm (`rkmon`), so a browser does not mix this login up with another gotty
app on the same host (a btop container, for instance). The gotty tag is pinned to its commit in the Dockerfile.

## One-time setup on the board

```bash
git clone https://github.com/shad0w82/cm3588-casaos-appstore.git ~/cm3588-casaos-appstore
docker login -u shad0w82      # use a Docker Hub access token (Read & Write), not the account password
```

`curl`, `tar` and Docker are all it needs. Nothing is compiled by hand: gotty is compiled inside the image build.

## Releasing a new version

The order matters: the compose is updated **last**, when the image is already on Docker Hub.

1. **A new rkmon release** (see <https://github.com/isac322/rkmon/releases>): nothing to do in this folder.
   **A packaging change**: edit `Dockerfile` or `entrypoint.sh` on the Mac, then commit and push the store, because
   a push of the image needs these files committed.

2. **On the board, in this store's clone**: get the latest files, build, test, then publish.

   ```bash
   cd ~/cm3588-casaos-appstore && git pull
   cd Apps/rkmon/docker
   ./build.sh 0.4.0                # build only, nothing is pushed (use 0.3.1-2 for a packaging revision)
   # ... test the image (next section) ...
   ./build.sh 0.4.0 --push         # same build, then push to Docker Hub
   ```

   The script ends by printing the exact `image:` line for the compose.

3. **On the Mac, in this store repository**: put that line in `Apps/rkmon/docker-compose.yml`, commit and push.

An app that is already installed in CasaOS keeps its own copy of the compose, so it does not change by itself:
update the image from the app's settings, or reinstall it.

A new rkmon release can change how rkmon is started or what it needs: always run the image (next section) before
`--push`.

## Testing an image before publishing it

Run it on a port the installed app does not use (it owns 7682), with the same mounts as the compose:

```bash
docker run --rm --name rkmon-test -p 7683:7681 --privileged \
  -v /proc:/proc -v /sys:/sys -v /dev:/dev \
  -e GOTTY_AUTH_USER=admin -e GOTTY_AUTH_PASS=<a test password> \
  shad0w82/rkmon:0.4.0
```

Then open `http://<board>:7683/`: the browser asks for the login, and rkmon shows up. Stop it with Ctrl-C.
`--dry-run` on any `build.sh` call runs all the checks, downloads included, and prints the docker commands without
running them.

## If something goes wrong

| Message | What it means |
|---|---|
| `the rkmon release v0.4.0 has no checksums.txt` | That rkmon release does not exist, or it has no `checksums.txt`. |
| `checksum mismatch` | The downloaded tarball is not the one the release lists. Do not use it; check the release assets. |
| `... is already on Docker Hub` | That version was published; release a new packaging revision or a new rkmon version. |
| `packaging files ... have uncommitted changes` | Commit (and push) this folder first; the image records the commit it was built from. |
| `cannot reach the Docker daemon` | Docker is not running, or the user is not in the `docker` group. |
| `denied` / `unauthorized` while pushing | Run `docker login -u shad0w82` again with a valid token. |
| The build fails while compiling gotty | It needs network access to GitHub and the Go module proxy. |
