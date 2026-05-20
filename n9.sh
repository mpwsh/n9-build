#!/bin/bash
#
# n9 — build + deploy Qt projects to a Nokia N9.
#
# One script, three contexts:
#   1. Host without QtSDK   → builds inside the mpwsh/n9-build container
#   2. Host with QtSDK      → builds locally (faster, no Docker needed)
#   3. Inside the container → builds locally (the container has QtSDK)
#
# Auto-detects which mode to use. To force Docker mode, set N9_FORCE_DOCKER=1.
#
# Device deployment (setup/send/run/ssh) always runs on the host using ssh.
#
# The dev key (~/.ssh/n9-developer) is RSA without a passphrase. The N9's
# 2012-era ssh only speaks ssh-rsa, so ed25519 won't work.

set -euo pipefail

# --- Config ---

QTSDK_ROOT="/opt/QtSDK"
QTSDK_TARGET="harmattan_10.2011.34-1_rt1.2"
QTSDK_SYSROOT="harmattan_sysroot_10.2011.34-1_slim"

KEY_PATH="${HOME}/.ssh/n9-developer"
DEVICE_USER="developer"
BUILD_IMAGE="mpwsh/n9-build:latest"

SSH_OPTS=(
  -i "${KEY_PATH}"
  -o "PubkeyAcceptedKeyTypes=+ssh-rsa"
  -o "HostKeyAlgorithms=+ssh-rsa"
  -o "StrictHostKeyChecking=accept-new"
  -o "UserKnownHostsFile=${HOME}/.ssh/known_hosts"
)

# --- Logging ---

log() { printf '[n9] %s\n' "$*" >&2; }
die() {
  printf '[n9] error: %s\n' "$*" >&2
  exit 1
}

# --- Detection ---

# Returns 0 if a usable local QtSDK is present.
have_local_qtsdk() {
  [ -x "${QTSDK_ROOT}/Madde/bin/mad" ] &&
    [ -d "${QTSDK_ROOT}/Madde/sysroots/${QTSDK_SYSROOT}" ] &&
    [ -x "${QTSDK_ROOT}/Madde/targets/${QTSDK_TARGET}/bin/gcc" ]
}

# Returns 0 if a command is available on PATH.
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# --- Prerequisite checks per command ---

check_build_prereqs() {
  if [[ -n "${N9_FORCE_DOCKER:-}" ]] || ! have_local_qtsdk; then
    have_cmd docker || die "neither local QtSDK at ${QTSDK_ROOT} nor docker found — install one"
  fi
}

check_device_prereqs() {
  have_cmd ssh || die "ssh not found on PATH"
  have_cmd scp || die "scp not found on PATH"
}

check_setup_prereqs() {
  check_device_prereqs
  have_cmd ssh-keygen || die "ssh-keygen not found on PATH"
  have_cmd ssh-copy-id || die "ssh-copy-id not found on PATH"
}

# --- Usage ---

usage() {
  cat >&2 <<EOF
n9 — build + deploy Qt projects to a Nokia N9

Commands:
  setup --device <ip>                One-time: generate dev key, copy to phone
  build --path <dir> [--release]     Build the .deb (local or via Docker)
  send  --path <dir> --device <ip>   Build + scp + install (no launch)
  run   --path <dir> --device <ip>   Build + scp + install + launch
  ssh   --device <ip>                Open SSH session to the phone

Build mode is auto-detected:
  * local QtSDK at ${QTSDK_ROOT}  → build locally
  * otherwise                         → build in ${BUILD_IMAGE}

Override with N9_FORCE_DOCKER=1 to always use Docker.

The phone's developer password is shown in:
  Settings → Security → Developer mode → SDK Connection
EOF
}

# --- Arg parsing ---

DEVICE=""
PROJECT_PATH=""
BUILD_TYPE="debug"
CMD="${1:-}"
if [[ -z "${CMD}" || "${CMD}" == "-h" || "${CMD}" == "--help" || "${CMD}" == "help" ]]; then
  usage
  [[ -z "${CMD}" ]] && exit 1 || exit 0
fi
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
  --device)
    DEVICE="$2"
    shift 2
    ;;
  --path)
    PROJECT_PATH="$2"
    shift 2
    ;;
  --release)
    BUILD_TYPE="release"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

require_device() {
  [[ -n "${DEVICE}" ]] || die "this command requires --device <ip>"
}

require_path() {
  [[ -n "${PROJECT_PATH}" ]] || die "this command requires --path <dir>"
  [[ -d "${PROJECT_PATH}" ]] || die "no such directory: ${PROJECT_PATH}"
  PROJECT_PATH="$(cd "${PROJECT_PATH}" && pwd)"
}

require_key() {
  [[ -f "${KEY_PATH}" ]] || die "no key at ${KEY_PATH} — run 'n9 setup --device <ip>' first"
}

# --- Build logic (used by build_local and build_docker) ---

# The actual build steps. Assumes:
#   * CWD is the project root with a .pro file
#   * /opt/QtSDK is the active QtSDK (true locally if detected, true in container)
#
# This is the function that runs inside the container and on a host that has
# QtSDK installed — same code, same result.
do_build() {
  local project_path="$1"
  local build_type="$2"

  cd "${project_path}"

  local pro_file
  pro_file="$(find . -maxdepth 1 -name '*.pro' | head -1)"
  [[ -n "${pro_file}" ]] || die "no .pro file in ${project_path}"

  local project_name
  project_name="$(basename "${pro_file}" .pro)"

  log "building ${project_name} (${build_type})"

  local mad="${QTSDK_ROOT}/Madde/bin/mad"
  local target_gcc="${QTSDK_ROOT}/Madde/targets/${QTSDK_TARGET}/bin/gcc"
  local target_gpp="${QTSDK_ROOT}/Madde/targets/${QTSDK_TARGET}/bin/g++"

  "${mad}" -t "${QTSDK_TARGET}" make clean 2>/dev/null || true
  rm -rf debian

  "${mad}" -t "${QTSDK_TARGET}" qmake \
    "${pro_file}" \
    -r -spec linux-g++-maemo \
    CONFIG+="${build_type}" \
    QMAKE_CXX="${target_gpp}" \
    QMAKE_CC="${target_gcc}"

  "${mad}" -t "${QTSDK_TARGET}" make -j4

  if [[ -d "qtc_packaging/debian_harmattan" ]]; then
    cp -r qtc_packaging/debian_harmattan debian
    chmod +x debian/rules
  fi

  if [[ -d "debian" ]]; then
    "${mad}" dpkg-buildpackage -nc -uc -us
    local version
    version="$(head -1 debian/changelog | sed 's/.*(\(.*\)).*/\1/')"
    local deb_file="../${project_name}_${version}_armel.deb"

    mkdir -p build
    cp "${deb_file}" build/ 2>/dev/null || true
    cp "${project_name}" build/ 2>/dev/null || true
    log "✓ built build/$(basename "${deb_file}")"
  else
    log "no debian directory — binary-only build"
    mkdir -p build
    cp "${project_name}" build/ 2>/dev/null || true
  fi
}

build_local() {
  log "using local QtSDK at ${QTSDK_ROOT}"
  do_build "${PROJECT_PATH}" "${BUILD_TYPE}"
}

build_docker() {
  log "using ${BUILD_IMAGE}"
  # Resolve the absolute path to this script in a portable way.
  # `readlink -f` is GNU-only; BSD/macOS readlink behaves differently.
  local self
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  # Docker Desktop on macOS only file-shares /Users, /Volumes, /tmp,
  # /private by default. If n9 is installed in /usr/local/bin (or
  # /opt/homebrew/bin, etc.), Docker can't see the source file and
  # silently treats the mount target as a directory.
  # Stage a copy in /tmp which is always shared.
  local staged
  staged="$(mktemp -t n9-script)"
  cp "${self}" "${staged}"
  chmod +x "${staged}"
  trap "rm -f '${staged}'" EXIT
  # We re-exec this same script inside the container. The container has
  # /opt/QtSDK, so the script's auto-detection picks the local path
  # and runs do_build directly — no recursion, no separate build script.
  docker run --rm \
    --platform linux/amd64 \
    -v "${PROJECT_PATH}:/work" \
    -v "${staged}:/usr/local/bin/n9:ro" \
    -w /work \
    "${BUILD_IMAGE}" \
    n9 build --path /work $([[ "${BUILD_TYPE}" == "release" ]] && echo "--release")
}

# --- Subcommands ---

cmd_setup() {
  check_setup_prereqs
  require_device

  if [[ ! -f "${KEY_PATH}" ]]; then
    log "generating dev key at ${KEY_PATH}"
    ssh-keygen -t rsa -b 2048 -N "" -C "n9-developer@$(hostname -s)" -f "${KEY_PATH}"
  else
    log "key already exists at ${KEY_PATH}"
  fi

  log "copying public key to ${DEVICE_USER}@${DEVICE}"
  log "you'll be prompted for the phone's developer-mode password"

  ssh-copy-id \
    -i "${KEY_PATH}.pub" \
    -o "PubkeyAcceptedKeyTypes=+ssh-rsa" \
    -o "HostKeyAlgorithms=+ssh-rsa" \
    -o "StrictHostKeyChecking=accept-new" \
    "${DEVICE_USER}@${DEVICE}"

  log "verifying key works"
  if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${DEVICE_USER}@${DEVICE}" "echo ok" >/dev/null 2>&1; then
    log "✓ key authentication working — ready to deploy"
  else
    die "key auth still failing — manual cleanup may be needed on the phone"
  fi
}

cmd_build() {
  check_build_prereqs
  require_path

  if [[ -z "${N9_FORCE_DOCKER:-}" ]] && have_local_qtsdk; then
    build_local
  else
    build_docker
  fi
}

find_built_deb() {
  local deb
  deb="$(find "${PROJECT_PATH}/build" -maxdepth 1 -name '*.deb' 2>/dev/null | head -n1)"
  [[ -n "${deb}" ]] || die "no .deb in ${PROJECT_PATH}/build — run 'n9 build' first"
  printf '%s' "${deb}"
}

deb_to_app_name() {
  basename "$1" | sed -E 's/_[^_]+_[^_]+\.deb$//'
}

cmd_send() {
  check_device_prereqs
  require_path
  require_device
  require_key

  log "(re)building to pick up any code changes"
  cmd_build

  local deb deb_remote
  deb="$(find_built_deb)"
  deb_remote="/tmp/$(basename "${deb}")"

  log "scp $(basename "${deb}") → ${DEVICE}:${deb_remote}"
  scp "${SSH_OPTS[@]}" "${deb}" "${DEVICE_USER}@${DEVICE}:${deb_remote}"

  log "installing on phone (devel-su needs the developer-mode password)"
  ssh "${SSH_OPTS[@]}" -t "${DEVICE_USER}@${DEVICE}" \
    "devel-su -c 'dpkg -i ${deb_remote}'"
}

cmd_run() {
  cmd_send

  local deb app_name binary_path
  deb="$(find_built_deb)"
  app_name="$(deb_to_app_name "${deb}")"
  binary_path="/opt/${app_name}/bin/${app_name}"

  log "launching ${app_name}"

  ssh "${SSH_OPTS[@]}" "${DEVICE_USER}@${DEVICE}" "
        if file '${binary_path}' | grep -q 'shared object'; then
            echo '[phone] launching via invoker --type=e'
            invoker --single-instance --type=e '${binary_path}' &
        else
            echo '[phone] launching directly'
            '${binary_path}' &
        fi
        disown
    " || log "(launch backgrounded on phone; SSH session closed)"
}

cmd_ssh() {
  check_device_prereqs
  require_device
  require_key
  log "ssh ${DEVICE_USER}@${DEVICE}"
  exec ssh "${SSH_OPTS[@]}" "${DEVICE_USER}@${DEVICE}"
}

# --- Dispatch ---

case "${CMD}" in
setup) cmd_setup ;;
build) cmd_build ;;
send) cmd_send ;;
run) cmd_run ;;
ssh) cmd_ssh ;;
*) die "unknown command: ${CMD} (try 'n9 --help')" ;;
esac
