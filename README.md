# dsh-anywhere

Run DeepSeek Harness in Docker from any directory.

```sh
dsh-anywhere ~/src/myproject
```

The directory is mounted at `/workspace`. Each canonical directory gets its own
settings volume; one credentials volume is shared by every project, so the API
key is entered once.

## Requirements

- Docker 20.10+
- bash
- python3 to pick a free port
- internet access for the first image build (the image installs DSH)

Linux and macOS (Docker Desktop). Windows/WSL is untested.

## What you get

- **First run.** Enter the API key once. DSH stores it in
  `dsh-anywhere-credentials` and creates the `/workspace` workspace
  automatically.
- **Same directory again.** Its settings volume reopens the previous workspace
  and sessions.
- **New directory.** A new settings volume, the same API key, and an
  automatically created `/workspace` workspace.
- **Several copies.** `dsh-anywhere ~/src/a` and `dsh-anywhere ~/src/b` can run
  at the same time with separate sessions and one shared key.
- **Running.** The launcher stays in the foreground. The container prints the
  browser URL/token link in the console; press Ctrl-C to stop and remove it.

## Options

```text
Usage: dsh-anywhere [DIRECTORY]

  -h, --help             this help
```

Without `DIRECTORY`, the current directory is used. The launcher runs in the
foreground: press Ctrl-C to stop, and click the browser URL/token link the
container prints in the console. On every run it builds `dsh-anywhere:latest`
from this repository's Dockerfile (Docker reuses layers) and then starts it; it
does not pull images. To use another tag, change `IMAGE` at the top of
`dsh-anywhere`.

## How it works

1. **Image.** Every run builds the image from this repository's `Dockerfile`
   (Docker reuses layers; the first build installs `@deepseek-ai/dsh` on
   `node:24-bookworm-slim`). The image also contains `entrypoint.sh` and the
   `profile.yml` overlay.
2. **Project volume.** A volume named `dsh-anywhere-<folder>-<checksum>` is
   mounted at `/dsh`, with `HOME`/`DSH_HOME` at `/dsh/home`. Profiles, session
   history, and the workspace registry live there.
3. **Credentials volume.** `dsh-anywhere-credentials` is mounted at
   `/dsh-credentials`; `profile.yml` points DSH's credentials store there. The
   API keys and the browser-session signing secret are shared by every project.
4. **Workspace.** The project is mounted at `/workspace`. The image points
   `/dsh-defaults/deepseek-harness/default-workspace` at `/workspace`, so a
   fresh project volume registers it automatically.
5. **Runtime.** A free loopback port, a read-only rootfs, capability drop,
   no-new-privileges, a 4 GiB memory limit, and the host uid/gid.

## Git identity

Commits use `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, and
`GIT_COMMITTER_EMAIL` from the launcher's environment when set. Otherwise the
project's `user.name` and `user.email` git config is used, with
`DSH Agent <dsh-agent@localhost>` as the final fallback.

## Volumes

Each canonical directory gets its own settings volume. The launcher prints its
name as `Settings: volume ...`:

```sh
vol=dsh-anywhere-myapp-1234567890   # from the launcher's "Settings: volume" line
docker volume inspect "$vol"
docker run --rm -v "$vol":/dsh -v "$PWD":/backup alpine \
  tar -C /dsh -czf /backup/dsh-home.tgz .
```

The credentials volume is shared by every project:

```sh
docker volume inspect dsh-anywhere-credentials
docker run --rm -v dsh-anywhere-credentials:/credentials -v "$PWD":/backup alpine \
  tar -C /credentials -czf /backup/dsh-credentials.tgz .
```

Treat that archive as a secret. To start the key store over, remove the volume
(`docker volume rm dsh-anywhere-credentials`) or change the key in the Models
page.

On first use, the launcher carries an existing API key from the old
`dsh-anywhere-home` volume (or from this project's previous volume) into
`dsh-anywhere-credentials`. Sessions in the old shared volume are not opened by
the launcher; only the key is copied.

## Multiple copies

```sh
dsh-anywhere ~/src/a
dsh-anywhere ~/src/b
docker ps --filter label=dsh.anywhere=1
docker logs -f dsh-anywhere-...
docker rm -f dsh-anywhere-...
```

The two projects get separate settings volumes and session lists. They share
`dsh-anywhere-credentials`, so the key is entered only once. Two containers for
the *same* project share that project's volume and therefore its `/workspace`
workspace and session history.

## Security

- The port is published on `127.0.0.1` only; use an SSH tunnel for remote access.
- The token link is a one-time login; do not forward it.
- The credentials volume and project volumes may contain secrets.
- Read-only root filesystem, capability drop, no-new-privileges, and the host
  uid/gid.

## Limitations

- **Shared workspace within a volume.** Every project is mounted at
  `/workspace`. Different projects get different volumes, but two containers for
  the same project share its `/workspace` workspace and session list. Resuming a
  session while a different host directory is mounted at `/workspace` points its
  tools at that directory.
- **First run.** The first run asks for the API key once, stores it in
  `dsh-anywhere-credentials`, and creates the `/workspace` workspace
  automatically. A new project volume also creates its workspace automatically.
- **Automatic workspace title.** That workspace is titled "Default workspace"
  and points at `/workspace`; rename it once if you want the folder name. The
  title persists in the project volume.
- **Moving a project.** The volume name is derived from the absolute path, so
  moving or renaming the project directory gives it a new volume. The old volume
  is left untouched and is not opened by the launcher.
- **Simultaneous start on one volume.** DSH rewrites
  `profiles/web/cordis.yml` during boot; do not start two copies at exactly the
  same moment.
- **Volume ownership.** The volumes belong to the uid that created them. If the
  container fails with `EACCES` on `/dsh/home`, align the project volume:
  `docker run --rm -v <volume>:/dsh alpine chown -R "$(id -u):$(id -g)" /dsh`.
  Do the same for `dsh-anywhere-credentials:/dsh-credentials` if the key cannot
  be written.

## Development

```sh
make image   # build dsh-anywhere:latest
make test    # bash -n and tests/smoke.sh
make lint    # shellcheck
make install # symlink into ~/.local/bin
```

Layout: `dsh-anywhere` is the launcher, `entrypoint.sh` starts `dsh web` in the
container, `profile.yml` wires the shared credentials and automatic workspace,
and `tests/smoke.sh` covers checks that need no Docker.

## License

MIT — see [LICENSE](LICENSE).
