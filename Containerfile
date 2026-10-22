# syntax=docker/dockerfile:1
###############################################################################
#  Zenith Linux  —  imagen OCI base (Fedora bootc)
#
#  Base      : quay.io/fedora/fedora-bootc:44
#  Escritorio: KWin Wayland + SDDM + Caelestia Shell (puerto KDE)
#  Apps      : Firefox (RPM) + Flatpak/Flathub
#  NVIDIA    : akmod-nvidia compilado en la imagen (opcional con WITH_NVIDIA)
#
#  Todo el sistema queda definido en este archivo. /usr es de solo lectura en
#  ejecución; /etc y /var se mezclan y persisten.
###############################################################################

ARG BASE_IMAGE=quay.io/fedora/fedora-bootc
ARG FEDORA_VERSION=44

FROM ${BASE_IMAGE}:${FEDORA_VERSION}

# ---------------------------------------------------------------------------
#  Argumentos de construcción
# ---------------------------------------------------------------------------
ARG FEDORA_VERSION=44
# Versión de Caelestia Shell (tag del repo ladybug-me/caelestia-kde).
# v2.6.3 = commit c0cfd04d. Cambiar aquí para actualizar el escritorio.
ARG CAELESTIA_REF=v2.6.3
# "true"  -> incluye akmod-nvidia (RPM Fusion nonfree)
# "false" -> imagen sin driver propietario (AMD/Intel puros)
ARG WITH_NVIDIA=true

LABEL org.opencontainers.image.title="Zenith Linux" \
      org.opencontainers.image.description="Distribución inmutable basada en Fedora bootc, KWin Wayland y Caelestia Shell" \
      org.opencontainers.image.source="https://github.com/WwwNoOne/Zenith-Linux" \
      org.opencontainers.image.url="https://github.com/WwwNoOne/Zenith-Linux" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.zenith.caelestia="${CAELESTIA_REF}" \
      org.zenith.fedora="${FEDORA_VERSION}"

# ---------------------------------------------------------------------------
#  1. Repositorios de terceros
#
#  RPM Fusion aporta ffmpeg completo y akmod-nvidia. Los COPR aportan lo que
#  Fedora no empaqueta (quickshell-git, darkly, libcava, app2unit, ...).
#  Los .repo de COPR se eliminan al final: las actualizaciones llegan por
#  imagen (bootc), no con dnf. RPM Fusion se conserva por trazabilidad.
# ---------------------------------------------------------------------------
RUN set -eux; \
    dnf install -y dnf5-plugins; \
    dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; \
    dnf install -y ffmpeg --allowerasing; \
    dnf copr enable -y errornointernet/quickshell; \
    dnf copr enable -y deltacopy/darkly; \
    dnf copr enable -y celestelove/app2unit; \
    dnf copr enable -y celestelove/libcava; \
    dnf copr enable -y leloubil/wl-clip-persist; \
    dnf copr enable -y brycensranch/gpu-screen-recorder-git; \
    dnf copr enable -y atim/starship

# ---------------------------------------------------------------------------
#  2a. Sesión Wayland / KDE, hardware y shell de Caelestia
#
#  Además de plasma-workspace/kwin, se instalan explícitamente los componentes
#  que Caelestia invoca por nombre en tiempo de ejecución:
#    plasma5support, libplasma        módulos QML org.kde.plasma.*
#    kf6-kpackage, kf6-kservice       kpackagetool6, kbuildsycoca6
#    kscreen                          configuración de pantallas (kscreen-doctor)
#    powerdevil, kglobalacceld        energía y atajos globales
#    kdialog, kmenuedit               diálogos e edición del menú de apps
#    kde-cli-tools                    kde-open, usado por xdg-open
#    plasma-systemsettings            ajustes del sistema
# ---------------------------------------------------------------------------
RUN set -eux; \
    dnf install -y \
        plasma-workspace kwin kscreenlocker sddm sddm-x11 polkit-kde \
        xdg-desktop-portal xdg-desktop-portal-kde plasma-integration kde-gtk-config \
        plasma5support libplasma kf6-kded kglobalacceld powerdevil kscreen \
        kf6-kpackage kf6-kservice plasma-systemsettings kmenuedit kdialog \
        kde-cli-tools \
        xorg-x11-server-Xwayland egl-wayland \
        qt6-qtbase qt6-qtdeclarative qt6-qtwayland qt6-qt5compat \
        qt6-qtmultimedia qt6-qtimageformats qt6-qtsvg qt6-qtshadertools \
        kf6-kwindowsystem kf6-kguiaddons kf6-kcoreaddons kf6-kconfig \
        kf6-kglobalaccel kf6-networkmanager-qt pulseaudio-qt-qt6 \
        kpipewire libqalculate libsecret aubio lm_sensors ksshaskpass; \
    dnf install -y \
        mesa-dri-drivers mesa-vulkan-drivers mesa-libEGL mesa-libGL \
        vulkan-loader \
        kernel-modules-extra linux-firmware \
        pipewire pipewire-pulseaudio wireplumber \
        NetworkManager wpa_supplicant bluez upower accountsservice \
        tuned-ppd brightnessctl ddcutil; \
    dnf install -y \
        quickshell-git matugen app2unit libcava gpu-screen-recorder \
        wl-clipboard cliphist inotify-tools trash-cli jq

# ---------------------------------------------------------------------------
#  2b. Terminal, utilidades, temas, tipografías y apps base
# ---------------------------------------------------------------------------
RUN set -eux; \
    dnf install -y \
        foot eza fastfetch starship btop fish bash pciutils fontconfig \
        procps-ng libnotify libxml2 qalculate \
        xdg-utils xdg-user-dirs desktop-file-utils sassc bat ripgrep python3 \
        fuzzel swappy ImageMagick tesseract tesseract-langpack-eng \
        spectacle slurp grim wl-clip-persist ydotool \
        darkly adw-gtk3-theme papirus-icon-theme \
        google-rubik-fonts google-noto-sans-fonts \
        google-noto-sans-cjk-fonts google-noto-emoji-fonts; \
    dnf install -y firefox flatpak sudo curl unzip tar which avahi nss-mdns

# Paquetes deseables pero no críticos: si un nombre cambia entre versiones de
# Fedora, la imagen se construye igual.
#
#  En Fedora 44 los drivers VA-API/VDPAU de Mesa ya no son subpaquetes
#  (mesa-va-drivers/mesa-vdpau-drivers desaparecieron): van dentro de
#  mesa-dri-drivers, que ya se instala arriba. vainfo/vulkaninfo sirven para
#  diagnosticar la decodificación por hardware (zenith doctor).
RUN set -eux; \
    dnf install -y --skip-unavailable \
        libva-utils vulkan-tools libva-intel-media-driver \
        zram-generator alsa-sof-firmware

# ---------------------------------------------------------------------------
#  2c. Tipografías que Caelestia espera encontrar
#
#  El instalador oficial las descarga en ~/.local/share/fonts; en una imagen
#  inmutable van en /usr/share/fonts para todos los usuarios. Son SIL OFL.
#    - Material Symbols Rounded : iconos de la shell
#    - CaskaydiaCove Nerd Font  : fuente monoespaciada (Cascadia Code parcheada)
#    - JetBrains Mono Nerd Font : alternativa monoespaciada
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /usr/share/fonts/zenith/material-symbols \
             /usr/share/fonts/zenith/cascadia-code \
             /usr/share/fonts/zenith/jetbrains-mono; \
    curl -fsSL --retry 5 -o /tmp/MaterialSymbolsRounded.ttf \
        "https://raw.githubusercontent.com/google/material-design-icons/49d4db35df873165d6bd6ba09b063c7dafbac2f4/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf"; \
    curl -fsSL --retry 5 -o /tmp/MaterialSymbols-LICENSE \
        "https://raw.githubusercontent.com/google/material-design-icons/49d4db35df873165d6bd6ba09b063c7dafbac2f4/LICENSE"; \
    curl -fsSL --retry 5 -o /tmp/CascadiaCode.zip \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/CascadiaCode.zip"; \
    curl -fsSL --retry 5 -o /tmp/JetBrainsMono.zip \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip"; \
    install -m 0644 /tmp/MaterialSymbolsRounded.ttf /tmp/MaterialSymbols-LICENSE \
        /usr/share/fonts/zenith/material-symbols/; \
    unzip -q /tmp/CascadiaCode.zip \
        'CaskaydiaCoveNerdFont-Regular.ttf' 'CaskaydiaCoveNerdFont-Bold.ttf' \
        'CaskaydiaCoveNerdFont-Italic.ttf' 'CaskaydiaCoveNerdFont-BoldItalic.ttf' \
        'LICENSE' -d /usr/share/fonts/zenith/cascadia-code; \
    unzip -q /tmp/JetBrainsMono.zip \
        'JetBrainsMonoNerdFont-Regular.ttf' 'JetBrainsMonoNerdFont-Bold.ttf' \
        'JetBrainsMonoNerdFont-Italic.ttf' 'JetBrainsMonoNerdFont-BoldItalic.ttf' \
        'OFL.txt' -d /usr/share/fonts/zenith/jetbrains-mono; \
    rm -f /tmp/CascadiaCode.zip /tmp/JetBrainsMono.zip \
          /tmp/MaterialSymbolsRounded.ttf /tmp/MaterialSymbols-LICENSE; \
    fc-cache -f

# ---------------------------------------------------------------------------
#  3. Dependencias de compilación de Caelestia Shell
#
#  ccache no se instala a propósito: en una capa de build única no reutiliza
#  nada y dentro del contenedor aborta con «ccache: error: File exists».
# ---------------------------------------------------------------------------
RUN set -eux; \
    dnf install -y \
        cmake ninja-build gcc gcc-c++ git make pkgconf-pkg-config \
        qt6-qtbase-devel qt6-qtbase-private-devel qt6-qtdeclarative-devel \
        qt6-qtwayland-devel qt6-qtsvg-devel qt6-qtshadertools-devel \
        qt6-qtmultimedia-devel qt6-qt5compat-devel qt6-qttools-devel \
        extra-cmake-modules kwin-devel \
        kf6-kglobalaccel-devel kf6-kwindowsystem-devel kf6-kguiaddons-devel \
        kf6-kcoreaddons-devel kf6-kconfig-devel kf6-networkmanager-qt-devel \
        pulseaudio-qt-qt6-devel pulseaudio-libs-devel \
        kpipewire-devel libepoxy-devel libdrm-devel libX11-devel wayland-devel \
        vulkan-headers protobuf-devel protobuf-compiler openssl-devel \
        aubio-devel fftw-devel lm_sensors-devel pipewire-devel \
        libqalculate-devel libcava-devel

# ---------------------------------------------------------------------------
#  4. Compilar e instalar Caelestia Shell en /usr (instalación "packaged")
#
#  El layout es el del PKGBUILD oficial:
#    /usr/bin/caelestia*                  CLI
#    /usr/lib/caelestia                   librerías
#    /usr/lib64/qt6/qml                   plugin QML de Caelestia
#    /etc/xdg/quickshell/caelestia        shell.qml y módulos
#    /usr/share/caelestia                 dots, scripts y assets
#    /usr/share/sddm/themes/caelestia     pantalla de login
#    /usr/share/plasma/shells/caelestia.desktop
# ---------------------------------------------------------------------------
RUN set -eux; \
    git clone --depth 1 --branch "${CAELESTIA_REF}" \
        --recurse-submodules --shallow-submodules \
        https://github.com/ladybug-me/caelestia-kde /src/caelestia-kde; \
    cmake -B /src/build -S /src/caelestia-kde/shell -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/ \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DVERSION="${CAELESTIA_REF#v}" \
        -DINSTALL_BINDIR=usr/bin \
        -DINSTALL_LIBDIR=usr/lib/caelestia \
        -DINSTALL_DATADIR=usr/share/caelestia \
        -DINSTALL_QMLDIR=usr/lib64/qt6/qml \
        -DINSTALL_QSCONFDIR=etc/xdg/quickshell/caelestia \
        -DCAELESTIA_PACKAGE=ON \
        -DREQUIRE_CAVA=ON \
        -DDISTRIBUTOR="Zenith Linux"; \
    cmake --build /src/build -j"$(nproc)"; \
    cmake --install /src/build; \
    cmake -B /src/effect-build -S /src/caelestia-kde/shell/kwin-effects/workspace-tracker \
        -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib64; \
    cmake --build /src/effect-build -j"$(nproc)"; \
    cmake --install /src/effect-build

# ---------------------------------------------------------------------------
#  5. NVIDIA propietario (RPM Fusion)
#
#  akmods compila el módulo contra el kernel exacto de la imagen y se
#  regenera el initramfs para que nvidia-drm arranque con KMS.
#  Requiere Secure Boot DESACTIVADO: los módulos no van firmados.
# ---------------------------------------------------------------------------
#  Tras actualizar pueden coexistir varios kernels (installonly_limit). akmods
#  debe compilar solo para el más reciente, que es el que arrancará la imagen;
#  los kernels antiguos solo ocuparían espacio y confundirían a dracut.
#
#  libva-nvidia-driver (nvidia-vaapi-driver) permite que Firefox decodifique
#  vídeo por hardware con VA-API. No se activa por sí solo: para usarlo hay que
#  exportar LIBVA_DRIVER_NAME=nvidia (ver README), porque forzarlo en la imagen
#  rompería la decodificación en equipos Intel/AMD.
RUN set -eux; \
    if [ "${WITH_NVIDIA}" = "true" ]; then \
        dnf upgrade -y 'kernel*'; \
        KVER="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n1)"; \
        for old in $(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
                kernel kernel-core kernel-modules kernel-modules-core \
                kernel-modules-extra kernel-devel kernel-devel-matched \
                2>/dev/null | grep -v -- "-${KVER}\$" || true); do \
            dnf remove -y "$old" || true; \
        done; \
        dnf install -y kernel-devel-matched akmods; \
        dnf install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda \
            libva-nvidia-driver; \
        KVER="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n1)"; \
        test "$(rpm -q kernel --qf '%{VERSION}\n' | wc -l)" -eq 1; \
        test -d "/usr/src/kernels/${KVER}"; \
        akmods --force --kernels "${KVER}"; \
        depmod -a "${KVER}"; \
        dracut --force --no-hostonly --kver "${KVER}" \
            || echo "aviso: dracut no generó el initramfs; bootc lo hace al desplegar"; \
        ls /usr/lib/modules/"${KVER}"/extra/nvidia/ 2>/dev/null \
            || echo "aviso: no se listaron módulos nvidia en /usr/lib/modules"; \
    else \
        echo "WITH_NVIDIA=false: se omite el driver propietario"; \
    fi

# ---------------------------------------------------------------------------
#  6. Configuración del sistema, branding y script de primer inicio
# ---------------------------------------------------------------------------
COPY files/ /

RUN set -eux; \
    chmod 0755 /usr/bin/caelestia-autostart /usr/bin/zenith \
                 /usr/libexec/zenith/first-login; \
    chmod 0644 /etc/issue /etc/motd \
                 /etc/skel/.bashrc /etc/skel/.bash_profile \
                 /etc/xdg/ksplashrc /etc/xdg/plasmarc /etc/xdg/plasmashellrc \
                 /etc/sddm.conf.d/10-zenith.conf /etc/sddm.conf.d/zz-caelestia.conf \
                 /etc/modprobe.d/zenith-nvidia.conf \
                 /etc/modules-load.d/zenith-uinput.conf \
                 /etc/systemd/zram-generator.conf \
                 /usr/lib/os-release \
                 /usr/lib/bootc/kargs.d/50-zenith-nvidia.toml \
                 /usr/lib/environment.d/90-zenith-caelestia.conf \
                 /usr/lib/systemd/user/caelestia-shell.service \
                 /usr/lib/udev/rules.d/70-uinput.rules; \
    if [ ! -e /usr/bin/qdbus6 ] && [ -x /usr/bin/qdbus-qt6 ]; then \
        ln -s qdbus-qt6 /usr/bin/qdbus6; \
    fi; \
    if [ ! -e /usr/bin/sass ] && [ -x /usr/bin/sassc ]; then \
        ln -s sassc /usr/bin/sass; \
    fi; \
    if [ "${WITH_NVIDIA}" != "true" ]; then \
        rm -f /usr/lib/bootc/kargs.d/50-zenith-nvidia.toml \
              /etc/modprobe.d/zenith-nvidia.conf; \
    fi; \
    ln -sf ../usr/lib/os-release /etc/os-release; \
    if [ -f /usr/share/sddm/themes/caelestia/theme.conf ]; then \
        sed -i -e 's|^os=.*|os=Zenith Linux|' \
               -e 's|^host=.*|host=zenith|' \
            /usr/share/sddm/themes/caelestia/theme.conf; \
    fi; \
    mkdir -p /etc/flatpak/remotes.d; \
    curl -fsSL https://flathub.org/repo/flathub.flatpakrepo \
        -o /etc/flatpak/remotes.d/flathub.flatpakrepo; \
    sed -i 's|^SHELL=.*|SHELL=/usr/bin/fish|' /etc/default/useradd 2>/dev/null || true; \
    systemctl enable sddm.service bluetooth.service \
        tuned.service fstrim.timer; \
    systemctl set-default graphical.target; \
    systemctl --global enable caelestia-shell.service; \
    find /etc/yum.repos.d -maxdepth 1 -name '_copr*' -delete; \
    dnf clean all; \
    rm -rf /src /var/cache/dnf /var/cache/libdnf5 /tmp/*

# Comprobación del contrato de imagen bootc y del escritorio.
RUN set -eux; \
    test -x /usr/bin/bootc; \
    if ! command -v quickshell >/dev/null 2>&1 && ! command -v qs >/dev/null 2>&1; then \
        echo "error: no se encontró el binario de quickshell" >&2; exit 1; \
    fi; \
    test -f /etc/xdg/quickshell/caelestia/shell.qml; \
    test -d /usr/share/plasma/shells/caelestia.desktop; \
    test -f /usr/share/sddm/themes/caelestia/Main.qml; \
    grep -q '^os=Zenith Linux$' /usr/share/sddm/themes/caelestia/theme.conf; \
    grep -q '^PRETTY_NAME="Zenith Linux' /etc/os-release; \
    test -f /usr/share/wayland-sessions/plasma.desktop; \
    test -x /usr/bin/ydotool && test -x /usr/bin/ydotoold; \
    test -f /usr/lib/udev/rules.d/70-uinput.rules; \
    test -f /etc/modules-load.d/zenith-uinput.conf; \
    test "$(stat -c '%a' /usr/lib/os-release)" = "644"; \
    test -z "$(find /etc/sddm.conf.d /etc/xdg /etc/skel /etc/modules-load.d \
                     /etc/modprobe.d /usr/lib/systemd/user /usr/lib/environment.d \
                     /usr/lib/udev/rules.d -type f -perm -o+w -print -quit)"; \
    test -n "$(find /usr/lib64/qt6/plugins/kwin -name '*workspace_tracker*' -print -quit)"; \
    if [ "${WITH_NVIDIA}" = "true" ]; then \
        test -f /usr/lib/bootc/kargs.d/50-zenith-nvidia.toml; \
    fi; \
    echo "Zenith Linux: layout bootc correcto"

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
