# n9

Build and deploy Qt projects for the Nokia N9.

## What this is

A single bash script that handles the full build-and-deploy loop for N9 apps:

- Builds armel `.deb` packages from Qt projects
- Auto-detects whether a local Qt SDK is installed (uses it if so) or falls
  back to the [`mpwsh/n9-build`](https://hub.docker.com/r/mpwsh/n9-build)
  Docker image
- Deploys to a phone over SSH using a dedicated dev key
- Same script works on your host and inside the Docker image — no separate
  builder tool

## Install

```bash
sudo install -m 0755 n9.sh /usr/local/bin/n9
```

Requires `bash`, `docker` (or a local Qt SDK at `/opt/QtSDK`), `ssh`,
`scp`, `ssh-keygen`, `ssh-copy-id`. All commonly preinstalled on Linux/macOS.

## First-time setup

1. Enable Developer Mode on the phone:
   - Settings → Security → Developer mode → ON
   - Note the password under "SDK Connection"
   - Note the phone's IP (USB: usually `192.168.2.15`; WiFi: varies)

2. Copy your dev key to the phone:

   ```bash
   n9 setup --device 192.168.2.15
   ```

   Generates `~/.ssh/n9-developer` if needed, then prompts once for the
   developer-mode password to install it.

## Daily use

```bash
# Build .deb (auto-detects local Qt vs Docker)
n9 build --path .

# Build + scp + install on the phone
n9 send --path . --device 192.168.2.15

# Build + install + auto-launch
n9 run --path . --device 192.168.2.15

# Quick shell to the phone
n9 ssh --device 192.168.2.15
```

`devel-su` will still prompt for the developer password each `send`/`run` —
that's the privilege-escalation step on the phone, separate from SSH auth.

## Build mode auto-detection

| Condition                                | Build mode |
| ---------------------------------------- | ---------- |
| `/opt/QtSDK/Madde/bin/mad` is executable | Local      |
| Otherwise                                | Docker     |
| `N9_FORCE_DOCKER=1` in env               | Docker     |

The same script runs inside the [`mpwsh/n9-build`](https://hub.docker.com/r/mpwsh/n9-build)
image, where it picks the local path because the SDK is installed at
`/opt/QtSDK` inside the container.

## Project structure expected

```
your-project/
├── your-project.pro
├── main.cpp
├── ... source files ...
└── qtc_packaging/
    └── debian_harmattan/
        ├── control          # Package metadata
        ├── changelog        # Version (the .deb's version comes from here)
        ├── rules            # debhelper rules
        ├── compat
        ├── copyright
        ├── manifest.aegis   # Aegis caps the app requests
        └── your-app.desktop # Launcher entry
```

The `.deb` lands in `build/<app>_<version>_armel.deb`.

## Use in CI

GitHub Actions can drive this with no host-side install — just pull the
image and call the same script:

```yaml
- name: Build .deb
  run: |
    docker run --rm \
      -v "$PWD:/work" \
      -w /work \
      mpwsh/n9-build \
      n9 build --path /work
```

See [`n9-sensorscope`](https://github.com/mpw/n9-sensorscope) for a complete
release workflow.

## Aegis caveat

Apps requesting Aegis capabilities (sensors, location, network, cellular)
install cleanly on phones with Aegis Open Mode enabled but won't fully
install on stock firmware. See the
[Aegis Installer guide](https://n9.mpw.sh/docs/aegis) for setup.

## License

MIT.
