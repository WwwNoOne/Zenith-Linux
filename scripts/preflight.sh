#!/usr/bin/env bash
# Zenith Linux — comprobación previa del entorno de construcción.
#
# No construye nada: verifica que la máquina (WSL2 o Linux) puede hacerlo y
# explica en castellano qué falta. Se ejecuta con `./build.sh check`.
#
# Códigos de salida: 0 = todo listo, 1 = falta algo imprescindible.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PODMAN="${PODMAN:-sudo podman}"
FEDORA_VERSION="${FEDORA_VERSION:-44}"
CAELESTIA_REF="${CAELESTIA_REF:-v2.6.3}"
IMAGE="${IMAGE:-ghcr.io/wwwnone/zenith-linux:latest}"

FAIL=0
WARN=0

ok()    { printf '  [ OK ]   %s\n' "$*"; }
info()  { printf '  [info]   %s\n' "$*"; }
warn()  { printf '  [AVISO]  %s\n' "$*"; WARN=$((WARN + 1)); }
fail()  { printf '  [ERROR]  %s\n' "$*"; FAIL=$((FAIL + 1)); }
title() { printf '\n== %s ==\n' "$*"; }

title "Sistema"
if [[ "$(uname -s)" == "Linux" ]]; then
    ok "$(uname -sr)"
else
    fail "esto no es Linux; ejecuta el script dentro de WSL2 o de una máquina Linux"
fi

if grep -qi microsoft /proc/version 2>/dev/null; then
    info "WSL2 detectado"
    if [[ ! -e /dev/loop-control ]]; then
        warn "no existe /dev/loop-control: la imagen OCI se puede construir,"
        warn "pero bootc-image-builder (ISO/VMDK) probablemente falle. Prueba:"
        warn "    sudo modprobe loop && ls -l /dev/loop-control"
        warn "Si sigue sin aparecer, genera los medios en otra VM/hardware Linux."
    else
        ok "/dev/loop-control presente"
    fi
fi

for cmd in bash curl tar gzip; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd: $(command -v "$cmd")"
    else
        fail "falta $cmd"
    fi
done

title "Podman"
if command -v podman >/dev/null 2>&1; then
    ok "podman $(podman --version | awk '{print $3}')"
    if $PODMAN info >/dev/null 2>&1; then
        ok "'$PODMAN info' funciona"
        info "almacén: $($PODMAN info --format '{{.Store.GraphRoot}}' 2>/dev/null || echo '?')"
        info "driver : $($PODMAN info --format '{{.Store.GraphDriverName}}' 2>/dev/null || echo '?')"
    elif [[ "$PODMAN" == sudo* ]]; then
        if sudo -n true 2>/dev/null; then
            fail "'$PODMAN info' falla; revisa la instalación de Podman"
        else
            warn "sudo pide contraseña: no se pudo comprobar '$PODMAN info'"
            info "se usará '$PODMAN'; introduce la contraseña al construir"
        fi
    else
        warn "'$PODMAN info' falla; si usas Podman sin root, exporta PODMAN=podman"
    fi
else
    fail "falta podman: bash scripts/wsl-bootstrap.sh (en Ubuntu/WSL2)"
fi

title "Disco"
avail_kb=$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -n "${avail_kb:-}" ]]; then
    avail_gb=$((avail_kb / 1024 / 1024))
    if (( avail_gb >= 25 )); then
        ok "$avail_gb GiB libres aquí"
    elif (( avail_gb >= 12 )); then
        warn "$avail_gb GiB libres: justo para la imagen (sin ISO ni VMDK)"
    else
        fail "$avail_gb GiB libres: se necesitan ~25 GiB para imagen + medios"
    fi
fi

title "Repositorio"
for f in Containerfile build.sh iso/config.toml files/usr/bin/zenith; do
    if [[ -e "$f" ]]; then ok "$f"; else fail "falta $f"; fi
done
if command -v git >/dev/null 2>&1 && [[ -d .git ]]; then
    info "rama: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
fi

if [[ -f scripts/check-syntax.sh ]]; then
    if bash scripts/check-syntax.sh >/tmp/zenith-check-syntax.log 2>&1; then
        ok "sintaxis de scripts y bloques RUN del Containerfile"
    else
        fail "sintaxis: detalle en /tmp/zenith-check-syntax.log"
    fi
fi

if [[ -f iso/config.toml ]]; then
    if command -v python3 >/dev/null 2>&1 &&
       python3 -c 'import tomllib, sys; tomllib.load(open(sys.argv[1], "rb"))' iso/config.toml >/dev/null 2>&1; then
        ok "iso/config.toml es TOML válido"
    elif command -v python3 >/dev/null 2>&1; then
        fail "iso/config.toml no es TOML válido: bootc-image-builder lo rechazará"
    else
        warn "sin python3: no se pudo validar iso/config.toml"
    fi
fi

title "Red (recursos del build)"
urls=(
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
    "https://flathub.org/repo/flathub.flatpakrepo"
    "https://github.com/ladybug-me/caelestia-kde.git/info/refs?service=git-upload-pack"
    "https://bitbucket.org/dirn-typo/yet-another-monochrome-icon-set/info/refs?service=git-upload-pack"
    "https://github.com/soramanew/m3shapes.git/info/refs?service=git-upload-pack"
    "https://download.copr.fedorainfracloud.org/results/errornointernet/quickshell/fedora-${FEDORA_VERSION}-x86_64/repodata/repomd.xml"
    "https://download.copr.fedorainfracloud.org/results/celestelove/libcava/fedora-${FEDORA_VERSION}-x86_64/repodata/repomd.xml"
    "https://download.copr.fedorainfracloud.org/results/celestelove/app2unit/fedora-${FEDORA_VERSION}-x86_64/repodata/repomd.xml"
    "https://download.copr.fedorainfracloud.org/results/deltacopy/darkly/fedora-${FEDORA_VERSION}-x86_64/repodata/repomd.xml"
    "https://download.copr.fedorainfracloud.org/results/leloubil/wl-clip-persist/fedora-${FEDORA_VERSION}-x86_64/repodata/repomd.xml"
    "https://download.copr.fedorainfracloud.org/results/brycensranch/gpu-screen-recorder-git/fedora-${FEDORA_VERSION}-x86_64/repodata/repomd.xml"
    "https://download.copr.fedorainfracloud.org/results/atim/starship/fedora-${FEDORA_VERSION}-x86_64/repodata/repomd.xml"
    "https://quay.io/v2/fedora/fedora-bootc/manifests/${FEDORA_VERSION}"
    "https://quay.io/v2/centos-bootc/bootc-image-builder/manifests/latest"
)
for u in "${urls[@]}"; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' -L --max-time 25 "$u" 2>/dev/null || echo 000)
    case "$code" in
        200|206|401) ok "$code  ${u#https://}" ;;
        000)         fail "sin respuesta: ${u#https://}" ;;
        *)           fail "$code  ${u#https://}" ;;
    esac
done

title "Resumen"
printf '  imagen:      %s\n' "$IMAGE"
printf '  Fedora:      %s\n' "$FEDORA_VERSION"
printf '  Caelestia:   %s\n' "$CAELESTIA_REF"
printf '  NVIDIA:      %s\n' "${WITH_NVIDIA:-true}"
printf '  avisos:      %s\n' "$WARN"
printf '  errores:     %s\n' "$FAIL"

if (( FAIL > 0 )); then
    printf '\nHay %d problema(s) que impiden construir. Corrígelos y repite.\n' "$FAIL"
    exit 1
fi

printf '\nEntorno listo. Siguiente paso:  ./build.sh image\n'
