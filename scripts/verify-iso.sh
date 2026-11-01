#!/bin/bash
# scripts/verify-iso.sh
# Verifies that the signed ISO is a complete UEFI Secure Boot artifact before
# it gets published as a build artifact:
#   1. MOK enrollment material + EFI boot files on the ISO9660 tree
#   2. El Torito UEFI boot entry pointing to the GRUB EFI image
#   3. shim (BOOTX64.EFI) and GRUB (GRUBX64.EFI) inside that EFI image
#   4. shim signed by the Microsoft UEFI CA and GRUB signed by Debian
#   5. kernel image(s) signed by the generated MOK certificate

set -euo pipefail

ISO="${1:-}"
MOK_CRT="${2:-mok/mok.crt}"

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "Usage: $0 <signed.iso> [mok.crt]"
    exit 1
fi

if [ ! -f "$MOK_CRT" ]; then
    echo "ERROR: MOK certificate not found: $MOK_CRT"
    exit 1
fi

WORK_DIR="$(mktemp -d /tmp/iso-verify-XXXXXX)"
# xorriso restores the ISO's read-only directory modes on extraction, so make
# the tree writable before removing it. Without this the cleanup fails with
# "Permission denied" and the script exits 1 even after a successful check.
cleanup() {
    chmod -R u+rwX "$WORK_DIR" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
    echo "ERROR: $*"
    exit 1
}

echo "=== Verifying Secure Boot chain in ${ISO} ==="

# 1) MOK material and EFI boot files on the ISO filesystem
ISO_PATHS="$(xorriso -indev "$ISO" -find / -maxdepth 3 2>/dev/null || true)"
for REQUIRED in /MOK.crt /MOK.der /live/MOK.der /EFI/boot/bootx64.efi /EFI/boot/mmx64.efi; do
    printf '%s\n' "$ISO_PATHS" | grep -qF "$REQUIRED" \
        || fail "${REQUIRED} is missing from the ISO"
done
echo "OK: MOK certificate, MOK.der and EFI boot files are present."

# 2) El Torito UEFI boot entry must exist and use the GRUB EFI image
BOOT_REPORT="$(xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null || true)"
printf '%s\n' "$BOOT_REPORT" | grep -q 'UEFI' \
    || fail "no UEFI El Torito boot entry in the ISO"
printf '%s\n' "$BOOT_REPORT" | grep -q '/boot/grub/efi.img' \
    || fail "UEFI boot entry does not point to /boot/grub/efi.img"
echo "OK: El Torito UEFI boot entry present."

# 3) The EFI boot image must carry shim and GRUB
xorriso -osirrox on -indev "$ISO" -extract /boot/grub/efi.img "$WORK_DIR/efi.img" >/dev/null 2>&1 \
    || fail "cannot extract /boot/grub/efi.img"
EFI_CONTENT="$(mdir -i "$WORK_DIR/efi.img" ::/EFI/boot 2>/dev/null || true)"
printf '%s\n' "$EFI_CONTENT" | grep -qi 'BOOTX64' \
    || fail "shim (BOOTX64.EFI) missing from the EFI boot image"
printf '%s\n' "$EFI_CONTENT" | grep -qi 'GRUBX64' \
    || fail "GRUB (GRUBX64.EFI) missing from the EFI boot image"
echo "OK: EFI boot image contains shim + GRUB."

# 4) The boot volume itself must carry a trusted chain: shim is signed by
#    Microsoft (trusted by the firmware) and GRUB by Debian (trusted by shim).
#    Check the binaries inside efi.img, which is what the firmware actually
#    boots, instead of the copies on the ISO9660 tree.
mcopy -i "$WORK_DIR/efi.img" ::/EFI/boot/BOOTX64.EFI "$WORK_DIR/bootx64.efi" >/dev/null 2>&1 \
    || fail "cannot extract shim (BOOTX64.EFI) from the EFI boot image"
SHIM_SIGNERS="$(sbverify --list "$WORK_DIR/bootx64.efi" 2>/dev/null || true)"
printf '%s\n' "$SHIM_SIGNERS" | grep -qi 'microsoft' \
    || fail "shim is not signed by the Microsoft UEFI CA"
echo "OK: shim is Microsoft UEFI CA signed."

mcopy -i "$WORK_DIR/efi.img" ::/EFI/boot/GRUBX64.EFI "$WORK_DIR/grubx64.efi" >/dev/null 2>&1 \
    || fail "cannot extract GRUB (GRUBX64.EFI) from the EFI boot image"
GRUB_SIGNERS="$(sbverify --list "$WORK_DIR/grubx64.efi" 2>/dev/null || true)"
printf '%s\n' "$GRUB_SIGNERS" | grep -qi 'debian' \
    || fail "GRUB is not signed by Debian; shim will reject it under Secure Boot"
echo "OK: GRUB is Debian-signed (trusted by shim)."

# 5) Every kernel in /live must verify against the generated MOK certificate
xorriso -osirrox on -indev "$ISO" -extract /live "$WORK_DIR/live" >/dev/null 2>&1 \
    || fail "cannot extract /live from the ISO"
mapfile -t KERNELS < <(find "$WORK_DIR" -type f -name 'vmlinuz*' | sort)
[ "${#KERNELS[@]}" -gt 0 ] || fail "no kernel image found in /live"

UNVERSIONED=0
for KERNEL in "${KERNELS[@]}"; do
    sbverify --cert "$MOK_CRT" "$KERNEL" >/dev/null 2>&1 \
        || fail "kernel signature does not verify against the MOK certificate: $(basename "$KERNEL")"
    if [ "$(basename "$KERNEL")" = 'vmlinuz' ]; then
        UNVERSIONED=1
    fi
done
[ "$UNVERSIONED" -eq 1 ] || fail "/live/vmlinuz is missing or was not signed"
echo "OK: ${#KERNELS[@]} kernel image(s) signed by the MOK key."

echo "=== ISO verification passed ==="
