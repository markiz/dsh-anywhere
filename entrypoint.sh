#!/usr/bin/env bash
set -Eeuo pipefail

port="${DSH_WEB_PORT:-3080}"
profile_patch=/usr/local/share/dsh-anywhere/profile.yml
mkdir -p "${HOME:-/dsh/home}" 2>/dev/null || true

if [[ ! -f "$profile_patch" ]]; then
  printf 'Missing profile overlay: %s\n' "$profile_patch" >&2
  exit 1
fi

container_ip="$(hostname -i 2>/dev/null | awk '{print $1}')"
if [[ -z "$container_ip" ]]; then
  printf 'Could not determine the container address for the DSH web server.\n' >&2
  exit 1
fi

exec dsh web \
  --patch "$profile_patch" \
  --host "$container_ip" \
  --port "$port" \
  --no-open \
  --public-url "http://127.0.0.1:${port}/" \
  --trusted-host 127.0.0.1 \
  --trusted-host localhost "$@"
