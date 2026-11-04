# Debian 13 (Trixie) Ultralight Wayland Live ISO - Universal Intel

ISO personalizada ultraligera de **Debian GNU/Linux 13 (Trixie)** con la pila Wayland basada en **Labwc**, optimizada para **cualquier equipo Intel** (tanto con GPUs integradas como dedicadas). Compatible con **UEFI Secure Boot**. La cadena de confianza es la de Debian: **shim firmado por Microsoft**, **GRUB firmado por Debian** y **kernel firmado por Debian**. No hay MOK, no hay que enrolar ninguna clave y no se incluye firmware no esencial.

## 🎯 Características Universales Intel

- **Detección automática de hardware Intel**: CPU, GPU (integradas y dedicadas), WiFi, Bluetooth y Audio
- **Soporte Intel Universal**: Intel HD/UHD/Iris Xe (integradas) + Intel Arc (dedicadas)
- **Optimización automática**: Scripts de detección y optimización específicos para cada hardware detectado
- **Wayland nativo**: Toda la stack está optimizada para Wayland con retrocompatibilidad XWayland
- **Ultraligera y minimalista**: Solo lo esencial para un escritorio moderno y funcional
- **Firmware mínimo y coherente**: `firmware-intel-graphics`, `firmware-iwlwifi` (WiFi y Bluetooth Intel), `firmware-sof-signed` + `firmware-intel-sound` + `alsa-ucm-conf` (audio SOF, con `sof-glk` para Gemini Lake) e `intel-microcode`; sin blobs AMD/NVIDIA (`firmware-misc-nonfree` excluido).

---

## 💻 Especificaciones de Hardware Objetivo

**ISO universal para cualquier equipo Intel**, optimizada para:

### Procesadores Intel Soportados
- Intel Celeron (todas las generaciones)
- Intel Pentium (todas las generaciones)
- Intel Core i3/i5/i7/i9 (todas las generaciones)
- Intel Atom (todas las generaciones)

### GPUs Intel Soportadas
- **Integradas**: Intel HD Graphics, Intel UHD Graphics, Intel Iris Xe Graphics
- **Dedicadas**: Intel Arc Graphics (A380, A750, A770, etc.)
- **Legacy**: Intel HD Graphics 2000/3000/4000, Intel Iris Graphics 5100/6100

### Aceleración Hardware
- Intel Media Driver (`iHD` / `intel-media-va-driver`) para GPUs modernas
- Intel i965 VA-API driver para GPUs legacy
- Mesa Iris (`mesa-va-drivers`, `mesa-vulkan-drivers`) con detección automática
- Vulkan support para GPUs Intel modernas
- OpenCL support para compute workloads

### Audio
- Intel SOF (`firmware-sof-signed`, `firmware-intel-sound`, `alsa-ucm-conf`)
- Intel HD Audio (legacy)
- Soporte para múltiples altavoces y micrófonos

### Redes
- WiFi: Intel Wireless (`iwlwifi`)
- Bluetooth: Intel (firmware `ibt-*` en `firmware-iwlwifi`)
- Ethernet: Intel

### Almacenamiento
- eMMC, SSD SATA, SSD NVMe/M.2
- Soporte para particiones GPT obligatorio

### Seguridad
- UEFI x86_64 con Secure Boot obligatorio
- GPT + partición EFI obligatorio
- No soporta BIOS/MBR legacy

> **Detección automática**: El instalador detecta automáticamente el hardware Intel específico y aplica las optimizaciones correspondientes durante la instalación.

---

## 🚀 Arquitectura del Software

* **Compositor Wayland:** Labwc (apilamiento ultraligero Openbox para wlroots)
* **Gestión de Asiento (Seat):** `seatd` / `libseat1` (sin depender de gestores pesados)
* **Arranque Directo:** Sin Display Manager (DM). TTY1 ejecuta automáticamente `exec /usr/local/bin/launch-labwc`.
* **Servidor de Audio:** PipeWire + WirePlumber + emulación PulseAudio (`pipewire-pulse`).
* **Barra de Estado:** Waybar (con indicador de batería, brillo, volumen, CPU y RAM).
* **Terminal & Lanzador:** `foot` (terminal acelerado por Wayland) y `fuzzel` (lanzador de aplicaciones dmenu/rofi-like en Wayland).
* **Navegador:** Firefox Nightly (`/opt/firefox-nightly`, verificado contra el archivo `.checksums` de Mozilla durante la compilación).
* **Escritorio:** `mousepad` (editor gráfico), `pcmanfm`, `pavucontrol` y `nmtui` (red).
* **Herramientas de Configuración:**
  - Pantalla: `wlr-randr` (Wayland) y `xrandr` (XWayland, vía `x11-xserver-utils`)
  - Ratón/Touchpad: `libinput-tools` y `xinput` (XWayland)
  - Hardware Intel: `powertop`, `tuned`, `thermald`, `cpuid`
* **Energía:** `swayidle` + `swaylock` (bloqueo a los 5 min y suspensión a los 10), `zram-tools` (swap comprimida en RAM), `thermald` y `tuned`.
* **Medios extraíbles:** `exfatprogs` y `ntfs-3g` para montar USB exFAT/NTFS desde `udisks2`.
* **Firmas UEFI:** `shim-signed` y `grub-efi-amd64-signed`; el kernel de `linux-image-amd64` ya viene firmado por Debian. No se instala `sbsigntool` en la ISO; `mokutil` puede venir como dependencia de `shim-signed`, pero no se usa.
* **Detección Intel:** Scripts automáticos para detectar y optimizar CPU, GPU, WiFi, Bluetooth y Audio Intel específicos.
* **Reproducibilidad:** base de `bootstrap` fijada a un snapshot de Debian; squashfs con `zstd`.

---

## 🌐 Sitio del Proyecto (GitHub Pages)

La web del proyecto está en [docs/index.html](docs/index.html): un único fichero HTML autocontenido (sin CDN, sin dependencias, sin build) que presenta la visión, la cadena Secure Boot, el pipeline, el hardware objetivo y los pasos de instalación. Para publicarla, en **Settings → Pages** elige *Deploy from a branch*, rama `main` y carpeta `/docs`; el fichero `docs/.nojekyll` evita el procesado de Jekyll.

---

## 📁 Estructura del Repositorio

```text
.
├── .github/
│   └── workflows/
│       └── build-iso.yml               # Pipeline de GitHub Actions (ubuntu-latest)
├── docs/
│   ├── index.html                      # Web del proyecto (autocontenida, GitHub Pages)
│   └── .nojekyll                       # Publicación directa sin Jekyll
├── auto/
│   ├── clean                           # Script de limpieza live-build
│   ├── config                          # Configuración base debian amd64 / grub-efi
│   └── build                           # Lanzador de compilación live-build
├── config/
│   ├── bootloaders/grub-pc/
│   │   └── grub.cfg                    # Menú GRUB (ruta de live-build; no implica BIOS)
│   ├── package-lists/
│   │   ├── 00-base.list.chroot          # Sistema base, live-boot, systemd, sudo
│   │   ├── 01-wayland.list.chroot       # Labwc, foot, fuzzel, waybar, pipewire, seatd
│   │   ├── 02-graphics-codecs.list.chroot # Controladores Intel VA-API, Mesa, FFmpeg
│   │   ├── 03-lenovo-hardware.list.chroot # Firmware Intel (GPU/WiFi/SOF), microcódigo, red
│   │   ├── 04-secureboot.list.chroot    # Shim, GRUB EFI firmado y efibootmgr (sin claves MOK)
│   │   ├── 05-installer.list.chroot     # Calamares y su configuración Debian
│   │   └── 06-desktop-extras.list.chroot # swayidle/swaylock, zram, medios extraíbles, runtime Firefox
│   ├── includes.chroot/
│   │   ├── etc/
│   │   │   ├── calamares/
│   │   │   │   ├── settings.conf       # Secuencia, instancias shellprocess y job efi-fallback
│   │   │   │   └── modules/
│   │   │   │       ├── partition.conf  # Instalación obligatoria en tabla GPT (UEFI)
│   │   │   │       └── efi-fallback.conf # Shim en EFI/BOOT antes del primer reinicio
│   │   │   ├── systemd/system/
│   │   │   │   ├── getty@tty1.service.d/
│   │   │   │   │   └── autologin.conf  # Autologin en TTY1 para el usuario live
│   │   │   │   └── efi-removable-fallback.service # Ruta de arranque tipo USB en el sistema instalado
│   │   │   ├── profile.d/
│   │   │   │   └── 99-autostart-labwc.sh # Detección TTY1 y llamada a launch-labwc
│   │   │   ├── live/config.conf.d/
│   │   │   │   └── live-user.conf      # Grupos de usuario (_seat, audio, video, etc.)
│   │   │   ├── default/
│   │   │   │   └── zramswap            # Swap comprimida en RAM (ALGO=zstd, 50 %)
│   │   │   ├── polkit-1/rules.d/
│   │   │   │   └── 49-nopasswd_global.rules # Acciones administrativas sin contraseña
│   │   │   └── skel/
│   │   │       ├── .bash_profile       # Respaldo de inicio de sesión de usuario
│   │   │       └── .config/
│   │   │           ├── labwc/
│   │   │           │   ├── autostart   # Script de arranque (pipewire, wireplumber, waybar)
│   │   │           │   ├── environment # Variables de entorno Wayland / Intel VA-API
│   │   │           │   ├── rc.xml      # Atajos de teclado y panel táctil Lenovo
│   │   │           │   └── menu.xml    # Menú contextual de escritorio (clic derecho)
│   │   │           ├── waybar/
│   │   │           │   ├── config      # Configuración de módulos de barra
│   │   │           │   └── style.css   # Estilo visual de barra superior
│   │   │           ├── foot/
│   │   │           │   └── foot.ini    # Configuración de terminal
│   │   │           └── fuzzel/
│   │   │               └── fuzzel.ini  # Configuración de menú buscador
│   │   ├── usr/local/bin/
│   │   │   ├── launch-labwc            # Script ejecutable de lanzamiento y entorno
│   │   │   └── launch-calamares        # Lanzador del instalador con pkexec/sudo
│   │   ├── usr/local/sbin/
│   │   │   ├── efi-removable-fallback  # Shim + GRUB firmado en EFI/BOOT del sistema instalado
│   │   │   └── setup-autologin         # Autologin de TTY1 para el usuario instalado
│   │   └── usr/share/applications/
│   │       └── firefox-nightly.desktop # Entrada de escritorio de Firefox Nightly
│   └── hooks/
│       └── live/
│           ├── 0100-user-setup.hook.chroot # Permisos, usuario live y servicios
│           ├── 0150-strip-unused-firmware.hook.chroot # Purga firmware NVIDIA/AMD
│           └── 0200-firefox-nightly.hook.chroot # Descarga e instala Firefox Nightly
├── scripts/
│   ├── repack-iso.sh                   # GPT + MBR protector + ESP; sin firma MOK
│   ├── verify-iso.sh                   # Verificación de la cadena Debian y del layout UEFI
│   └── boot-test-iso.sh                # Arranque de prueba en QEMU/OVMF con Secure Boot
├── .gitignore
└── README.md
```

---

## 🔑 Atajos de Teclado en Labwc

| Atajo | Acción |
| :--- | :--- |
| `Super + Enter` | Abrir terminal (`foot`) |
| `Super + d` | Abrir lanzador de programas (`fuzzel`) |
| `Super + q` o `Alt + F4` | Cerrar ventana activa |
| `Super + Shift + q` | Salir de Labwc |
| `Alt + Tab` | Alternar entre ventanas |
| `Teclas de Volumen` | Ajustar volumen mediante PipeWire (`wpctl`) |
| `Teclas de Brillo` | Ajustar brillo de pantalla Lenovo 300e (`brightnessctl`) |
| `Impr Pant` | Captura de pantalla completa (`grim`) |
| `Shift + Impr Pant` | Captura de región interactiva (`slurp \| grim`) |
| `Clic Derecho` en escritorio | Desplegar menú de aplicaciones y apagado |

---

## 🔒 Secure Boot sin MOK

La ISO y el sistema instalado usan la cadena que Debian ya firma. No se genera ninguna clave propia ni se enrola nada:

| Componente | Firmante | Confianza |
| :--- | :--- | :--- |
| `shim` (`BOOTX64.EFI`) | Microsoft UEFI CA | `db` del firmware |
| `GRUB` (`GRUBX64.EFI`) | Debian | CA de Debian incluida en shim |
| `vmlinuz` | Debian | CA de Debian vía `shim_lock` |

* **Kernel:** `linux-image-amd64` de Debian 13 ya incluye la firma PE/COFF de Debian. `sbsign` no se ejecuta; el archivo se copia tal cual a `/live/vmlinuz`.
* **Sin MOK:** no hay `mok.key`, `MOK.crt`, `MOK.der`, `MOK.cer`, `mmx64.efi` ni pasos de enrolamiento. `mokutil` puede estar presente como dependencia de `shim-signed`, pero no se usa.
* **Sin MBR de arranque:** la ISO no trae GRUB BIOS ni código de arranque en el MBR. Solo el MBR protector que exige GPT (tipo `0xEE`).
* **Sistema instalado:** `grub-install` detecta la sesión UEFI y coloca shim y GRUB firmados en la ESP; el kernel instalado también viene firmado por Debian. No hace falta MOK. El job `shellprocess@efi-fallback` ejecuta el helper antes de desmontar el ESP, así que `EFI/BOOT` ya tiene shim en el primer arranque y no hay que entrar en setup.
* **Ruta de respaldo:** `efi-removable-fallback` escribe shim, GRUB y `grub.cfg` en `/boot/efi/EFI/BOOT` (sin `mmx64.efi`) durante la instalación. El servicio `efi-removable-fallback.service` lo verifica y repara en cada arranque si el firmware pierde la entrada NVRAM.

### Arranque en la Lenovo 300e

1. Flashea la ISO a una memoria USB con `dd` (o un grabador que escriba la imagen tal cual).
2. Enciende la laptop, pulsa `F12` y elige el USB.
3. Arranca directamente con **Secure Boot activado**. No hay que desactivarlo ni enrolar claves.

Si el firmware no muestra el USB en el menú, usa la opción **"Boot from file"** y selecciona `EFI/BOOT/BOOTX64.EFI` de la partición EFI del medio. Es shim, firmado por Microsoft, así que el firmware lo acepta.

---

## 💽 Layout de la ISO: GPT + MBR protector, sin BIOS ni APM

La ISO final es **UEFI-only**:

* **LBA 0:** MBR protector (`0x55AA`, primera partición tipo `0xEE`) con los 440 bytes de código de arranque a cero. No hay código BIOS.
* **LBA 1:** cabecera GPT (`EFI PART`).
* **GPT:** partición 1 para el sistema ISO9660 y partición 2 para el ESP, creada a partir de `boot/grub/efi.img`.
* **El Torito:** entrada UEFI que apunta al ESP añadido.
* **Sin APM:** no se escribe Apple Partition Map.
* **Sin entrada BIOS:** no hay El Torito `PC-BIOS` ni `-isohybrid-mbr`.

El comando de reconstrucción (`scripts/repack-iso.sh`) usa:

```text
xorriso -as mkisofs \
  -R -r -J -joliet-long -l -iso-level 3 \
  -append_partition 2 0xef boot/grub/efi.img \
  -appended_part_as_gpt -partition_offset 16 \
  -e '--interval:appended_partition_2:all::' -no-emul-boot \
  -o debian-live-lenovo300e-uefi.iso <arbol>
```

**Por qué no se usa `-isohybrid-gpt-basdat`:** xorriso documenta que esa opción «works only with `-isohybrid-mbr`». Sin `-isohybrid-mbr`, xorriso la ignora silenciosamente y la ISO se genera sin GPT; el build anterior fallaba exactamente en la comprobación de `EFI PART` del LBA 1. `-append_partition` + `-appended_part_as_gpt` produce un GPT válido, un MBR protector real y un ESP que el firmware puede arrancar desde USB.

> El kernel sigue pudiendo leer tablas MBR de memorias externas (es lo normal para un USB con datos). Lo que no existe es el arranque ni la instalación por MBR: Calamares exige GPT y la ISO no contiene bootloader BIOS.

---

## 🌐 Firefox Nightly

Nightly no está en el archivo de Debian, así que `config/hooks/live/0200-firefox-nightly.hook.chroot` lo descarga del canal oficial de Mozilla durante la compilación, verifica el SHA512 del archivo `.checksums` publicado junto al tarball y lo instala en `/opt/firefox-nightly` con un lanzador en `/usr/local/bin/firefox-nightly` y una entrada de escritorio (`MOZ_ENABLE_WAYLAND=1`). El hook aborta el build si falta alguna librería de runtime, para no publicar un navegador que no arranca.

---

## 🧪 CI, Reproducibilidad y Releases

* **Validación de paquetes:** `scripts/check-package-lists.sh` contrasta cada nombre de `config/package-lists` y de `packages.conf` con el archivo real de Debian antes de compilar: un nombre inexistente falla en segundos, no tras el debootstrap. Se ejecuta en el CI y en local.
* **Snapshot de Debian:** la base de `debootstrap` se fija por defecto al snapshot `20261031T000000Z` (`DEBIAN_SNAPSHOT`). El resto de etapas usa `deb.debian.org` a propósito: live-build copia el mirror de chroot en el `sources.list` final, así que fijarlo dejaría la ISO y el sistema instalado apuntando a un snapshot sin actualizaciones de seguridad. Usa `DEBIAN_SNAPSHOT=live` para compilar contra el archivo actual.
* **Solo Debian 13 (trixie):** las listas de paquetes usan los nombres `t64` de trixie (`libgtk-3-0t64`, `libasound2t64`, ...); `auto/config` falla con un mensaje claro si se intenta otra suite.
* **Squashfs zstd:** `--chroot-squashfs-compression-type zstd` acelera la descompresión en el N4120.
* **Herramientas verificadas:** los `.deb` de live-build, debootstrap y debian-archive-keyring que se instalan como root se comprueban con SHA256.
* **Caché:** `cache/packages.bootstrap` y `cache/packages.chroot` se conservan entre runs con `actions/cache`, y `concurrency` cancela builds duplicados de la misma rama.
* **Arranque sin tecla:** `config/bootloaders/grub-pc/grub.cfg` sustituye la plantilla de live-build para fijar `set timeout=10` y `set default=0`; sin eso GRUB se queda esperando una tecla en el menú y rompe el arranque desatendido y la prueba en QEMU. El nombre `grub-pc` es la ruta que lee live-build, no un bootloader BIOS.
* **Repack UEFI:** `scripts/repack-iso.sh` extrae el árbol, conserva el kernel Debian, crea el GPT con MBR protector y ESP, y comprueba `EFI PART`, el tipo `0xEE`, la ausencia de APM/código BIOS y el contenido de `efi.img`.
* **Verificación:** `scripts/verify-iso.sh` comprueba GPT + MBR protector, ausencia de APM y de entrada BIOS, la entrada El Torito UEFI, shim firmado por Microsoft, GRUB firmado por Debian y todos los kernels firmados por Debian. No usa MOK.
* **Prueba de arranque:** se ejecuta en cada push a `main`, en tags `v*` y en runs manuales (input `run_boot_test`, activo por defecto). Se arranca la ISO con QEMU + OVMF Secure Boot **como disco USB** (el medio real) y se espera a que el sistema llegue a userspace: el arranque incluye `console=ttyS0,115200 console=tty0`, así que el log serie del invitado debe mostrar el prompt de login (`login:`). Eso demuestra que el firmware aceptó shim, shim aceptó GRUB, GRUB cargó el kernel firmado por Debian y systemd arrancó; si aparece un rechazo de firma, un `Kernel panic` o se agota el timeout (`BOOT_TIMEOUT`, 900 s por defecto), el job falla. Las capturas, el OCR y el log serie quedan como artefacto `secureboot-boot-test`. Con `BOOT_MEDIA=cdrom` se prueba la ruta El Torito.
* **Instalación GPT:** `config/includes.chroot/etc/calamares/modules/partition.conf` fija `defaultPartitionTableType: gpt` y `requiredPartitionTableType: gpt`. La ISO solo trae GRUB para UEFI, así que el sistema instalado debe ser GPT con partición EFI; Calamares ya elige GPT en sistemas EFI, pero así queda explícito y se rechaza una instalación legacy/MBR. El job `shellprocess@efi-fallback` de `settings.conf` deja el respaldo shim en `EFI/BOOT` antes de reiniciar.
* **Instancias de Calamares:** `settings.conf` declara `shellprocess@efi-fallback`, `@detect-intel-hardware`, `@autologin` y `@remove-installer-menu` en la sección `instances:` con su `.conf` propio. Sin ese bloque Calamares cargaría `shellprocess.conf` y ninguna de esas tareas se ejecutaría. `@autologin` apunta el autologin de TTY1 al usuario creado por el instalador y lo desactiva si no encuentra ninguno, para que el sistema instalado no busque al usuario `live`.
* **Releases:** solo al empujar un tag `v*` se publica un GitHub Release con la ISO, su `.sha256` y, si defines los secretos `GPG_PRIVATE_KEY`/`GPG_PASSPHRASE`, una firma detached `.asc`. Un push a `main` no crea releases; para publicar, crea y empuja un tag `v*`. Ya no se adjuntan certificados MOK.

---

## ⚙️ Compilación Local (Opcional)

Si deseas compilar la imagen localmente en Debian/Ubuntu:

```bash
# 1. Dar permisos de ejecución a los scripts (el repo no guarda el bit)
chmod +x auto/clean auto/config auto/build scripts/*.sh
find config/hooks -type f -exec chmod +x {} +
find config/includes.chroot/usr/local/bin config/includes.chroot/usr/local/sbin \
  -type f -exec chmod +x {} +

# 1b. Instalar herramientas (sbsigntool aporta sbverify; mtools, mdir/mcopy)
sudo apt-get update
sudo apt-get install -y xorriso dosfstools mtools zstd sbsigntool

# 1c. Ubuntu y Debian 12 traen versiones antiguas de live-build (3.0~a57 / 20230502)
# que no reconocen opciones de Debian 13 como --updates. Instala los paquetes de trixie:
curl -fsSLO https://deb.debian.org/debian/pool/main/l/live-build/live-build_20250505+deb13u1_all.deb
curl -fsSLO https://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.141_all.deb
curl -fsSLO https://deb.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2025.1_all.deb
sudo apt-get install -y ./debian-archive-keyring_2025.1_all.deb ./debootstrap_1.0.141_all.deb ./live-build_20250505+deb13u1_all.deb

# 2. Configurar y compilar live-build (DEBIAN_SNAPSHOT=live usa el mirror actual;
#    sin variable se usa el snapshot fijado en auto/config)
sudo DEBIAN_VERSION="trixie" DEBIAN_SNAPSHOT="live" lb config
sudo lb build

# 3. Reconstruir la ISO con GPT + MBR protector y ESP (sin sudo: solo lee la ISO)
./scripts/repack-iso.sh live-image-amd64.hybrid.iso debian-live-lenovo300e-uefi.iso

# 4. Verificar el layout y la cadena Secure Boot de Debian
./scripts/verify-iso.sh debian-live-lenovo300e-uefi.iso

# 5. Opcional: probar el arranque con Secure Boot en QEMU (USB por defecto)
sudo apt-get install -y qemu-system-x86 ovmf socat tesseract-ocr tesseract-ocr-eng netpbm
./scripts/boot-test-iso.sh debian-live-lenovo300e-uefi.iso
# BOOT_MEDIA=cdrom ./scripts/boot-test-iso.sh debian-live-lenovo300e-uefi.iso
```

La ISO publicada incluye el kernel firmado por Debian, shim y GRUB firmados, y no requiere ningún paso de MOK.

---

## 🔧 Nuevas Características Universales Intel

### Detección Automática de Hardware Intel

El instalador Calamares ahora incluye scripts de detección automática que identifican:

- **CPU Intel**: Detecta cualquier procesador Intel (Celeron, Pentium, Core i3/i5/i7/i9, Atom)
- **GPU Intel**: Distingue entre GPUs integradas (HD/UHD/Iris Xe) y dedicadas (Arc)
- **WiFi Intel**: Detecta tarjetas Intel Wireless y alternativas (Realtek, Atheros, Broadcom)
- **Bluetooth Intel**: Detecta adaptadores Bluetooth Intel y alternativas
- **Audio Intel**: Detecta audio Intel SOF, HD Audio y alternativas

### Optimización Automática

Después de la instalación, el sistema aplica optimizaciones específicas según el hardware detectado:

- **Intel GPU**: Configura VA-API, Vulkan, y ajustes específicos de driver (iHD para modernas, i965 para legacy)
- **Intel CPU**: Habilita Intel IOMMU, C-states, P-states y power management
- **Intel WiFi**: Configura power saving y módulos iwlwifi optimizados
- **Intel Audio**: Configura SOF firmware y power saving para audio

### Eliminación Automática del Instalador

Una vez instalado el sistema en el disco, el instalador Calamares elimina automáticamente:

- La opción "Install Debian to Disk (Calamares)" del menú de Labwc
- El script `launch-calamares`
- Los archivos de escritorio de Calamares

Esto deja el sistema instalado limpio y listo para uso, sin residuos del modo live.

### Herramientas de Configuración Incluidas

El sistema incluye herramientas completas para configurar:

- **Pantalla**: `wlr-randr` (Wayland) y `xrandr` (XWayland, vía `x11-xserver-utils`)
- **Audio**: `pavucontrol` y `wpctl` / `pw-cli` (PipeWire)
- **Red**: `nmtui` / `nmcli` (NetworkManager)
- **Ratón/Touchpad**: `libinput-tools` y `xinput` (XWayland)
- **Hardware Intel**: `powertop`, `tuned`, `thermald`, `cpuid`
- **Telemetría**: `dmidecode`, `hwinfo`, `lshw`, `pciutils`, `usbutils`, `ethtool`

### Soporte Universal Intel

La ISO ahora soporta:
- Cualquier procesador Intel (todas las generaciones)
- GPUs Intel integradas (HD, UHD, Iris Xe)
- GPUs Intel dedicadas (Arc A380, A750, A770, etc.)
- GPUs Intel legacy (HD Graphics 2000/3000/4000, Iris 5100/6100)
- WiFi y Bluetooth Intel (firmware `firmware-iwlwifi`)
- Múltiples opciones de audio (Intel SOF, HD Audio, alternativas)

Todo esto se detecta y configura automáticamente durante la instalación.
