#!/usr/bin/env bash
###############################################################################
#  Zenith Linux — construcción de imagen y medios de arranque
#
#  Se ejecuta DENTRO de WSL2 (Ubuntu) o en cualquier Linux con Podman.
#  Requiere Podman y, para ISO/VMDK, bootc-image-builder.
#
#  Uso:
#    ./build.sh check      comprueba el entorno (podman, disco, red, loop)
#    ./build.sh image      construye la imagen OCI
#    ./build.sh lint       imagen + "bootc container lint" (validación)
#    ./build.sh verify     imagen + comprobación del escritorio en un contenedor
#    ./build.sh vmdk       imagen + disco VMDK (VirtualBox)
#    ./build.sh iso        imagen + ISO de instalación (Anaconda/bootc)
#    ./build.sh qcow2      imagen + disco QCOW2 (QEMU/KVM)
#    ./build.sh all        imagen + VMDK + ISO
#
#  Variables:
#    IMAGE            nombre:tag de la imagen (ghcr.io/wwwnone/zenith-linux:latest)
#    FEDORA_VERSION   44
#    CAELESTIA_REF    v2.6.3
#    WITH_NVIDIA      true|false
#    PODMAN           "sudo podman" (por defecto) o "podman"
#    SKIP_IMAGE       1 = no reconstruir; usa la imagen existente (lint, verify,
#                     vmdk, qcow2, raw, iso, all)
###############################################################################
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE="${IMAGE:-ghcr.io/wwwnone/zenith-linux:latest}"
FEDORA_VERSION="${FEDORA_VERSION:-44}"
CAELESTIA_REF="${CAELESTIA_REF:-v2.6.3}"
WITH_NVIDIA="${WITH_NVIDIA:-true}"
PODMAN="${PODMAN:-sudo podman}"
BIB_IMAGE="${BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"
TARGET="${1:-image}"
# SKIP_IMAGE=1 omite la reconstrucción y trabaja con la imagen ya existente.
# Útil para iterar sobre lint/verify o para generar VMDK/ISO sin recompilar.
SKIP_IMAGE="${SKIP_IMAGE:-0}"

build_image() {
    if [[ "$SKIP_IMAGE" == "1" ]]; then
        echo "==> SKIP_IMAGE=1: se usa la imagen existente $IMAGE"
        return 0
    fi
    echo "==> Construyendo $IMAGE (Fedora $FEDORA_VERSION, Caelestia $CAELESTIA_REF, NVIDIA=$WITH_NVIDIA)"
    $PODMAN build \
        --build-arg "FEDORA_VERSION=$FEDORA_VERSION" \
        --build-arg "CAELESTIA_REF=$CAELESTIA_REF" \
        --build-arg "WITH_NVIDIA=$WITH_NVIDIA" \
        -t "$IMAGE" .
}

build_media() {
    local type="$1"
    mkdir -p output
    if [[ ! -e /dev/loop-control ]]; then
        echo "AVISO: no existe /dev/loop-control. bootc-image-builder (osbuild) suele" >&2
        echo "       necesitarlo; en WSL2 puede fallar. Si ocurre, construye la imagen" >&2
        echo "       aquí y ejecuta bootc-image-builder en una VM Linux o en hardware." >&2
    fi
    echo "==> Generando $type con bootc-image-builder"
    $PODMAN run --rm --privileged \
        --security-opt label=disable \
        --pull=newer \
        -v "$PWD/output:/output" \
        -v "$PWD/iso/config.toml:/config.toml:ro" \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        "$BIB_IMAGE" \
        build \
        --type "$type" \
        --config /config.toml \
        "$IMAGE"
    # bib escribe como root; devolver la propiedad al usuario de WSL.
    if [[ "$PODMAN" == sudo* ]]; then
        sudo chown -R "$(id -u):$(id -g)" output || true
    fi
    echo "==> Listo. Resultado en: $(pwd)/output"
    find output -maxdepth 3 -type f \( -name '*.iso' -o -name '*.vmdk' -o -name '*.qcow2' -o -name '*.raw' \) -printf '    %p (%s)\n' || true
}

case "$TARGET" in
    check)
        exec bash scripts/preflight.sh
        ;;
    image)
        build_image
        ;;
    lint)
        build_image
        echo "==> bootc container lint"
        $PODMAN run --rm --entrypoint bootc "$IMAGE" container lint
        ;;
    verify)
        build_image
        echo "==> Comprobación del escritorio dentro de la imagen"
        IMAGE="$IMAGE" PODMAN="$PODMAN" WITH_NVIDIA="$WITH_NVIDIA" \
            bash scripts/verify-image.sh "$IMAGE"
        ;;
    iso|vmdk|qcow2|raw)
        build_image
        build_media "$TARGET"
        ;;
    all)
        build_image
        build_media vmdk
        build_media iso
        ;;
    *)
        echo "Uso: $0 [check|image|lint|verify|vmdk|qcow2|raw|iso|all]" >&2
        exit 1
        ;;
esac
