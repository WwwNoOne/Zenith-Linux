#!/usr/bin/env bash
# Zenith Linux — prueba de arranque en QEMU/KVM (alternativa rápida a VirtualBox).
#
# Arranca una imagen de disco generada por bootc-image-builder con firmware
# UEFI (OVMF), captura la pantalla con el monitor de QEMU y permite enviar
# teclas para iniciar sesión. No abre ninguna ventana: las capturas quedan en
# PNG y se pueden abrir con cualquier visor.
#
# Requisitos (solo para pruebas, no para construir la imagen):
#   sudo apt-get install -y qemu-system-x86 ovmf
#   /dev/kvm accesible (WSL2 con virtualización anidada lo expone)
#
# Uso:
#   bash scripts/qemu-boot-test.sh start output/qcow2/disk.qcow2
#   bash scripts/qemu-boot-test.sh shot sddm
#   bash scripts/qemu-boot-test.sh type zenith
#   bash scripts/qemu-boot-test.sh key ret
#   bash scripts/qemu-boot-test.sh shot escritorio
#   bash scripts/qemu-boot-test.sh stop
#
# Variables: RAM (4096), CPUS (4), DIR (output/qemu), SSD (1) añade un disco
# de datos, MON (DIR/monitor.sock).

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RAM="${RAM:-4096}"
CPUS="${CPUS:-4}"
SSD="${SSD:-1}"
DIR="${DIR:-output/qemu}"
MON="$DIR/monitor.sock"
PIDFILE="$DIR/qemu.pid"
CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
VARS_SRC="/usr/share/OVMF/OVMF_VARS_4M.fd"
SSH_PORT="${SSH_PORT:-2222}"

cmd="${1:-}"

err() { echo "error: $*" >&2; exit 1; }

# Envía un comando al monitor de QEMU a través del socket UNIX.
mon() {
    MON="$MON" CMD="$1" python3 - <<'PY'
import os, socket, time
ruta = os.environ["MON"]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(10)
s.connect(ruta)
time.sleep(0.2)
s.sendall((os.environ["CMD"] + "\n").encode())
time.sleep(0.4)
try:
    print(s.recv(65536).decode(errors="replace").strip())
except socket.timeout:
    pass
s.close()
PY
}

# Convierte el PPM que produce QEMU (P6) a PNG sin dependencias externas.
ppm_a_png() {
    PPM="$1" PNG="$2" python3 - <<'PY'
import os, struct, zlib

datos = open(os.environ["PPM"], "rb").read()
if not datos.startswith(b"P6"):
    raise SystemExit("no es un PPM P6")
partes = datos.split(maxsplit=4)
ancho, alto, maxv = int(partes[1]), int(partes[2]), int(partes[3])
pixeles = partes[4]
if maxv != 255:
    pixeles = bytes((v * 255) // maxv for v in pixeles)
fila = ancho * 3
crudo = b"".join(b"\x00" + pixeles[y * fila:(y + 1) * fila] for y in range(alto))

def trozo(tipo, cuerpo):
    return (struct.pack(">I", len(cuerpo)) + tipo + cuerpo
            + struct.pack(">I", zlib.crc32(tipo + cuerpo) & 0xFFFFFFFF))

png = (b"\x89PNG\r\n\x1a\n"
       + trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0))
       + trozo(b"IDAT", zlib.compress(crudo, 6))
       + trozo(b"IEND", b""))
open(os.environ["PNG"], "wb").write(png)
print(f"{os.environ['PNG']} ({ancho}x{alto})")
PY
}

# Traduce un texto a secuencias "sendkey" del monitor.
escribir() {
    local texto="$1" c tecla
    for ((i = 0; i < ${#texto}; i++)); do
        c="${texto:i:1}"
        case "$c" in
            [a-z0-9]) tecla="$c" ;;
            [A-Z]) tecla="shift-$(echo "$c" | tr 'A-Z' 'a-z')" ;;
            ' ') tecla="spc" ;;
            '-') tecla="minus" ;;
            '.') tecla="dot" ;;
            '/') tecla="slash" ;;
            '_') tecla="shift-minus" ;;
            '@') tecla="shift-2" ;;
            *) echo "aviso: carácter no soportado '$c'" >&2; continue ;;
        esac
        mon "sendkey $tecla" >/dev/null
    done
}

case "$cmd" in
    start)
        disco="${2:-}"
        [[ -n "$disco" ]] || err "indica la imagen de disco (raw/qcow2)"
        [[ -f "$disco" ]] || err "no existe $disco"
        command -v qemu-system-x86_64 >/dev/null || err "falta qemu-system-x86_64"
        [[ -e "$CODE" && -e "$VARS_SRC" ]] || err "falta OVMF (apt-get install ovmf)"
        [[ -w /dev/kvm ]] || err "sin acceso a /dev/kvm (se puede usar sin -accel kvm, más lento)"
        mkdir -p "$DIR"
        cp -f "$VARS_SRC" "$DIR/OVMF_VARS.fd"
        case "$disco" in
            *.qcow2) fmt=qcow2 ;;
            *)       fmt=raw ;;
        esac
        extra=()
        if [[ "$SSD" == "1" ]]; then
            qemu-img create -f qcow2 "$DIR/datos.qcow2" 8G >/dev/null
            extra+=(-drive "file=$DIR/datos.qcow2,if=virtio,format=qcow2")
        fi
        qemu-system-x86_64 \
            -name zenith-test \
            -accel kvm -machine q35 -cpu host -smp "$CPUS" -m "$RAM" \
            -drive if=pflash,format=raw,readonly=on,file="$CODE" \
            -drive if=pflash,format=raw,file="$DIR/OVMF_VARS.fd" \
            -drive "file=$disco,if=virtio,format=$fmt" \
            "${extra[@]}" \
            -device virtio-vga \
            -device virtio-rng-pci \
            -nic "user,model=virtio-net-pci,hostfwd=tcp::$SSH_PORT-:22" \
            -display none \
            -monitor "unix:$MON,server,nowait" \
            -serial "file:$DIR/serial.log" \
            -pidfile "$PIDFILE" \
            -daemonize
        sleep 2
        if [[ -f "$PIDFILE" ]]; then
            echo "QEMU arrancado (pid $(cat "$PIDFILE")). Monitor: $MON"
            echo "Serial: $DIR/serial.log   SSH: localhost:$SSH_PORT (si sshd está activo)"
        else
            err "QEMU no arrancó; mira $DIR/serial.log"
        fi
        ;;
    shot)
        nombre="${2:-captura}"
        mkdir -p "$DIR"
        # Ruta absoluta: el monitor de QEMU no hereda el directorio de trabajo.
        ppm="$(cd "$DIR" && pwd)/$nombre.ppm"
        mon "screendump $ppm" >/dev/null
        sleep 1
        [[ -f "$ppm" ]] || err "QEMU no generó la captura (¿está arrancado?)"
        ppm_a_png "$ppm" "$DIR/$nombre.png"
        rm -f "$ppm"
        ;;
    key)
        [[ -n "${2:-}" ]] || err "indica la tecla (p. ej. ret, esc, tab)"
        mon "sendkey $2" >/dev/null
        echo "tecla enviada: $2"
        ;;
    type)
        [[ -n "${2:-}" ]] || err "indica el texto"
        escribir "$2"
        echo "texto enviado: $2"
        ;;
    stop)
        if [[ -S "$MON" ]]; then
            mon "quit" >/dev/null || true
            echo "QEMU detenido"
        else
            echo "no hay ninguna instancia arrancada"
        fi
        ;;
    *)
        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
