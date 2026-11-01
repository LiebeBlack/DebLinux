#!/bin/bash
# scripts/verify-iso.sh
# Verifies that the final ISO is a valid UEFI-only Secure Boot artifact:
#   1. GPT at LBA 1 and a protective MBR (0xEE) at LBA 0
#   2. no APM, no legacy BIOS boot code and no BIOS El Torito entry
#   3. a UEFI El Torito entry that points at the appended ESP
#   4. shim signed by the Microsoft UEFI CA and GRUB signed by Debian
#   5. every kernel in /live signed by Debian (no MOK involved)
#
# It intentionally does not require MokManager, MOK certificates or a
# /EFI/boot copy on the ISO9660 tree: the Debian-signed chain boots directly.

set -euo pipefail

ISO="${1:-}"

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "Usage: $0 <uefi.iso>"
    exit 1
fi

WORK_DIR="$(mktemp -d /tmp/iso-verify-XXXXXX)"
# xorriso restores the ISO's read-only directory modes on extraction, so make
# the tree writable before removing it.
cleanup() {
    chmod -R u+rwX "$WORK_DIR" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
    echo "ERROR: $*"
    exit 1
}

echo "=== Verifying UEFI Secure Boot chain in ${ISO} ==="

# 1) System area: protective MBR + GPT, no BIOS code, no APM.
GPT_SIG="$( { dd if="$ISO" bs=512 skip=1 count=1 status=none 2>/dev/null | head -c 8; } || true)"
[ "$GPT_SIG" = "EFI PART" ] || fail "no GPT header at LBA 1 (USB UEFI boot would be lost)"

MBR_SIG="$(dd if="$ISO" bs=1 skip=510 count=2 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[ "$MBR_SIG" = "55aa" ] || fail "no MBR signature at LBA 0 (expected a protective MBR)"

MBR_TYPE="$(dd if="$ISO" bs=1 skip=450 count=1 status=none 2>/dev/null | od -An -tu1 | tr -d ' \n')"
[ "$MBR_TYPE" = "238" ] || fail "first MBR partition is not protective type 0xEE (got ${MBR_TYPE:-none})"

APM_SIG="$(dd if="$ISO" bs=1 count=2 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[ "$APM_SIG" != "4552" ] || fail "Apple Partition Map found in the system area"

BOOT_CODE_BYTES="$(dd if="$ISO" bs=1 count=440 status=none 2>/dev/null | tr -d '\000' | wc -c)"
[ "$BOOT_CODE_BYTES" -eq 0 ] || fail "legacy BIOS boot code found in the MBR (${BOOT_CODE_BYTES} nonzero bytes)"

echo "OK: GPT + protective MBR, no APM and no BIOS boot code."

# 2) El Torito must have exactly one entry, it must be UEFI, and it must use
# the appended ESP. xorriso 1.5.6 reports an image outside the ISO9660 tree
# as "El Torito img blks : N  <blocks>"; older/newer versions may print the
# --interval:appended_partition_2 pseudo-path. Accept both for that entry.
BOOT_REPORT="$(xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null || true)"
BOOT_IMG_COUNT="$(printf '%s\n' "$BOOT_REPORT" | grep -c '^El Torito boot img :' || true)"
[ "$BOOT_IMG_COUNT" -eq 1 ] \
    || fail "expected exactly one El Torito boot image (got ${BOOT_IMG_COUNT})"
UEFI_ENTRY="$(printf '%s\n' "$BOOT_REPORT" \
    | sed -n 's/^El Torito boot img : *\([0-9][0-9]*\)  *UEFI  y .*/\1/p' | head -n 1)"
[ -n "$UEFI_ENTRY" ] || fail "no UEFI El Torito boot entry in the ISO"
UEFI_TORITO_LINE="$(printf '%s\n' "$BOOT_REPORT" \
    | grep -E "^El Torito (img blks|blks|img path) *: *${UEFI_ENTRY}  " || true)"
if [ -n "$UEFI_TORITO_LINE" ]; then
    # A path to an ISO9660 file would be resolved as a path here; only the
    # appended-partition pseudo-path or a block-range (outside the ISO tree)
    # is acceptable.
    printf '%s\n' "$UEFI_TORITO_LINE" \
        | grep -qE '^(El Torito (img blks|blks) *: *[0-9]+  [0-9]+$|El Torito img path *: *[0-9]+  .*appended_partition_2)' \
        || fail "the UEFI El Torito entry does not use the appended ESP"
else
    # No path line: xorriso could not resolve the image in the ISO tree and
    # reports LBA 0xffffffff, which is what an appended ESP looks like.
    printf '%s\n' "$BOOT_REPORT" \
        | grep -qE "^El Torito boot img : *${UEFI_ENTRY}  *UEFI .*4294967295$" \
        || fail "the UEFI El Torito entry does not use the appended ESP"
fi
if printf '%s\n' "$BOOT_REPORT" | grep -qiE '\bBIOS\b|PC-BIOS'; then
    fail "a legacy BIOS El Torito entry is still present"
fi
echo "OK: El Torito UEFI entry present (no BIOS entry)."

# 3) The EFI image must carry shim, GRUB and their config.
xorriso -osirrox on -indev "$ISO" -extract /boot/grub/efi.img "$WORK_DIR/efi.img" >/dev/null 2>&1 \
    || fail "cannot extract /boot/grub/efi.img"
EFI_CONTENT="$(mdir -i "$WORK_DIR/efi.img" ::/EFI/boot 2>/dev/null || true)"
printf '%s\n' "$EFI_CONTENT" | grep -qi 'BOOTX64' \
    || fail "shim (BOOTX64.EFI) missing from the EFI boot image"
printf '%s\n' "$EFI_CONTENT" | grep -qi 'GRUBX64' \
    || fail "GRUB (GRUBX64.EFI) missing from the EFI boot image"
if printf '%s\n' "$EFI_CONTENT" | grep -qi 'MMX64'; then
    echo "WARNING: MokManager (MMX64.EFI) is present but unused; no MOK is enrolled."
fi
echo "OK: EFI boot image contains shim + GRUB."

# 4) Firmware trusts Microsoft's CA; shim trusts Debian's CA.
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

# 5) Every kernel in /live must carry Debian's signature. MOK is not used.
xorriso -osirrox on -indev "$ISO" -extract /live "$WORK_DIR/live" >/dev/null 2>&1 \
    || fail "cannot extract /live from the ISO"
mapfile -t KERNELS < <(find "$WORK_DIR/live" -type f -name 'vmlinuz*' | sort)
[ "${#KERNELS[@]}" -gt 0 ] || fail "no kernel image found in /live"

HAVE_VMLINUZ=0
for KERNEL in "${KERNELS[@]}"; do
    KERNEL_SIGNERS="$(sbverify --list "$KERNEL" 2>/dev/null || true)"
    if [ -z "$KERNEL_SIGNERS" ]; then
        fail "kernel is unsigned: $(basename "$KERNEL")"
    fi
    printf '%s\n' "$KERNEL_SIGNERS" | grep -qi 'debian' \
        || fail "kernel is not Debian-signed: $(basename "$KERNEL")"
    if [ "$(basename "$KERNEL")" = 'vmlinuz' ]; then
        HAVE_VMLINUZ=1
    fi
done
[ "$HAVE_VMLINUZ" -eq 1 ] || fail "/live/vmlinuz is missing or is not a regular file"
echo "OK: ${#KERNELS[@]} kernel image(s) Debian-signed; no MOK required."

echo "=== ISO verification passed ==="
