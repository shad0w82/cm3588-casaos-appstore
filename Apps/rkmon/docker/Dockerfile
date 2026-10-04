# rkmon (RK3588 hardware monitor by isac322) as a browser web-terminal via gotty. arm64 / RK3588 only.
#
# Not built by hand: build.sh makes a temporary build context that holds this file, entrypoint.sh and,
# as "rkmon" and "rkmon-LICENSE", the checksum-verified binary and license of an rkmon release.
#
# gotty is compiled from source at v1.7.2 instead of downloaded: the prebuilt v1.8.0 release breaks
# WebSocket basic-auth, this build does not (it mirrors bigbeartechworld/big-bear-btop's working recipe).
# The tag is pinned to its commit, so a moved tag cannot change what gets built.
FROM alpine:3.24.1

ARG GOTTY_VERSION=v1.7.2
ARG GOTTY_COMMIT=2e37e3f7c7d73502f145fb4608ebee2627889d45

# Runtime deps + a throwaway build toolchain (go/git) to compile gotty, removed afterwards to keep the
# image small. gcompat: glibc shim in case the rkmon release binary is glibc- (not musl-) linked.
RUN apk add --no-cache ca-certificates gcompat procps iproute2 \
 && apk add --no-cache --virtual .build git go \
 && git clone --depth 1 --branch ${GOTTY_VERSION} https://github.com/sorenisanerd/gotty.git /tmp/gotty \
 && [ "$(git -C /tmp/gotty rev-parse HEAD)" = "${GOTTY_COMMIT}" ] \
 # Unique Basic-auth realm so browsers don't reuse another gotty app's cached
 # credentials (they key basic-auth by host+realm, often ignoring the port —
 # e.g. a btop container on the same host would otherwise shadow rkmon's login).
 && sed -i 's/realm="GoTTY"/realm="rkmon"/g' /tmp/gotty/server/middleware.go \
 && cd /tmp/gotty && go build -o /usr/local/bin/gotty && cd / \
 && mkdir -p /usr/share/licenses/gotty && cp /tmp/gotty/LICENSE /usr/share/licenses/gotty/LICENSE \
 && rm -rf /tmp/gotty /root/go \
 && apk del .build \
 && chmod +x /usr/local/bin/gotty

# The rkmon binary comes after the gotty build, so a new rkmon release does not recompile gotty.
COPY --chmod=0755 rkmon /usr/local/bin/rkmon
COPY rkmon-LICENSE /usr/share/licenses/rkmon/LICENSE

# Only a non-sensitive locale here. Auth defaults live in entrypoint.sh and the
# real values are injected at runtime (docker-compose / CasaOS env), so no
# credential is baked into the image layers.
ENV LANG=C.UTF-8

COPY --chmod=0755 entrypoint.sh /entrypoint.sh

EXPOSE 7681
ENTRYPOINT ["/entrypoint.sh"]
