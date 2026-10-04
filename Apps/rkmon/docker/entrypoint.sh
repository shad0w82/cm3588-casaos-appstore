#!/bin/sh
# Serve rkmon over a gotty web terminal (mirrors bigbear's btop entrypoint).
# -w (--permit-write) lets the browser send rkmon's keybinds. Optional basic-auth
# via env, so CasaOS users can set credentials from the app UI.
export HOME=/root
export TERM="${TERM:-xterm-256color}"

# Defaults (overridden at runtime via docker-compose / CasaOS env).
GOTTY_AUTH_ENABLED="${GOTTY_AUTH_ENABLED:-true}"
GOTTY_AUTH_USER="${GOTTY_AUTH_USER:-admin}"
GOTTY_AUTH_PASS="${GOTTY_AUTH_PASS:-changeme}"

if [ "$GOTTY_AUTH_ENABLED" = "true" ]; then
    exec gotty -p 7681 -w -c "${GOTTY_AUTH_USER}:${GOTTY_AUTH_PASS}" rkmon
else
    exec gotty -p 7681 -w rkmon
fi
