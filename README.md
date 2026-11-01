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
* **Firmas UEFI:** `shim-signed`, `grub-efi-amd64-signed`, `sbsigntool`, `mokutil`.

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
│   │   └── 04-secureboot.list.chroot    # Shim, grub-efi-signed, mokutil, sbsigntool
│   ├── includes.chroot/
│   │   ├── etc/
│   │   │   ├── systemd/system/getty@tty1.service.d/
│   │   │   │   └── autologin.conf      # Autologin en TTY1 para el usuario live
│   │   │   ├── profile.d/
│   │   │   │   └── 99-autostart-labwc.sh # Detección TTY1 y llamada a launch-labwc
│   │   │   ├── live/config.conf.d/
│   │   │   │   └── live-user.conf      # Grupos de usuario (_seat, audio, video, etc.)
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
│   │   └── usr/local/bin/
│   │       └── launch-labwc            # Script ejecutable de lanzamiento y entorno
│   └── hooks/
│       └── live/
│           └── 0100-user-setup.hook.chroot # Ajustes de permisos y servicios en chroot
├── scripts/
│   ├── generate-mok.sh                 # Generador dinámico de claves MOK OpenSSL
│   └── sign-and-repack.sh              # Extracción, firma con sbsign y reempaquetado xorriso
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

### Cómo Enrolar la Clave MOK en la Lenovo 300e:

Al flashear la ISO a una memoria USB (usando `dd` o `ventoy`):

1. Conecta la memoria USB a la Lenovo 300e y enciende el equipo presionando `F12` para elegir el dispositivo de arranque.
2. Si el kernel requiere enrolamiento de clave o arranca **MokManager** (`mmx64.efi`):
   * Selecciona **"Enroll MOK"** o **"Enroll key from disk"**.
   * Navega a la partición de la USB y selecciona el archivo `MOK.der` o `MOK.crt`.
   * Selecciona **"View Key"** para confirmar los datos (`Debian Secure Boot MOK`).
   * Selecciona **"Continue"** -> **"Yes"** -> Confirma con la contraseña (si estableciste una o confirma la inscripción).
   * Selecciona **"Reboot"**.
3. El equipo arrancará normalmente en Debian 13 bajo Secure Boot activado al 100%.

---

## ⚙️ Compilación Local (Opcional)

Si deseas compilar la imagen localmente en Debian/Ubuntu:

```bash
# 1. Instalar herramientas
sudo apt-get update
sudo apt-get install -y live-build debootstrap debian-archive-keyring \
  isolinux syslinux-utils sbsigntool openssl xorriso dosfstools mtools

# 2. Generar claves MOK
chmod +x scripts/*.sh auto/*
./scripts/generate-mok.sh mok/mok.key mok/mok.crt mok/mok.der

# 3. Configurar y compilar live-build
sudo DEBIAN_VERSION="trixie" lb config
sudo lb build

# 4. Firmar el kernel y reempaquetar la ISO final
sudo ./scripts/sign-and-repack.sh live-image-amd64.hybrid.iso debian-live-lenovo300e-signed.iso mok/mok.key mok/mok.crt mok/mok.der
```
