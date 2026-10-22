# Zenith Linux

Distribución Linux **inmutable basada en imágenes OCI**, construida sobre
[Fedora bootc](https://bootc.dev), con **KWin Wayland + SDDM** como sesión
gráfica y **[Caelestia Shell](https://github.com/ladybug-me/caelestia-kde)**
(puerto KDE) como escritorio. Firefox va en la imagen; el resto de aplicaciones
se instalan con **Flatpak/Flathub**.

> **Estado:** v0.1 — esqueleto funcional, **todavía no compilado** en este
> equipo (no hay WSL2 ni Podman instalados). Los nombres de paquete se
> verificaron contra los repositorios de Fedora 44, RPM Fusion y los COPR
> (octubre 2026), pero el primer `build.sh image` real puede seguir necesitando
> ajustes. Todo el sistema está definido en el `Containerfile`.

---

## 1. Arquitectura

| Capa | Componente | Función |
| --- | --- | --- |
| Base | `quay.io/fedora/fedora-bootc:44` | Sistema base de solo lectura, systemd, kernel Fedora |
| Escritorio | KWin Wayland + SDDM | Compositor y pantalla de inicio de sesión |
| Shell | Caelestia (quickshell) | Barra, launcher, notificaciones, lockscreen |
| Navegador | Firefox (RPM) | Único navegador en la imagen |
| Apps | Flatpak + Flathub | Único método para instalar software de usuario |
| NVIDIA | `akmod-nvidia` (RPM Fusion) | Módulo compilado durante el build |
| Swap | zram-generator | Swap comprimido en RAM |

### Mapa de almacenamiento

```
/            solo lectura (composefs + /usr inmutable)
/etc         escribible (overlay), configuración del sistema
/var         escribible y persistente (Flatpak, contenedores, logs)
/var/home    escribible y persistente; /home es un enlace aquí
```

Las actualizaciones son atómicas: se descarga una imagen nueva y se cambia el
arranque. Si algo falla, `zenith rollback` vuelve a la imagen anterior.

---

## 2. Decisiones de implementación

Estas son las decisiones que se apartan (o precisan) del documento original,
para que el sistema sea viable sobre bootc:

1. **Caelestia se instala en `/usr`, no en `/home`.** Se compila con el layout
   oficial de paquete (`CAELESTIA_PACKAGE=ON`): `/usr/bin/caelestia*`,
   `/etc/xdg/quickshell/caelestia`, `/usr/share/sddm/themes/caelestia`. Así el
   escritorio viaja dentro de la imagen, es idéntico para todos los usuarios y
   sobrevive a cualquier actualización. Lo que sí vive en `/home` es la
   configuración personal (`~/.config`, temas, wallpapers): un script de
   **primer inicio** ejecuta los pasos 03, 04, 04a, 06 y 10 de Caelestia como
   el usuario.
2. **Sesión Plasma mínima, sin el escritorio Plasma completo.** Se instala
   `plasma-workspace` (startplasma, kscreenlocker, plasmashell) y `kwin`, pero
   el shell visible es Caelestia. El paquete `caelestia.desktop` sustituye al
   shell de Plasma y aporta el lockscreen.
3. **NVIDIA dentro de la imagen, opcional.** `WITH_NVIDIA=true` (por defecto)
   instala `akmod-nvidia` y compila el módulo contra el kernel exacto de la
   imagen, además de regenerar el initramfs. Con `false` la imagen queda limpia
   para AMD/Intel.
4. **Los repos COPR se eliminan al final del build.** Las actualizaciones
   llegan como imagen nueva (bootc), no con `dnf`. RPM Fusion se conserva para
   que se vea de dónde salieron los paquetes no libres.
5. **Fedora 44** es la versión estable actual (octubre 2026). Fedora 45 ya está
   publicada en Quay como pre-release; para probarla: `FEDORA_VERSION=45`.
6. **Las tipografías viajan en la imagen.** Caelestia espera *Material Symbols
   Rounded* (iconos) y una monoespaciada Nerd Font; en vez de descargarlas en
   `~/.local/share/fonts` en el primer login, se instalan en
   `/usr/share/fonts/zenith` durante el build (SIL OFL).
7. **Greeter SDDM en X11.** Se instala `sddm-x11` (Xorg) porque es lo que
   funciona de forma fiable en VirtualBox/llvmpipe; la sesión de usuario sí es
   KWin **Wayland** (`plasma.desktop`). Para usar el greeter Wayland:
   instalar `sddm-wayland-generic` (arrastra Weston) y poner
   `DisplayServer=wayland`.

---

## 3. Requisitos

- Windows 10/11 con virtualización habilitada (VT-x/AMD-V).
- WSL2 + Ubuntu 24.04 (o cualquier Linux con Podman 4.9+).
- ~40 GB de disco libre y 8 GB de RAM (16 GB recomendado: la compilación de
  Qt/Caelestia y la ISO son pesadas).
- Conexión a Internet (Fedora, RPM Fusion, COPR, GitHub, Flathub).
- Para NVIDIA: Secure Boot **desactivado**.

---

## 4. Puesta a punto (una sola vez)

### 4.1 Instalar WSL2

En PowerShell **como administrador**:

```powershell
wsl --install -d Ubuntu
wsl --status        # debe decir "Versión predeterminada: 2"
```

> Si `wsl --status` responde «WSL2 no se puede iniciar porque la virtualización
> no está habilitada», activa **VT-x/AMD-V** (Intel VT-x o AMD-V/SVM) en la
> BIOS/UEFI y el componente opcional «Plataforma de máquina virtual» de Windows
> (`OptionalFeatures.exe`). Sin eso, WSL2 no arranca aunque esté instalado.

Reinicia, abre Ubuntu y crea tu usuario. Después:

```powershell
wsl -d Ubuntu -- bash -lc "sudo apt-get update && sudo apt-get install -y podman uidmap slirp4netns fuse-overlayfs"
```

O usa el script incluido:

```powershell
wsl -d Ubuntu -- bash -lc "bash /mnt/c/Users/P52-u/Desktop/Zenith_linux/Zenith-Linux/scripts/wsl-bootstrap.sh"
```

### 4.2 (Recomendado) trabajar dentro del disco de WSL

Compilar sobre `/mnt/c` funciona pero es **mucho** más lento. Copia el repo a
ext4:

```powershell
wsl -d Ubuntu -- bash -lc "mkdir -p ~/zenith && cp -a /mnt/c/Users/P52-u/Desktop/Zenith_linux/Zenith-Linux/. ~/zenith/"
```

A partir de aquí, edita en Windows con `\\wsl$\Ubuntu\home\<usuario>\zenith` y
construye desde ahí. Los comandos de este README usan `~/zenith`.

---

## 5. Construir

```bash
cd ~/zenith
chmod +x build.sh scripts/*.sh
./build.sh check    # podman, disco, red y /dev/loop-control
./build.sh image
```

`check` no construye nada: verifica que Podman funciona, que hay espacio para
la imagen (~25 GiB con medios), que las URLs del build (RPM Fusion, COPR,
Flathub, fuentes, Caelestia) responden y, en WSL2, si existe
`/dev/loop-control` (necesario solo para ISO/VMDK). También lanza
`scripts/check-syntax.sh`, que valida la sintaxis de todos los scripts, la de
cada bloque `RUN` del `Containerfile` y que no haya ficheros con CRLF.

Solo la comprobación estática (sin Podman, tarda un segundo):

```bash
bash scripts/check-syntax.sh
```

Esto construye `ghcr.io/wwwnone/zenith-linux:latest`. La primera vez tarda
entre 30 y 60 minutos (descarga Fedora, compila Caelestia y, si está activo,
el módulo NVIDIA).

Variantes:

```bash
./build.sh lint     # imagen + "bootc container lint" (valida el layout)
./build.sh vmdk     # imagen + disco para VirtualBox
./build.sh iso      # imagen + ISO de instalación
./build.sh all      # imagen + VMDK + ISO
```

Variables útiles:

| Variable | Por defecto | Uso |
| --- | --- | --- |
| `IMAGE` | `ghcr.io/wwwnone/zenith-linux:latest` | nombre:tag de la imagen |
| `FEDORA_VERSION` | `44` | versión de la base bootc |
| `CAELESTIA_REF` | `v2.6.3` | tag de Caelestia |
| `WITH_NVIDIA` | `true` | `false` para AMD/Intel |
| `PODMAN` | `sudo podman` | `podman` para rootless |

Ejemplo sin NVIDIA:

```bash
WITH_NVIDIA=false ./build.sh image
```

Desde PowerShell puedes usar el envoltorio:

```powershell
.\build.ps1 check
.\build.ps1 image
.\build.ps1 vmdk
```

> **Nota:** `bootc-image-builder` necesita Podman **rootful** y montar
> `/var/lib/containers/storage`. Por eso `build.sh` usa `sudo podman` por
> defecto.
>
> **Nota WSL2:** osbuild usa dispositivos de bucle (`/dev/loop-control`). Si tu
> kernel de WSL2 no los expone, `build.sh vmdk|iso|qcow2` fallará al generar
> medios aunque la imagen OCI se construya bien. En ese caso, exporta la imagen
> (`podman save`) y ejecuta `bootc-image-builder` en una VM Linux, o usa
> `./build.sh lint` para validar la imagen dentro de WSL.

### Integración continua (opcional)

`.github/workflows/build.yml` valida el repositorio y construye la imagen en
GitHub Actions:

- **validate**: `bash scripts/check-syntax.sh` (segundos, sin Podman).
- **image**: `podman build` con `WITH_NVIDIA=false` + `bootc container lint`.
  Si el push va a `main`, publica `ghcr.io/<usuario>/zenith-linux:latest`, que
  se puede instalar con `bootc switch`.

La ISO/VMDK no se generan en CI: osbuild necesita `/dev/loop-control` y
privilegios que el runner no garantiza. NVIDIA queda fuera para no compilar
akmods en cada push; la imagen de uso real se construye en local.

---

## 6. Probar en VirtualBox

1. Crea una VM: tipo **Linux → Fedora (64-bit)**, **EFI activado**.
2. RAM 4–8 GB, 2–4 vCPU. En disco elige **«No añadir un disco duro virtual»**.
3. Vídeo: **VMSVGA**, 128 MB y **aceleración 3D activada**.
4. En Configuración → Almacenamiento, añade como disco el VMDK generado:
   `output/vmdk/disk.vmdk`. El VMDK **ya es el disco completo** (con su ESP y
   su raíz): no hace falta un disco vacío aparte ni instalar nada.
5. Arranca. Usuario: `zenith` / contraseña: `zenith` (cámbialos, ver
   `iso/config.toml`).

El tamaño del VMDK lo decide `bootc-image-builder` a partir del contenido de la
imagen. Si se queda corto y el VMDK es dinámico, se puede ampliar con
`VBoxManage modifymedium disk output/vmdk/disk.vmdk --resize 40960` (40 GiB) y
luego `growpart`/`btrfs filesystem resize` dentro de la VM.

> **Aviso VirtualBox:** KWin Wayland sobre VMSVGA puede arrancar con
> renderizado software (llvmpipe) o quedarse en negro según la versión de
> VirtualBox y los drivers del host. Para validar el escritorio de verdad es
> más fiable QEMU/KVM con `virtio-gpu` (`./build.sh qcow2`). VirtualBox sirve
> para comprobar arranque, SDDM e instalación.

---

## 7. Instalar en hardware real

1. `./build.sh iso`
2. Graba en un USB el ISO que indique el script al terminar (con el
   `bootc-image-builder` actual es `output/bootiso/install.iso`), en modo DD
   (Rufus o `dd if=... of=/dev/sdX bs=8M status=progress`).
3. Arranca en **UEFI**. Si vas a usar NVIDIA, desactiva Secure Boot.
4. Anaconda instala la imagen bootc en el disco. Crea tu usuario en el
   instalador (el `zenith/zenith` de `config.toml` es solo para pruebas).
5. Primer arranque: SDDM → sesión **Plasma (Wayland)** → Caelestia arranca
   automáticamente.

En el primer login, `caelestia-autostart` ejecuta la provisión de `/home`
(configs, tema, autostart, servicios de usuario). Tarda unos segundos y solo
ocurre una vez. El log está en:

```
~/.local/state/zenith/first-login.log
```

---

## 8. Uso diario

```bash
# Aplicaciones
flatpak install flathub org.gimp.GIMP
flatpak install flathub com.obsproject.Studio

# Estado y diagnóstico
zenith status
zenith doctor

# Actualizar (imagen + Flatpak) y reiniciar
zenith update
zenith reboot

# Volver a la imagen anterior
zenith rollback
zenith reboot
```

No uses `dnf install`: `/usr` es de solo lectura y el software de usuario va
por Flatpak. `rpm -q`, `journalctl`, `systemctl` y `podman` sí funcionan con
normalidad.

### Personalización

- Wallpaper y colores: **Nexus → Appearance** (Caelestia). El wallpaper de
  KDE no alimenta el esquema dinámico.
- Terminal: `~/.bashrc` (bash) o `~/.config/fish/config.fish` (fish, shell por
  defecto). Starship ya está configurado.
- Atajos: **Nexus → Shortcuts**.

---

## 9. NVIDIA: detalles importantes

- El módulo se compila **en el build**, contra el kernel de la imagen. No hay
  DKMS en el equipo.
- **Secure Boot debe estar desactivado.** Los módulos de akmods no van
  firmados. Si necesitas Secure Boot, hay que firmar con MOK
  (`kmodgenca`/`mokutil`), que aún no está automatizado.
- Al actualizar, la imagen nueva trae kernel y módulo ya compilados juntos; no
  actualices el kernel por separado (no es posible en bootc).
- Comprobación:

```bash
nvidia-smi
lsmod | grep -E 'nvidia|nouveau'
journalctl -b -u akmods
```

Si tu GPU es demasiado nueva para el módulo propietario, cambia
`akmod-nvidia` por `akmod-nvidia-open` en el `Containerfile` (Turing o
posterior).

### Decodificación de vídeo por hardware

Mesa ya cubre Intel y AMD (`mesa-dri-drivers` incluye los drivers VA-API en
Fedora 44). En NVIDIA la imagen instala además `libva-nvidia-driver`, pero no lo
activa: para que Firefox use VA-API con la GPU NVIDIA hay que forzarlo en la
sesión del usuario.

```bash
# ~/.config/environment.d/91-nvidia-vaapi.conf
LIBVA_DRIVER_NAME=nvidia
MOZ_DISABLE_RDD_SANDBOX=1
```

Comprueba con `vainfo` (paquete `libva-utils`) y `vulkaninfo` (`vulkan-tools`).
No lo pongas en `/etc/environment`: en equipos Intel/AMD rompería la
decodificación que ya funciona.

---

## 10. Estructura del repositorio

```
Zenith-Linux/
├── Containerfile              # toda la definición del SO
├── build.sh                   # imagen + VMDK/ISO/QCOW2
├── build.ps1                  # envoltorio Windows → WSL2
├── iso/config.toml            # usuario/hostname de bootc-image-builder
├── scripts/wsl-bootstrap.sh   # Podman en Ubuntu/WSL
├── scripts/preflight.sh       # comprobación previa (build.sh check)
├── scripts/check-syntax.sh    # bash -n + RUN del Containerfile + CRLF
├── .github/workflows/         # CI: validación, imagen y lint
└── files/                     # se copia tal cual sobre la raíz de la imagen
    ├── etc/
    │   ├── sddm.conf.d/       # greeter X11 + tema Caelestia + sesión plasma.desktop
    │   ├── modprobe.d/        # nouveau fuera, nvidia-drm KMS
    │   ├── modules-load.d/    # uinput (teclado en pantalla)
    │   ├── xdg/               # sin splash ni OSD de Plasma
    │   ├── systemd/           # zram
    │   └── skel/              # .bashrc / .bash_profile
    └── usr/
        ├── bin/               # caelestia-autostart, zenith
        ├── lib/os-release     # branding
        ├── lib/bootc/kargs.d/ # argumentos de kernel NVIDIA
        ├── lib/systemd/user/  # caelestia-shell.service
        ├── lib/udev/rules.d/  # regla uaccess para /dev/uinput
        └── libexec/zenith/    # provisión de primer inicio
```

---

## 11. Limitaciones actuales y siguientes pasos

- [ ] **Primer build sin validar**: los nombres de paquete ya se contrastaron
      con Fedora 44, RPM Fusion y los COPR, todas las URLs externas del build
      responden y scripts + bloques `RUN` pasan `bash -n`
      (`bash scripts/check-syntax.sh`), pero el build real sigue pendiente.
      Si algo falla, el log de `dnf` dice qué y se corrige en el `Containerfile`.
- [ ] **Tamaño de imagen**: se instalan las dependencias `-devel` para compilar
      Caelestia. Siguiente optimización: build multi-stage o `dnf remove` de
      toolchain tras la compilación (hoy se prioriza que el build funcione).
- [ ] **Firma de módulos NVIDIA** para Secure Boot.
- [ ] **`bootc-image-builder` está en transición**: el contenedor
      `quay.io/centos-bootc/bootc-image-builder` es desde 2026 un envoltorio de
      compatibilidad sobre `image-builder` (multicall). Los tipos `iso` y
      `anaconda-iso` siguen funcionando pero están marcados como *legacy*.
      Siguiente paso: migrar a `ghcr.io/osbuild/image-builder-cli` con el tipo
      `generic-iso` (requiere añadir `dracut-live`, `iso.yaml` y las piezas de
      shim/grub al contenedor).
- [ ] **Branding del instalador**: Anaconda sigue mostrando textos de Fedora.
      Se puede personalizar con un `installer` kickstart en `iso/config.toml`.
- [x] **CI**: workflow de GitHub Actions que valida el repo y construye la
      imagen + `bootc container lint` en cada push. La ISO/VMDK sigue
      construyéndose en local (osbuild necesita `/dev/loop-control`).
- [ ] **Actualización de Caelestia**: subir `CAELESTIA_REF` y reconstruir. La
      configuración de usuario se conserva en `/home`.
- [ ] **Fedora 45**: disponible en Quay; probar `FEDORA_VERSION=45` cuando sea
      estable.

---

## 12. Solución de problemas

| Síntoma | Qué revisar |
| --- | --- |
| SDDM no arranca / pantalla negra | `journalctl -b -u sddm`; el greeter por defecto es X11 (`sddm-x11`). Prueba `DisplayServer=wayland` solo si instalaste `sddm-wayland-generic` |
| La sesión no aparece en SDDM | Debe existir `/usr/share/wayland-sessions/plasma.desktop` (KDE ≥ 6.4 renombró `plasmawayland.desktop`) |
| Caelestia no aparece | `systemctl --user status caelestia-shell`; `caelestia shell -l`; log de primer inicio |
| Iconos cuadrados / faltan símbolos | `fc-list \| grep -i "material symbols"`; deben estar en `/usr/share/fonts/zenith` |
| El primer login no aplicó configs | Borra `~/.local/state/zenith/first-login-v1.done` y ejecuta `zenith first-login` |
| NVIDIA no carga | Secure Boot, `lsmod`, `journalctl -b -u akmods`, `nvidia-smi` |
| El teclado en pantalla no escribe | `ls -l /dev/uinput` (necesita la regla udev con `uaccess`), `modprobe uinput`, `systemctl --user status ydotoold` |
| Firefox no decodifica por hardware | `vainfo`; en NVIDIA exporta `LIBVA_DRIVER_NAME=nvidia` para el usuario, no globalmente |
| Wayland lento en VirtualBox | Activa 3D; usa QEMU/KVM para probar en serio |
| Falla el build en un paquete | El log de `dnf` dice cuál; ajústalo en el `Containerfile` |
| Falla el build de Caelestia | Revisa la versión de `CAELESTIA_REF` y las dependencias Qt/KF6 |
| bib falla con loop devices | WSL2 sin `/dev/loop-control`: usa una VM Linux o `./build.sh lint` |

---

## 13. Licencia

El `Containerfile`, los scripts y la configuración de Zenith Linux se publican
bajo **GPL-3.0-or-later**, la misma licencia que Caelestia Shell. Fedora,
KDE y el resto de componentes conservan sus licencias originales.
