#!/bin/bash
# scripts/boot-test-iso.sh
# Boots the ISO under OVMF Secure Boot, waits for the live system to reach
# userspace through the serial console and fails on a Secure Boot rejection,
# a kernel panic or a system that never comes up.
#
# The ISO must carry `console=ttyS0,115200` in its live boot append (it is set
# by auto/config), which makes the kernel, shim/GRUB errors and the serial
# getty visible on the QEMU serial log. Reaching a login prompt there proves
# that the firmware accepted shim, shim accepted GRUB, GRUB loaded the kernel
# and userspace started.
#
# Requires: qemu-system-x86, ovmf, socat, tesseract-ocr,
# tesseract-ocr-eng and netpbm (OCR output is kept as boot evidence).

set -euo pipefail

ISO="${1:-}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-900}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
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
# which would leave the screenshot artifacts without a readable transcript.
if ! tesseract --list-langs 2>&1 | grep -qx 'eng'; then
    echo "ERROR: tesseract English language data not installed (tesseract-ocr-eng)"
    exit 1
fi

WORK_DIR="$(mktemp -d /tmp/iso-boot-XXXXXX)"
SERIAL_LOG="$WORK_DIR/serial.log"
QEMU_PID=""

cleanup() {
    if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    mkdir -p "$ARTIFACT_DIR"
    cp "$WORK_DIR/screen.png" "$ARTIFACT_DIR/" 2>/dev/null || true
    cp "$WORK_DIR/ocr.txt" "$ARTIFACT_DIR/" 2>/dev/null || true
    cp "$SERIAL_LOG" "$ARTIFACT_DIR/" 2>/dev/null || true
    chmod -R u+rwX "$WORK_DIR" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Screen and serial wording of a rejected Secure Boot chain: firmware, shim's
# "Verification failed: (0x1A) Security Violation", GRUB's shim_lock refusals.
REJECT_RE='security violation|verification failed|access denied|not authorized|invalid signature|bad signature|prohibited by secure boot'
# A rejected kernel or a broken initramfs usually ends here.
FAILURE_RE='no bootable|boot failed|kernel panic|not syncing|attempted to kill init'
# Proof that the kernel booted and userspace started.
BOOTED_RE='login:|welcome to debian|reached target multi-user|reached target graphical'

cp "$OVMF_VARS" "$WORK_DIR/vars.fd"

echo "=== Booting ${ISO} with OVMF Secure Boot (timeout ${BOOT_TIMEOUT}s) ==="
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
    -serial "file:$SERIAL_LOG" \
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

echo "=== Waiting for the live system to reach userspace ==="
BOOTED=0
DEADLINE=$(( $(date +%s) + BOOT_TIMEOUT ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        echo "ERROR: QEMU exited before the system finished booting"
        echo "--- serial log ---"
        cat "$SERIAL_LOG" 2>/dev/null || true
        exit 1
    fi
    if grep -qiE "$REJECT_RE" "$SERIAL_LOG" 2>/dev/null; then
        echo "ERROR: Secure Boot rejection reported on the serial console"
        grep -iE "$REJECT_RE" "$SERIAL_LOG" || true
        exit 1
    fi
    if grep -qiE "$FAILURE_RE" "$SERIAL_LOG" 2>/dev/null; then
        echo "ERROR: the kernel or the initramfs failed on the serial console"
        grep -iE "$FAILURE_RE" "$SERIAL_LOG" || true
        exit 1
    fi
    if grep -qiE "$BOOTED_RE" "$SERIAL_LOG" 2>/dev/null; then
        BOOTED=1
        break
    fi
    sleep "$POLL_INTERVAL"
done

if [ "$BOOTED" -ne 1 ]; then
    echo "ERROR: the live system did not reach userspace within ${BOOT_TIMEOUT}s"
    echo "--- serial log (last 40 lines) ---"
    tail -n 40 "$SERIAL_LOG" 2>/dev/null || true
    exit 1
fi

echo "OK: kernel booted and userspace started (login prompt on ttyS0)."
grep -iE 'Linux version|systemd\[1\]:' "$SERIAL_LOG" | head -n 3 || true

# Keep a screenshot as evidence (labwc/autologin on tty1, firmware text, ...).
printf 'screendump %s\n' "$WORK_DIR/screen.ppm" | socat - "UNIX-CONNECT:$WORK_DIR/monitor.sock" >/dev/null
sleep 1
printf 'quit\n' | socat - "UNIX-CONNECT:$WORK_DIR/monitor.sock" >/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ -s "$WORK_DIR/screen.ppm" ]; then
    pnmtopng "$WORK_DIR/screen.ppm" > "$WORK_DIR/screen.png"
    TEXT="$(tesseract "$WORK_DIR/screen.png" stdout 2>/dev/null || true)"
    printf '%s\n' "$TEXT" > "$WORK_DIR/ocr.txt"
    if [ -z "$TEXT" ]; then
        echo "WARNING: tesseract returned no text; inspect the screenshot artifact."
    fi
    echo "--- Boot screen text ---"
    printf '%s\n' "$TEXT"
    echo "------------------------"
    if printf '%s\n' "$TEXT" | grep -qiE "$REJECT_RE|$FAILURE_RE"; then
        echo "ERROR: the boot screen shows a Secure Boot rejection or a boot failure"
        exit 1
    fi
else
    echo "WARNING: QEMU did not produce a screendump; no screen evidence captured."
fi

echo "OK: system reached userspace under Secure Boot with no rejection (kernel signature chain is also checked by verify-iso.sh)."
