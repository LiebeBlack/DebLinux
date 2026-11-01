# Debian 13 (Trixie) Ultralight Wayland Live ISO for Lenovo 300e 2nd Gen

ISO personalizada ultraligera de **Debian GNU/Linux 13 (Trixie)** con la pila Wayland basada en **Labwc**, optimizada específicamente para la laptop **Lenovo 300e 2nd Gen (Intel Celeron N4120)** con **UEFI Secure Boot** estrictamente activado y firmado mediante **MOK (Machine Owner Key)**.

---

## 💻 Especificaciones de Hardware Objetivo

* **Dispositivo:** Lenovo 300e 2nd Gen (Type 81M9 / 82GK)
* **Procesador:** Intel® Celeron® N4120 (4 núcleos, 1.10 GHz hasta 2.60 GHz, Gemini Lake Refresh)
* **GPU:** Intel® UHD Graphics 600 (Gen9.5 LP)
* **Aceleración Hardware:** Intel Media Driver (`iHD` / `intel-media-va-driver`), Mesa Iris (`mesa-va-drivers`, `mesa-vulkan-drivers`)
* **Audio:** Intel Gemini Lake SOF (`firmware-sof-signed`, `firmware-intel-sound`, `alsa-ucm-conf`)
* **Red Inalámbrica:** Intel Wireless / Realtek (`firmware-iwlwifi`, `firmware-realtek`)
* **Seguridad:** UEFI x86_64 con Secure Boot obligatorio

---

## 🚀 Arquitectura del Software

* **Compositor Wayland:** Labwc (apilamiento ultraligero Openbox para wlroots)
* **Gestión de Asiento (Seat):** `seatd` / `libseat1` (sin depender de gestores pesados)
* **Arranque Directo:** Sin Display Manager (DM). TTY1 ejecuta automáticamente `exec /usr/local/bin/launch-labwc`.
* **Servidor de Audio:** PipeWire + WirePlumber + emulación PulseAudio (`pipewire-pulse`).
* **Barra de Estado:** Waybar (con indicador de batería de la laptop, brillo, volumen, CPU y RAM).
* **Terminal & Lanzador:** `foot` (terminal acelerado por Wayland) y `fuzzel` (lanzador de aplicaciones dmenu/rofi-like en Wayland).
* **Navegador:** Firefox Nightly (`/opt/firefox-nightly`, verificado contra el archivo `.checksums` de Mozilla durante la compilación).
* **Escritorio:** `mousepad` (editor gráfico), `pcmanfm`, `pavucontrol`, `nm-applet`.
* **Energía:** `swayidle` + `swaylock` (bloqueo a los 5 min y suspensión a los 10), `zram-tools` (swap comprimida en RAM para los 4 GB) y `thermald`.
* **Medios extraíbles:** `exfatprogs` y `ntfs-3g` para montar USB exFAT/NTFS desde `udisks2`.
* **Firmas UEFI:** `shim-signed`, `grub-efi-amd64-signed`, `sbsigntool`, `mokutil`.
* **Reproducibilidad:** base de `bootstrap` fijada a un snapshot de Debian; squashfs con `zstd`.

---

## 📁 Estructura del Repositorio

```text
.
├── .github/
│   └── workflows/
│       └── build-iso.yml               # Pipeline de GitHub Actions (ubuntu-latest)
├── auto/
│   ├── clean                           # Script de limpieza live-build
│   ├── config                          # Configuración base debian amd64 / grub-efi
│   └── build                           # Lanzador de compilación live-build
├── config/
│   ├── package-lists/
│   │   ├── 00-base.list.chroot          # Sistema base, live-boot, systemd, sudo
│   │   ├── 01-wayland.list.chroot       # Labwc, foot, fuzzel, waybar, pipewire, seatd
│   │   ├── 02-graphics-codecs.list.chroot # Controladores Intel VA-API, Mesa, FFmpeg
│   │   ├── 03-lenovo-hardware.list.chroot # Firmware SOF audio, Intel microcode, wifi
│   │   ├── 04-secureboot.list.chroot    # Shim, grub-efi-signed, mokutil, sbsigntool
│   │   ├── 05-installer.list.chroot     # Calamares y su configuración Debian
│   │   └── 06-desktop-extras.list.chroot # swayidle/swaylock, zram, thermald, runtime Firefox
│   ├── includes.chroot/
│   │   ├── etc/
│   │   │   ├── systemd/system/getty@tty1.service.d/
│   │   │   │   └── autologin.conf      # Autologin en TTY1 para el usuario live
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
│   │   └── usr/share/applications/
│   │       └── firefox-nightly.desktop # Entrada de escritorio de Firefox Nightly
│   └── hooks/
│       └── live/
│           ├── 0100-user-setup.hook.chroot # Permisos, usuario live y servicios
│           └── 0200-firefox-nightly.hook.chroot # Descarga e instala Firefox Nightly
├── scripts/
│   ├── generate-mok.sh                 # Generador dinámico de claves MOK OpenSSL
│   ├── sign-and-repack.sh              # Extracción, firma con sbsign y reempaquetado xorriso
│   ├── verify-iso.sh                   # Verificación de la cadena Secure Boot del ISO
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
| `Shift + Impr Pant` | Captura de región interactiva (`slurp | grim`) |
| `Clic Derecho` en escritorio | Desplegar menú de aplicaciones y apagado |

---

## 🔒 Proceso de Firma MOK y Secure Boot

1. **Generación de Claves:** Durante el flujo de CI, se genera un par de claves X.509 RSA 2048 (`mok.key`, `mok.crt`, `mok.der`) con extensiones específicas de firma de código (`extendedKeyUsage = codeSigning, 1.3.6.1.4.1.2312.16.1.2`).
2. **Firma del Kernel:** Se extrae el ejecutable PE/COFF del kernel (`vmlinuz`) del sistema compilado y se firma usando `sbsign --key mok.key --cert mok.crt`.
3. **Verificación:** Se valida la firma con `sbverify --cert mok.crt`.
4. **Inyección en ISO:** Con `xorriso -boot_image any keep`, se reemplaza el kernel en `/live/vmlinuz` y se inyectan los certificados públicos en la raíz de la ISO (`/MOK.crt`, `/MOK.der`).
5. **Verificación de la cadena completa:** `scripts/verify-iso.sh` comprueba que shim esté firmado por Microsoft, que GRUB lo esté por Debian (esto último leyendo `GRUBX64.EFI` dentro de `efi.img`, que es lo que arranca el firmware) y que todos los kernels verifiquen contra el certificado MOK.

### Cómo Enrolar la Clave MOK en la Lenovo 300e:

Al flashear la ISO a una memoria USB (usando `dd` o `ventoy`):

1. Conecta la memoria USB a la Lenovo 300e y enciende el equipo presionando `F12` para elegir el dispositivo de arranque.
2. **Antes del primer arranque** hay que enrolar la clave MOK, porque el kernel va firmado con ella y el firmware aún no la conoce:
   * Entra en el menú de arranque del firmware y usa la opción **"Boot from file"** / **"EFI Shell"** para ejecutar `EFI/boot/mmx64.efi` de la USB (la ISO trae `MOK.der`/`MOK.crt` en la raíz y `mmx64.efi` tanto dentro de `efi.img` como en `/EFI/boot`).
   * En MokManager selecciona **"Enroll key from disk"**.
   * Navega a la partición de la USB y selecciona `MOK.der` (DER; es lo que MokManager reconoce de forma fiable; el `.crt` es PEM).
   * Selecciona **"View Key"** para confirmar los datos (`Debian Secure Boot MOK`).
   * Selecciona **"Continue"** -> **"Yes"** -> confirma la inscripción y reinicia con **"Reboot"**.
3. El equipo arrancará normalmente en Debian 13 bajo Secure Boot activado al 100%; el shim de Debian valida GRUB y GRUB valida el kernel con la clave MOK ya enrolada.

> **Nota:** la clave MOK se genera nueva en cada compilación (no se guarda en el repositorio), así que cada ISO exige volver a enrolarla. El `mmx64.efi` ya viene dentro de `efi.img` y el script añade una copia en `/EFI/boot` del árbol ISO9660; aun así, el explorador de archivos de muchos firmware solo lista particiones FAT y no el ISO9660. Si no te aparece, usa el **plan B**: desactiva Secure Boot temporalmente, arranca la ISO e instala; ya en el sistema instalado, copia `MOK.der` desde la raíz de la USB, instala `mokutil` si hace falta (`sudo apt install mokutil`) y ejecuta `sudo mokutil --import MOK.der`; reinicia, enrola la clave en MokManager y vuelve a activar Secure Boot.

---

## 🌐 Firefox Nightly

Nightly no está en el archivo de Debian, así que `config/hooks/live/0200-firefox-nightly.hook.chroot` lo descarga del canal oficial de Mozilla durante la compilación, verifica el SHA512 del archivo `.checksums` publicado junto al tarball y lo instala en `/opt/firefox-nightly` con un lanzador en `/usr/local/bin/firefox-nightly` y una entrada de escritorio (`MOZ_ENABLE_WAYLAND=1`). El hook aborta el build si falta alguna librería de runtime, para no publicar un navegador que no arranca.

---

## 🧪 CI, Reproducibilidad y Releases

* **Snapshot de Debian:** la base de `debootstrap` se fija por defecto al snapshot `20261031T000000Z` (`DEBIAN_SNAPSHOT`). El resto de etapas usa `deb.debian.org` a propósito: live-build copia el mirror de chroot en el `sources.list` final, así que fijarlo dejaría la ISO y el sistema instalado apuntando a un snapshot sin actualizaciones de seguridad. Usa `DEBIAN_SNAPSHOT=live` para compilar contra el archivo actual.
* **Solo Debian 13 (trixie):** las listas de paquetes usan los nombres `t64` de trixie (`libgtk-3-0t64`, `libasound2t64`, ...); el workflow ya no ofrece `bookworm` y `auto/config` falla con un mensaje claro si se intenta otra suite.
* **Squashfs zstd:** `--chroot-squashfs-compression-type zstd` acelera la descompresión en el N4120.
* **Herramientas verificadas:** los `.deb` de live-build, debootstrap y debian-archive-keyring que se instalan como root se comprueban con SHA256.
* **Caché:** `cache/packages.bootstrap` y `cache/packages.chroot` (donde live-build guarda los `.deb`) se conservan entre runs con `actions/cache`, y `concurrency` cancela builds duplicados de la misma rama.
* **Prueba de arranque:** se ejecuta en cada push a `main`, en tags `v*` y en runs manuales (input `run_boot_test`, activo por defecto). Se arranca la ISO con QEMU + OVMF Secure Boot y se detecta si el firmware rechaza shim/GRUB (se falla si aparece un rechazo de firma o un error de arranque). La firma del kernel se valida por separado en `verify-iso.sh` contra la MOK; OVMF arranca sin esa clave enrolada, así que esta prueba no llega a validar el kernel. Las capturas y el OCR quedan como artefacto `secureboot-boot-test`.
* **Releases:** solo al empujar un tag `v*` se publica un GitHub Release con la ISO, su `.sha256`, los certificados MOK y, si defines los secretos `GPG_PRIVATE_KEY`/`GPG_PASSPHRASE`, una firma detached `.asc`. Un push a `main` no crea releases; para publicar, crea y empuja un tag `v*`.

---

## ⚙️ Compilación Local (Opcional)

Si deseas compilar la imagen localmente en Debian/Ubuntu:

```bash
# 1. Instalar herramientas
sudo apt-get update
sudo apt-get install -y shim-signed \
  sbsigntool openssl xorriso dosfstools mtools zstd

# 1b. Ubuntu y Debian 12 traen versiones antiguas de live-build (3.0~a57 / 20230502)
# que no reconocen opciones de Debian 13 como --updates. Instala los paquetes de trixie:
curl -fsSLO https://deb.debian.org/debian/pool/main/l/live-build/live-build_20250505+deb13u1_all.deb
curl -fsSLO https://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.141_all.deb
curl -fsSLO https://deb.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2025.1_all.deb
sudo apt-get install -y ./debian-archive-keyring_2025.1_all.deb ./debootstrap_1.0.141_all.deb ./live-build_20250505+deb13u1_all.deb

# 2. Generar claves MOK
chmod +x scripts/*.sh auto/*
./scripts/generate-mok.sh mok/mok.key mok/mok.crt mok/mok.der

# 3. Configurar y compilar live-build (DEBIAN_SNAPSHOT=live usa el mirror actual;
#    sin variable se usa el snapshot fijado en auto/config)
sudo DEBIAN_VERSION="trixie" DEBIAN_SNAPSHOT="live" lb config
sudo lb build

# 4. Firmar el kernel y reempaquetar la ISO final
# (sin sudo: el script solo lee la ISO y escribe los artefactos como tu usuario,
#  de lo contrario quedan propiedad de root y falla la generación del sha256)
./scripts/sign-and-repack.sh live-image-amd64.hybrid.iso debian-live-lenovo300e-signed.iso mok/mok.key mok/mok.crt mok/mok.der

# 5. Verificar la cadena Secure Boot (shim/GRUB/kernel)
./scripts/verify-iso.sh debian-live-lenovo300e-signed.iso mok/mok.crt

# 6. Opcional: probar el arranque con Secure Boot en QEMU
sudo apt-get install -y qemu-system-x86 ovmf socat tesseract-ocr tesseract-ocr-eng netpbm
./scripts/boot-test-iso.sh debian-live-lenovo300e-signed.iso
```
