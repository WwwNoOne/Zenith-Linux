#!/usr/bin/env bash
# Zenith Linux — verificación de la imagen ya construida.
#
# Arranca un contenedor efímero sobre la imagen y comprueba el contrato del
# escritorio: binarios, sesiones Wayland, unidades de systemd habilitadas,
# tema de SDDM, tipografías, Flatpak y ausencia de repos de COPR.
#
# Complementa las aserciones del Containerfile (que solo miran ficheros) y no
# necesita arrancar la imagen en una máquina virtual.
#
# Uso:  bash scripts/verify-image.sh [imagen]
#       IMAGE=milocal:tag bash scripts/verify-image.sh
#
# Código de salida: 0 = todo correcto, 1 = algún fallo.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

IMAGE="${1:-${IMAGE:-ghcr.io/wwwnone/zenith-linux:latest}}"
PODMAN="${PODMAN:-sudo podman}"
WITH_NVIDIA="${WITH_NVIDIA:-true}"

echo "==> Verificando $IMAGE (NVIDIA=$WITH_NVIDIA)"
echo

$PODMAN run --rm -i --entrypoint /usr/bin/bash \
    -e "NVIDIA_EXPECTED=$WITH_NVIDIA" \
    "$IMAGE" -s <<'CHECK'
set -u

FAIL=0
ok()   { printf '  [ OK ]   %s\n' "$*"; }
bad()  { printf '  [ERROR]  %s\n' "$*"; FAIL=$((FAIL + 1)); }
have() { if [ -e "$1" ]; then ok "existe $1"; else bad "falta $1"; fi; }
exec_() {
    if [ -x "$1" ]; then ok "ejecutable $1"; else bad "no es ejecutable: $1"; fi
}
unit() {
    if systemctl is-enabled --quiet "$1" >/dev/null 2>&1; then
        ok "unidad habilitada: $1"
    else
        bad "unidad NO habilitada: $1"
    fi
}
expect_grep() { # patrón fichero descripción
    if grep -q -- "$1" "$2" 2>/dev/null; then ok "$3"; else bad "$3"; fi
}

echo "== Sistema =="
expect_grep '^ID=zenith$' /usr/lib/os-release 'os-release: ID=zenith'
expect_grep '^PRETTY_NAME="Zenith Linux' /usr/lib/os-release 'os-release: PRETTY_NAME'
if [ -L /etc/os-release ]; then ok '/etc/os-release es enlace simbólico'; else bad '/etc/os-release no es un enlace'; fi
if [ "$(systemctl get-default 2>/dev/null)" = "graphical.target" ]; then
    ok 'target por defecto: graphical.target'
else
    bad "target por defecto: $(systemctl get-default 2>/dev/null)"
fi
exec_ /usr/bin/bootc
exec_ /usr/bin/zenith

echo
echo "== Shell de Caelestia =="
if [ -x /usr/bin/quickshell ]; then ok 'binario /usr/bin/quickshell'; else bad 'falta /usr/bin/quickshell'; fi
have /etc/xdg/quickshell/caelestia/shell.qml
if [ -d /usr/share/plasma/shells/caelestia.desktop ]; then
    ok 'paquete de shell /usr/share/plasma/shells/caelestia.desktop'
else
    bad 'falta /usr/share/plasma/shells/caelestia.desktop'
fi
if [ -n "$(find /usr/lib64/qt6/qml -maxdepth 2 -name 'Caelestia*' -print -quit 2>/dev/null)" ]; then
    ok 'módulos QML de Caelestia instalados'
else
    bad 'sin módulos QML de Caelestia en /usr/lib64/qt6/qml'
fi
if [ -n "$(find /usr/lib64/qt6/qml -maxdepth 2 -name 'Quickshell*' -print -quit 2>/dev/null)" ]; then
    ok 'módulos QML de Quickshell instalados'
else
    bad 'sin módulos QML de Quickshell'
fi
expect_grep '^ShellPackage=caelestia.desktop' /etc/xdg/plasmashellrc 'plasmashellrc apunta a caelestia.desktop'
exec_ /usr/bin/caelestia-autostart
have /usr/lib/systemd/user/caelestia-shell.service
if systemctl --global is-enabled --quiet caelestia-shell.service >/dev/null 2>&1; then
    ok 'unidad de usuario habilitada: caelestia-shell.service'
else
    bad 'caelestia-shell.service no está habilitada globalmente'
fi
exec_ /usr/libexec/zenith/first-login

echo
echo "== Sesión, login y servicios =="
have /usr/share/wayland-sessions/plasma.desktop
exec_ /usr/bin/kwin_wayland
unit sddm.service
have /etc/sddm.conf.d/zz-caelestia.conf
have /usr/share/sddm/themes/caelestia/Main.qml
expect_grep '^Current=caelestia' /etc/sddm.conf.d/zz-caelestia.conf 'SDDM usa el tema caelestia'
expect_grep '^DefaultSession=plasma.desktop' /etc/sddm.conf.d/zz-caelestia.conf 'SDDM arranca la sesión Plasma/KWin'
unit bluetooth.service
unit tuned.service
unit fstrim.timer
if systemctl is-enabled --quiet ydotool.service >/dev/null 2>&1; then
    bad 'ydotool.service del sistema habilitado (debe usarse el demonio de usuario)'
else
    ok 'ydotool.service del sistema NO habilitado (se usa ydotoold de usuario)'
fi
have /usr/lib/udev/rules.d/70-uinput.rules
have /etc/modules-load.d/zenith-uinput.conf

echo
echo "== Apps y sistema base =="
if rpm -q firefox >/dev/null 2>&1; then ok 'Firefox instalado (RPM)'; else bad 'Firefox no instalado'; fi
exec_ /usr/bin/flatpak
have /etc/flatpak/remotes.d/flathub.flatpakrepo
if [ -z "$(find /etc/yum.repos.d -maxdepth 1 -name '_copr*' -print -quit 2>/dev/null)" ]; then
    ok 'sin repos de COPR en la imagen final'
else
    bad 'quedan ficheros _copr*.repo en /etc/yum.repos.d'
fi
have /usr/lib/systemd/system/tuned-ppd.service

echo
echo "== Tipografías =="
for f in /usr/share/fonts/zenith/material-symbols /usr/share/fonts/zenith/cascadia-code /usr/share/fonts/zenith/jetbrains-mono; do
    have "$f"
done
if fc-list 2>/dev/null | grep -qi 'Material Symbols Rounded'; then
    ok 'Material Symbols Rounded registrada en fontconfig'
else
    bad 'Material Symbols Rounded no aparece en fc-list'
fi
if fc-list 2>/dev/null | grep -qi 'CaskaydiaCove Nerd Font'; then
    ok 'CaskaydiaCove Nerd Font registrada en fontconfig'
else
    bad 'CaskaydiaCove Nerd Font no aparece en fc-list'
fi

echo
echo "== NVIDIA =="
if [ "${NVIDIA_EXPECTED:-true}" = "true" ]; then
    if rpm -q akmod-nvidia >/dev/null 2>&1; then ok 'akmod-nvidia instalado'; else bad 'akmod-nvidia no instalado'; fi
    have /usr/lib/bootc/kargs.d/50-zenith-nvidia.toml
    have /etc/modprobe.d/zenith-nvidia.conf
    if compgen -G '/usr/lib/modules/*/extra/nvidia/*.ko*' >/dev/null; then
        ok 'módulos nvidia compilados en el kernel'
    else
        bad 'no hay módulos nvidia en /usr/lib/modules/*/extra/nvidia'
    fi
else
    if rpm -q akmod-nvidia >/dev/null 2>&1; then
        bad 'akmod-nvidia instalado en una imagen WITH_NVIDIA=false'
    else
        ok 'sin akmod-nvidia, como se pidió'
    fi
    if [ -e /usr/lib/bootc/kargs.d/50-zenith-nvidia.toml ]; then
        bad 'quedan kargs de NVIDIA en una imagen sin NVIDIA'
    else
        ok 'sin kargs de NVIDIA'
    fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "RESULTADO: imagen correcta (0 fallos)"
else
    echo "RESULTADO: $FAIL fallo(s)"
fi
exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
CHECK

status=$?
echo
if [ "$status" -eq 0 ]; then
    echo "==> Verificación superada"
else
    echo "==> Verificación FALLIDA" >&2
fi
exit "$status"
