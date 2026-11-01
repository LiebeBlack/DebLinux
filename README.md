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
│   │   └── grub.cfg                    # Menú GRUB con timeout (arranque sin tecla)
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
│   │   │   ├── calamares/modules/
│   │   │   │   └── partition.conf      # Instalación obligatoria en tabla GPT (UEFI)
│   │   │   ├── systemd/system/
│   │   │   │   ├── getty@tty1.service.d/
│   │   │   │   │   └── autologin.conf  # Autologin en TTY1 para el usuario live
│   │   │   │   ├── efi-removable-fallback.service # Ruta de arranque tipo USB en el sistema instalado
│   │   │   │   └── setup-autologin.service # Ajusta el autologin al usuario instalado
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
│   │   │   └── efi-removable-fallback  # Shim + MokManager en EFI/BOOT del sistema instalado
│   │   └── usr/share/applications/
│   │       └── firefox-nightly.desktop # Entrada de escritorio de Firefox Nightly
│   └── hooks/
│       └── live/
│           ├── 0100-user-setup.hook.chroot # Permisos, usuario live y servicios
│           └── 0200-firefox-nightly.hook.chroot # Descarga e instala Firefox Nightly
├── scripts/
│   ├── generate-mok.sh                 # Generador dinámico de claves MOK OpenSSL
│   ├── sign-and-repack.sh              # Extracción del árbol, firma con sbsign y reconstrucción mkisofs
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

1. **Generación de Claves:** Durante el flujo de CI, se genera un par de claves X.509 RSA 2048 (`mok.key`, `mok.crt`, `mok.der`, `mok.cer`) con extensiones específicas de firma de código (`extendedKeyUsage = codeSigning, 1.3.6.1.4.1.2312.16.1.2`). `mok.cer` es el mismo certificado DER que `mok.der` con la extensión que esperan algunas herramientas y selectores de fichero del firmware; no es una tercera clave.
2. **Firma del Kernel:** Se extrae el ejecutable PE/COFF del kernel (`vmlinuz`) del sistema compilado y se firma usando `sbsign --key mok.key --cert mok.crt`.
3. **Verificación:** Se valida la firma con `sbverify --cert mok.crt`.
4. **Inyección de MokManager:** se reconstruye `efi.img` (la imagen FAT que arranca el firmware) para añadir `mmx64.efi`, porque shim solo busca MokManager en el mismo sistema de ficheros desde el que se cargó y live-build no lo incluye cuando hay GRUB firmado. El conjunto completo (`bootx64.efi`, `grubx64.efi`, `grub.cfg` y `mmx64.efi`) se replica además en `/EFI/boot` del árbol ISO9660: shim busca su segunda etapa en su propio directorio, así que copiar solo MokManager dejaba una ruta «boot from file» que no arrancaba.
5. **Construcción de la ISO final:** se extrae el árbol completo de la ISO de live-build, se sustituye el kernel firmado en `/live`, se inyectan los certificados públicos en la raíz (`/MOK.crt`, `/MOK.der`, `/MOK.cer`, más `/live/MOK.der`) y la nueva `efi.img`, y se genera el ISO con **el mismo comando `xorriso -as mkisofs` que usa live-build** (`-R -r -J -joliet-long -l -iso-level 3`, `-e boot/grub/efi.img -no-emul-boot`, `-isohybrid-gpt-basdat -isohybrid-apm-hfsplus`), conservando el volume id y los metadatos PVD del original. Se hace así porque `xorriso -boot_image any replay` sobre una ISO de live-build aborta con *«Cannot enable EL Torito boot image #1 because it is not a data file in the ISO filesystem»* y descarta el arranque; reconstruir desde el árbol con las opciones de live-build sí produce una imagen arrancable.
6. **Verificación de la cadena completa:** `scripts/sign-and-repack.sh` reextrae del ISO final los cuatro archivos de `/EFI/boot` y los compara byte a byte con la imagen de arranque, y `scripts/verify-iso.sh` comprueba que shim esté firmado por Microsoft, que GRUB lo esté por Debian (leyendo `GRUBX64.EFI` dentro de `efi.img`, que es lo que arranca el firmware), que `MMX64.EFI` esté dentro de `efi.img` y en el árbol, que la firma `EFI PART` del GPT siga en el LBA 1 para el arranque por USB y que todos los kernels verifiquen contra el certificado MOK.

### Arranque del Sistema Instalado (ruta tipo USB)

Al instalar, `grub-install` de Debian detecta que la sesión arrancó con Secure Boot y coloca la cadena firmada en la ESP (`EFI/<id>/shimx64.efi` firmado por Microsoft, `EFI/<id>/grubx64.efi` firmado por Debian y `EFI/<id>/grub.cfg`), además de registrar la entrada NVRAM con ese id apuntando a shim. El id lo toma Calamares del branding (`Debian`; instalaciones antiguas usan `debian`, que en FAT es el mismo directorio). Esa es la ruta principal y no necesita MOK: el kernel instalado ya viene firmado por Debian.

Como respaldo, `efi-removable-fallback.service` replica esa cadena en la ruta de medios extraíbles, igual que un USB:

| Archivo en `/boot/efi/EFI/BOOT` | Origen | Firmante |
| :--- | :--- | :--- |
| `BOOTX64.EFI` | `EFI/<id>/shimx64.efi` | Microsoft UEFI CA |
| `grubx64.efi` | `EFI/<id>/grubx64.efi` | Debian |
| `grub.cfg` | `EFI/<id>/grub.cfg` | — |
| `mmx64.efi` | `EFI/<id>/mmx64.efi` | Microsoft |

El script localiza `<id>` recorriendo `EFI/*` en busca de shim (no asume el nombre), reutiliza el `grub.cfg` de `grub-install` (que fija el UUID de la raíz) y, si no existe, lo sintetiza con `grub-probe` para no depender de ese archivo.

Esto cubre el caso en que el firmware no guarde la entrada NVRAM o la pierda (reset de CMOS, placa que solo arranca `EFI/BOOT/BOOTX64.EFI`) y corrige el fallback que deja Calamares, que copia el GRUB firmado por Debian en el hueco de `BOOTX64.EFI`: el firmware lo rechaza bajo Secure Boot porque ahí solo confía en la CA de Microsoft. Con shim en ese hueco la cadena vuelve a ser de confianza y MokManager queda al lado, disponible si algún día hace falta enrolar una clave desde esa ruta.

El servicio es idempotente (solo reescribe archivos cuyo contenido cambie), no toca un `EFI/BOOT/BOOTX64.EFI` que pertenezca a otro gestor de arranque y no hace nada en la sesión live, donde `/boot/efi` no está montado. Si la ESP no se puede escribir, lo anota en el journal y el arranque continúa por la entrada NVRAM.

Se ejecuta en cada arranque del sistema instalado, así que el respaldo se regenera solo si alguien borra la NVRAM o el propio `EFI/BOOT`. Lo que **no** puede cubrir es un firmware que ignore la NVRAM desde el primer arranque: ahí hay que arrancar una vez desde fichero (`EFI/<id>/shimx64.efi`) y el servicio deja la ruta tipo USB lista para los siguientes.

### Cómo Enrolar la Clave MOK en la Lenovo 300e:

Al flashear la ISO a una memoria USB (usando `dd` o `ventoy`):

1. Conecta la memoria USB a la Lenovo 300e y enciende el equipo presionando `F12` para elegir el dispositivo de arranque.
2. **Antes del primer arranque** hay que enrolar la clave MOK, porque el kernel va firmado con ella y el firmware aún no la conoce:
   * Entra en el menú de arranque del firmware y usa la opción **"Boot from file"** / **"EFI Shell"** para ejecutar `EFI/boot/mmx64.efi` de la USB (la ISO trae `MOK.der`, `MOK.cer` y `MOK.crt` en la raíz, y `mmx64.efi` tanto dentro de `efi.img` como en `/EFI/boot`).
   * En MokManager selecciona **"Enroll key from disk"**.
   * Navega a la partición de la USB y selecciona `MOK.der` o `MOK.cer` (ambos son el certificado DER; el `.crt` es PEM).
   * Selecciona **"View Key"** para confirmar los datos (`Debian Secure Boot MOK`).
   * Selecciona **"Continue"** -> **"Yes"** -> confirma la inscripción y reinicia con **"Reboot"**.
3. El equipo arrancará normalmente en Debian 13 bajo Secure Boot activado al 100%; el shim de Debian valida GRUB y GRUB valida el kernel con la clave MOK ya enrolada.

> **Nota:** la clave MOK se genera nueva en cada compilación (no se guarda en el repositorio), así que cada ISO exige volver a enrolarla. `scripts/sign-and-repack.sh` reconstruye `efi.img` para meter `mmx64.efi` dentro (shim solo lo lanza desde ahí) y además deja una copia en `/EFI/boot` del árbol ISO9660; aun así, el explorador de archivos de muchos firmware solo lista particiones FAT y no el ISO9660. Si no te aparece, usa el **plan B**: desactiva Secure Boot temporalmente, arranca la ISO e instala; ya en el sistema instalado, copia `MOK.der` desde la raíz de la USB, instala `mokutil` si hace falta (`sudo apt install mokutil`) y ejecuta `sudo mokutil --import MOK.der`; reinicia, enrola la clave en MokManager y vuelve a activar Secure Boot.

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
* **Arranque sin tecla:** `config/bootloaders/grub-pc/grub.cfg` sustituye la plantilla de live-build para fijar `set timeout=10` y `set default=0`; sin eso GRUB se queda esperando una tecla en el menú (la plantilla no define `timeout`), lo que rompe el arranque desatendido y la prueba en QEMU.
* **Prueba de arranque:** se ejecuta en cada push a `main`, en tags `v*` y en runs manuales (input `run_boot_test`, activo por defecto). Se arranca la ISO con QEMU + OVMF Secure Boot y se espera a que el sistema llegue a userspace: el arranque incluye `console=ttyS0,115200 console=tty0` (la pantalla sigue siendo `/dev/console`), así que el log serie del invitado debe mostrar el prompt de login (`login:`). Eso demuestra que el firmware aceptó shim, shim aceptó GRUB, GRUB cargó el kernel y systemd arrancó; si aparece un rechazo de firma, un `Kernel panic` o se agota el timeout (`BOOT_TIMEOUT`, 900 s por defecto), el job falla. Las capturas, el OCR y el log serie quedan como artefacto `secureboot-boot-test`.
* **Instalación GPT:** `config/includes.chroot/etc/calamares/modules/partition.conf` fija `defaultPartitionTableType: gpt` y `requiredPartitionTableType: gpt`. La ISO solo trae GRUB para UEFI, así que el sistema instalado debe ser GPT con partición EFI; Calamares ya elige GPT en sistemas EFI, pero así queda explícito y se rechaza una instalación legacy/MBR.
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
