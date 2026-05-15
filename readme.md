# n9-build

Docker image with the Nokia Harmattan SDK (Qt 4.7 + Qt Mobility + Qt Components),
preconfigured for cross-compiling Qt apps into `armel` `.deb` packages
installable on the Nokia N9.

Image: [`mpwsh/n9-build`](https://hub.docker.com/r/mpwsh/n9-build) (~1.8GB, public)

## What's inside

- Ubuntu 20.04 base
- Qt SDK 1.2.1 (offline installer) with these components:
  - `madde` cross-build tool + Harmattan target `harmattan_10.2011.34-1_rt1.2`
  - 2009q3-67 ARM toolchain (gcc 4.4.1 for `arm-none-linux-gnueabi`)
  - Qt 4.7.4 sysroot for Harmattan
  - Qt Components for Harmattan
  - Qt Mobility 1.2.1 (sensors, systeminfo, location, etc.)
- `dpkg-buildpackage` and friends for producing `.deb` packages
- An `n9` wrapper script at `/usr/local/bin/n9` that runs the build for you

The non-essential SDK bits (simulator, Qt Creator IDE, desktop Qt, docs,
examples, Symbian tools) are stripped out to keep the image small.

## Quick start

You'll need a Qt project with a `.pro` file and a `qtc_packaging/debian_harmattan/`
directory (the standard Qt Creator "Mobile Qt Application" template gives you
both). From the project root:

```bash
docker run --rm \
  -v "$PWD:/work" \
  -w /work \
  mpwsh/n9-build \
  n9 build --path /work
```

You'll find the `.deb` at `build/<app>_<version>_armel.deb`.

Copy it to the phone (USB, SCP, sideload from a web download) and install:

```bash
devel-su
dpkg -i your-app_1.0.0_armel.deb
```

## What `n9 build` does

The wrapper script (full source: [`n9.sh`](./n9.sh)) basically runs:

```bash
mad -t harmattan_10.2011.34-1_rt1.2 qmake your-app.pro -r -spec linux-g++-maemo
mad -t harmattan_10.2011.34-1_rt1.2 make -j4
cp -r qtc_packaging/debian_harmattan debian
mad dpkg-buildpackage -nc -uc -us
```

If you want to run the steps yourself instead of using `n9 build`, drop into
a shell:

```bash
docker run --rm -it -v "$PWD:/work" -w /work mpwsh/n9-build bash
```

## Project structure expected

```
your-project/
├── your-project.pro
├── main.cpp
├── ... source files ...
└── qtc_packaging/
    └── debian_harmattan/
        ├── control          # Package metadata
        ├── changelog        # Version history (dpkg-buildpackage reads version from here)
        ├── rules            # debhelper rules (usually unchanged from Qt Creator template)
        ├── compat
        ├── copyright
        ├── manifest.aegis   # Aegis security manifest (cap requests)
        └── your-app.desktop # Launcher entry
```

## Aegis caveat

Packages that request restricted Aegis caps (most things that touch sensors,
location, cellular, network) will install on phones with Aegis Open Mode
enabled but won't install on stock firmware. See the
[Aegis Installer guide](https://n9.mpw.sh/guides/install-aegis-hack) for how to enable it.

## Use in CI

See [`n9-sensorscope`](https://github.com/mpwsh/n9-sensorscope) for a complete
example of using this image in GitHub Actions to build a `.deb` on tag push
and attach it to a release.

## Building the image yourself

```bash
git clone https://github.com/mpwsh/n9-build
cd n9-build
docker build -t mpwsh/n9-build .
```

The Qt SDK installer (~750MB zip) is fetched from `https://n9.mpw.sh/browse/`
at build time, so you don't need to source it separately.

## License

The image bundles Nokia's Qt SDK 1.2.1, distributed under its original
licenses (LGPL for Qt, BSD/MIT for various components). This repository's
own scripts are MIT.
