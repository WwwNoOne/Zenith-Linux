#!/usr/bin/env bash
# Zenith Linux — prepara una Ubuntu de WSL2 (o un Linux normal) para construir.
#
#   bash scripts/wsl-bootstrap.sh
#
# Instala Podman y comprueba lo que zenith necesita. No construye nada.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Aviso: esto no parece WSL2; se instalan las mismas dependencias igualmente."
    IN_WSL=false
else
    IN_WSL=true
fi

echo "==> Instalando Podman y utilidades"
sudo apt-get update
sudo apt-get install -y podman uidmap slirp4netns fuse-overlayfs curl ca-certificates

if $IN_WSL; then
    echo
    echo "==> Intentando habilitar /dev/loop-control (lo necesita bootc-image-builder)"
    sudo modprobe loop 2>/dev/null || true
    if [[ -e /dev/loop-control ]]; then
        echo "    /dev/loop-control disponible"
    else
        cat <<'EOF'
    No aparece /dev/loop-control en este kernel de WSL2.
    La imagen OCI se puede construir igualmente; para ISO/VMDK hay dos salidas:
      - ejecutar bootc-image-builder en una VM Linux o en hardware real, o
      - usar `./build.sh vmdk` desde una distro WSL con kernel loop completo.
EOF
    fi
fi

echo
echo "==> Comprobando Podman rootful"
if sudo -n true 2>/dev/null; then
    sudo podman info --format '    root:   {{.Store.GraphRoot}}
    driver: {{.Store.GraphDriverName}}'
else
    echo "    sudo pide contraseña; se comprobará al construir (PODMAN='sudo podman')."
fi

echo
echo "Podman: $(podman --version)"
echo
echo "Siguiente paso:  ./build.sh check   (verifica red, disco y entorno)"
echo "Después:         ./build.sh image"
