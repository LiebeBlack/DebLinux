#!/bin/bash
# scripts/boot-test-iso.sh
# Boots the ISO with OVMF Secure Boot enabled and fails if the firmware shows a
# Secure Boot rejection. This is a smoke test: it proves shim is accepted and
# GRUB is not rejected, not that the desktop session is reached.
#
# Requires: qemu-system-x86, ovmf, socat, tesseract-ocr,
# tesseract-ocr-eng and netpbm.

set -euo pipefail

ISO="${1:-}"
BOOT_WAIT="${BOOT_WAIT:-75}"
ARTIFACT_DIR="${BOOT_TEST_ARTIFACTS:-boot-test-artifacts}"

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "Usage: $0 <signed.iso>"
    exit 1
fi

OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
OVMF_VARS="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"

for FILE in "$OVMF_CODE" "$OVMF_VARS"; do
    if [ ! -f "$FILE" ]; then
        echo "ERROR: ${FILE} not found (install the 'ovmf' package)"
        exit 1
    fi
done

for TOOL in qemu-system-x86_64 socat tesseract pnmtopng; do
    if ! command -v "$TOOL" >/dev/null 2>&1; then
        echo "ERROR: ${TOOL} not found"
        exit 1
    fi
done

# Without the English traineddata tesseract exits non-zero and OCR is empty,
# which would make the boot test pass without inspecting the screen.
if ! tesseract --list-langs 2>&1 | grep -qx 'eng'; then
    echo "ERROR: tesseract English language data not installed (tesseract-ocr-eng)"
    exit 1
fi

WORK_DIR="$(mktemp -d /tmp/iso-boot-XXXXXX)"
QEMU_PID=""

cleanup() {
    if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    mkdir -p "$ARTIFACT_DIR"
    cp "$WORK_DIR/screen.png" "$ARTIFACT_DIR/" 2>/dev/null || true
    cp "$WORK_DIR/ocr.txt" "$ARTIFACT_DIR/" 2>/dev/null || true
    cp "$WORK_DIR/serial.log" "$ARTIFACT_DIR/" 2>/dev/null || true
    chmod -R u+rwX "$WORK_DIR" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cp "$OVMF_VARS" "$WORK_DIR/vars.fd"

echo "=== Booting ${ISO} with OVMF Secure Boot (${BOOT_WAIT}s) ==="
qemu-system-x86_64 \
    -machine q35 \
    -accel tcg,thread=multi \
    -m 2048 -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$WORK_DIR/vars.fd" \
    -drive file="$ISO",format=raw,media=cdrom,readonly=on \
    -boot order=d \
    -display none -vga std \
    -monitor "unix:$WORK_DIR/monitor.sock,server=on,wait=off" \
    -serial "file:$WORK_DIR/serial.log" \
    -no-reboot &
QEMU_PID=$!

for _ in $(seq 1 30); do
    [ -S "$WORK_DIR/monitor.sock" ] && break
    sleep 1
done
if [ ! -S "$WORK_DIR/monitor.sock" ]; then
    echo "ERROR: QEMU monitor socket was not created"
    exit 1
fi

sleep "$BOOT_WAIT"

if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "ERROR: QEMU exited before the screenshot could be taken"
    cat "$WORK_DIR/serial.log" 2>/dev/null || true
    exit 1
fi

printf 'screendump %s\n' "$WORK_DIR/screen.ppm" | socat - "UNIX-CONNECT:$WORK_DIR/monitor.sock" >/dev/null
sleep 1
printf 'quit\n' | socat - "UNIX-CONNECT:$WORK_DIR/monitor.sock" >/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ ! -s "$WORK_DIR/screen.ppm" ]; then
    echo "ERROR: QEMU did not produce a screendump"
    exit 1
fi

pnmtopng "$WORK_DIR/screen.ppm" > "$WORK_DIR/screen.png"
TEXT="$(tesseract "$WORK_DIR/screen.png" stdout 2>/dev/null || true)"
printf '%s\n' "$TEXT" > "$WORK_DIR/ocr.txt"

if [ -z "$TEXT" ]; then
    echo "WARNING: tesseract returned no text; inspect the screenshot artifact."
fi

echo "--- Boot screen text ---"
printf '%s\n' "$TEXT"
echo "------------------------"

if printf '%s\n' "$TEXT" | grep -qiE 'security violation|verification failed|access denied|not authorized'; then
    echo "ERROR: firmware reported a Secure Boot rejection"
    exit 1
fi

if printf '%s\n' "$TEXT" | grep -qiE 'no bootable|boot failed'; then
    echo "ERROR: firmware could not boot the ISO"
    exit 1
fi

echo "OK: no Secure Boot rejection detected (shim/GRUB smoke test; the kernel MOK signature is checked by verify-iso.sh)."
