#!/bin/bash
# scripts/verify-iso.sh
# Verifies that the signed ISO is a complete UEFI Secure Boot artifact before
# it gets published as a build artifact:
#   1. MOK enrollment material + EFI boot files on the ISO9660 tree
#   2. El Torito UEFI boot entry pointing to the GRUB EFI image, and the
#      hybrid MBR/GPT system area that makes the ISO bootable from USB
#   3. shim (BOOTX64.EFI), GRUB (GRUBX64.EFI) and MokManager (MMX64.EFI)
#      inside that EFI image
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

# 1) MOK material and the EFI boot set on the ISO filesystem.
# Directory listings are matched by basename and case-insensitively: the
# ISO9660 tree may store BOOTX64.EFI and xorriso prints quoted paths.
iso_has_file() {
    local DIR="$1"
    local BASE="$2"
    local EXTRA="${3:-}"
    local LISTING

    LISTING="$(xorriso -indev "$ISO" -find "$DIR" $EXTRA -type f 2>/dev/null \
        | sed "s/^'//; s/'$//" || true)"
    printf '%s\n' "$LISTING" \
        | awk -F/ -v b="$BASE" 'tolower($NF) == tolower(b) { found = 1 } END { exit !found }'
}

for REQUIRED in MOK.crt MOK.der MOK.cer; do
    # -maxdepth 1 keeps this to the ISO root, so /live/MOK.der cannot satisfy it.
    iso_has_file / "$REQUIRED" "-maxdepth 1" \
        || fail "/${REQUIRED} is missing from the ISO"
done
iso_has_file /live MOK.der || fail "/live/MOK.der is missing from the ISO"
for REQUIRED in bootx64.efi grubx64.efi mmx64.efi grub.cfg; do
    iso_has_file /EFI/boot "$REQUIRED" \
        || fail "/EFI/boot/${REQUIRED} is missing from the ISO (firmware boot-from-file would fail)"
done
echo "OK: MOK certificate, MOK.der, MOK.cer and the EFI boot set are present."

# 2) El Torito UEFI boot entry must exist and use the GRUB EFI image
BOOT_REPORT="$(xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null || true)"
printf '%s\n' "$BOOT_REPORT" | grep -q 'UEFI' \
    || fail "no UEFI El Torito boot entry in the ISO"
printf '%s\n' "$BOOT_REPORT" | grep -q '/boot/grub/efi.img' \
    || fail "UEFI boot entry does not point to /boot/grub/efi.img"
echo "OK: El Torito UEFI boot entry present."

# 2b) The hybrid MBR/GPT system area must still be there, otherwise the image
#     only boots as a CD through El Torito and not from a USB stick, where UEFI
#     firmware needs a partitioned device with a FAT EFI boot image.
# Check the protective GPT header signature at LBA 1 instead of parsing the
# human-readable report, whose wording changes between xorriso versions.
GPT_SIG="$( { dd if="$ISO" bs=512 skip=1 count=1 status=none 2>/dev/null | head -c 8; } || true)"
if [ "$GPT_SIG" != "EFI PART" ]; then
    echo "System area report for diagnosis:"
    xorriso -indev "$ISO" -report_system_area plain 2>/dev/null || true
    fail "no GPT partition table in the ISO system area (USB UEFI boot would be lost)"
fi
echo "OK: hybrid MBR/GPT system area present."

# 3) The EFI boot image must carry shim, GRUB and MokManager. MokManager is
#    mandatory: shim looks for mmx64.efi on the same FAT filesystem it was
#    loaded from, so it cannot be provided by the ISO9660 tree alone.
xorriso -osirrox on -indev "$ISO" -extract /boot/grub/efi.img "$WORK_DIR/efi.img" >/dev/null 2>&1 \
    || fail "cannot extract /boot/grub/efi.img"
EFI_CONTENT="$(mdir -i "$WORK_DIR/efi.img" ::/EFI/boot 2>/dev/null || true)"
printf '%s\n' "$EFI_CONTENT" | grep -qi 'BOOTX64' \
    || fail "shim (BOOTX64.EFI) missing from the EFI boot image"
printf '%s\n' "$EFI_CONTENT" | grep -qi 'GRUBX64' \
    || fail "GRUB (GRUBX64.EFI) missing from the EFI boot image"
printf '%s\n' "$EFI_CONTENT" | grep -qi 'MMX64' \
    || fail "MokManager (MMX64.EFI) missing from the EFI boot image; MOK enrollment from the boot medium would be impossible"
echo "OK: EFI boot image contains shim + GRUB + MokManager."

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

HAVE_VMLINUZ=0
for KERNEL in "${KERNELS[@]}"; do
    sbverify --cert "$MOK_CRT" "$KERNEL" >/dev/null 2>&1 \
        || fail "kernel signature does not verify against the MOK certificate: $(basename "$KERNEL")"
    if [ "$(basename "$KERNEL")" = 'vmlinuz' ]; then
        HAVE_VMLINUZ=1
    fi
done
[ "$HAVE_VMLINUZ" -eq 1 ] || fail "/live/vmlinuz is missing or was not signed"
echo "OK: ${#KERNELS[@]} kernel image(s) signed by the MOK key."

echo "=== ISO verification passed ==="
