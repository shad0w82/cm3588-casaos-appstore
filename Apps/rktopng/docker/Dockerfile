# RkTopNG runtime image: Alpine + smartmontools (S.M.A.R.T. needs `smartctl`) + the released binary.
#
# Not built by hand: build.sh makes a temporary build context that holds this file and the
# checksum-verified binary of a GitHub release as "rktopng". The binary is static and already carries
# the dashboard (go:embed), so there is nothing else to install: no Go, no Node, no source.
FROM alpine:3.21
RUN apk add --no-cache smartmontools
COPY --chmod=0755 rktopng /usr/local/bin/rktopng
EXPOSE 9888
ENTRYPOINT ["/usr/local/bin/rktopng"]
