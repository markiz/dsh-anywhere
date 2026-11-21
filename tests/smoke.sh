#!/usr/bin/env bash
set -Eeuo pipefail

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1; pwd -P)
tmp=$(mktemp -d "$root/.test.XXXXXX")
trap 'rm -rf "${tmp:?}"' EXIT

# Keep the git-config lookup independent of the developer's identity.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect() {
  case $1 in
    *"$2"*) ;;
    *) fail "$3 (missing \"$2\")" ;;
  esac
}

bin="$tmp/bin"
mkdir -p "$bin"
cat >"$bin/docker" <<'FAKE'
#!/usr/bin/env bash
cmd=${1:-}; shift || true
if [[ $cmd == run ]]; then printf '%s\n' "$*" >>"$DOCKER_LOG"; exit 0; fi
if [[ $cmd == build ]]; then printf 'BUILD %s\n' "$*" >>"$DOCKER_LOG"; exit 0; fi
case $cmd in
  info) exit 0 ;;
  volume)
    [[ ${1:-} == inspect ]] && shift
    [[ ${1:-} == dsh-anywhere-home ]] && exit 0
    exit 1
    ;;
  *) exit 0 ;;
esac
FAKE
chmod +x "$bin/docker"

log="$tmp/docker.log"
run_launcher() {
  : >"$log"
  out=$(PATH="$bin:$PATH" DOCKER_LOG="$log" "$root/dsh-anywhere" "$@" 2>&1) || fail "launcher failed: $*"
}
main_run() {
  grep -- '--label dsh.anywhere=1' "$log" | tail -n 1
}
volume_of() {
  main_run | tr ' ' '\n' | sed -n 's/^type=volume,src=\([^,]*\),dst=\/dsh$/\1/p'
}

project="$tmp/project"
mkdir -p "$project"
git -C "$project" init -q
git -C "$project" config user.name "Repo User"
git -C "$project" config user.email repo@example.invalid

"$root/dsh-anywhere" --help >/dev/null || fail "--help"
grep -q -- 'chmod 0644 /usr/local/share/dsh-anywhere/profile.yml' "$root/Dockerfile" ||
  fail "profile overlay is not made world-readable"

run_launcher "$project"
expect "$out" "Starting DeepSeek Harness" "start banner"
expect "$out" "Workspace: /workspace" "workspace printed"
expect "$out" "Credentials: volume dsh-anywhere-credentials" "credentials printed"
grep -q -- '^BUILD -t dsh-anywhere:latest' "$log" || fail "auto build missing"
grep -q -- '--memory 4g' "$log" || fail "memory limit missing"
grep -q -- 'dsh-anywhere:latest' "$log" || fail "image missing"
grep -q -- '--rm' "$log" || fail "--rm missing"
grep -q -- 'dst=/workspace' "$log" || fail "workspace mount missing"
grep -q -- 'type=volume,src=dsh-anywhere-credentials,dst=/dsh-credentials' "$log" ||
  fail "credentials volume missing"
grep -q -- 'DSH_HOME=/dsh/home' "$log" || fail "dsh home missing"
grep -q -- 'GIT_AUTHOR_NAME=Repo User' "$log" || fail "git config author name"
grep -q -- 'GIT_AUTHOR_EMAIL=repo@example.invalid' "$log" || fail "git config author email"
grep -q -- 'GIT_COMMITTER_NAME=Repo User' "$log" || fail "git config committer name"
grep -q -- 'GIT_COMMITTER_EMAIL=repo@example.invalid' "$log" || fail "git config committer email"
case " $(main_run) " in
  *" -d "*) fail "container was started as a daemon" ;;
esac
case $(main_run) in
  *"--env-file"*|*"--build"*|*"--pull"*) fail "removed option in docker run" ;;
esac
port=$(main_run | sed -n 's/.*-p 127\.0\.0\.1:\([0-9]*\):[0-9]*.*/\1/p')
env_port=$(main_run | sed -n 's/.*DSH_WEB_PORT=\([0-9]*\).*/\1/p')
[[ -n $port && $port == "$env_port" ]] || fail "port mapping mismatch"

volume=$(volume_of)
[[ -n $volume ]] || fail "derived volume missing"
case $volume in
  dsh-anywhere-project-*) ;;
  *) fail "unexpected derived volume: $volume" ;;
esac
[[ $volume =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail "invalid volume name: $volume"

: >"$log"
out=$(PATH="$bin:$PATH" DOCKER_LOG="$log" \
  GIT_AUTHOR_NAME="Env Author" GIT_AUTHOR_EMAIL=env@example.invalid \
  "$root/dsh-anywhere" "$project" 2>&1)
grep -q -- 'GIT_AUTHOR_NAME=Env Author' "$log" || fail "env author name"
grep -q -- 'GIT_AUTHOR_EMAIL=env@example.invalid' "$log" || fail "env author email"
grep -q -- 'GIT_COMMITTER_NAME=Repo User' "$log" || fail "committer falls back to git config"
grep -q -- 'GIT_COMMITTER_EMAIL=repo@example.invalid' "$log" || fail "committer email falls back to git config"

plain="$tmp/plain"
mkdir -p "$plain"
: >"$log"
out=$(PATH="$bin:$PATH" DOCKER_LOG="$log" "$root/dsh-anywhere" "$plain" 2>&1)
grep -q -- 'GIT_AUTHOR_NAME=DSH Agent' "$log" || fail "default author name"
grep -q -- 'GIT_AUTHOR_EMAIL=dsh-agent@localhost' "$log" || fail "default author email"

run_launcher "$project"
[[ $(volume_of) == "$volume" ]] || fail "volume name is not stable"

other="$tmp/other-project"
mkdir -p "$other"
run_launcher "$other"
[[ $(volume_of) != "$volume" ]] || fail "different projects share a volume"

same_a="$tmp/a/shared"
same_b="$tmp/b/shared"
mkdir -p "$same_a" "$same_b"
run_launcher "$same_a"
vol_a=$(volume_of)
run_launcher "$same_b"
vol_b=$(volume_of)
[[ $vol_a != "$vol_b" ]] || fail "same-named projects share a volume"

: >"$log"
out=$(cd "$project" && PATH="$bin:$PATH" DOCKER_LOG="$log" "$root/dsh-anywhere" 2>&1)
expect "$out" "Workspace: /workspace" "default directory"
grep -q -- "src=${project},dst=/workspace" "$log" || fail "default directory mount missing"
grep -q -- '--entrypoint sh' "$log" || fail "credentials migration not attempted"
grep -q -- '/dsh-legacy' "$log" || fail "legacy credentials source missing"

for flag in -p --port -v --volume -C --project -i --image --build --no-build --pull --env-file --name --memory --credentials-volume --open --no-open --dry-run -V --version; do
  if "$root/dsh-anywhere" "$flag" x >/dev/null 2>&1; then
    fail "removed option accepted: $flag"
  fi
done

if "$root/dsh-anywhere" --definitely-not-a-flag >/dev/null 2>&1; then
  fail "unknown option accepted"
fi

printf 'ok\n'
