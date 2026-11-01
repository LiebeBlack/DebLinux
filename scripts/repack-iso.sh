#!/bin/bash
# scripts/repack-iso.sh
# Rebuilds the live-build ISO tree as a UEFI-only image:
#   - valid GPT in LBA 1 with a protective MBR partition of type 0xEE
#   - the EFI boot image (shim + Debian-signed GRUB) appended as an ESP
#   - an El Torito UEFI entry that points at that ESP
#   - no APM, no BIOS boot code and no legacy BIOS El Torito entry
#
# The Debian kernel is left untouched: Debian signs the linux-image kernels,
# and this image boots under Secure Boot through shim -> Debian GRUB -> kernel
# without enrolling a MOK.

set -euo pipefail

ORIG_ISO="${1:-}"
FINAL_ISO="${2:-}"

if [ -z "$ORIG_ISO" ] || [ -z "$FINAL_ISO" ]; then
    echo "Usage: $0 <input_original.iso> <output_final.iso>"
    exit 1
fi

if [ ! -f "$ORIG_ISO" ]; then
    echo "ERROR: Input ISO not found: $ORIG_ISO"
    exit 1
fi

WORK_DIR="$(mktemp -d /tmp/iso-repack-XXXXXX)"
cleanup() {
    # xorriso restores the ISO's read-only directory modes on extraction.
    chmod -R u+rwX "$WORK_DIR" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

EXTRACT_TARGET="$WORK_DIR/extracted"

echo "=== Step 1: Extracting the ISO tree from ${ORIG_ISO} ==="
xorriso -osirrox on -indev "$ORIG_ISO" -extract / "$EXTRACT_TARGET"

# Depending on the xorriso version, extracting "/" places the ISO contents
# directly in EXTRACT_TARGET or below an extra directory level. Discover the
# real tree root instead of assuming one of the two layouts.
ISO_TREE="$EXTRACT_TARGET"
if [ ! -d "$ISO_TREE/live" ]; then
    ISO_TREE="$(find "$EXTRACT_TARGET" -maxdepth 3 -type d -name live 2>/dev/null \
        | head -n 1 | xargs -r dirname)"
fi

if [ -z "$ISO_TREE" ] || [ ! -d "$ISO_TREE/live" ] || [ ! -f "$ISO_TREE/boot/grub/efi.img" ]; then
    echo "ERROR: unexpected tree layout after extracting ${ORIG_ISO}:"
    find "$EXTRACT_TARGET" -maxdepth 3 2>/dev/null | head -n 40
    exit 1
fi
echo "ISO tree root: ${ISO_TREE}"
chmod -R u+rwX "$ISO_TREE"

echo "=== Step 2: Keeping the Debian-signed kernel as /live/vmlinuz ==="
# live-build usually ships /live/vmlinuz as a symlink to vmlinuz-<version>.
# The verify script and live-boot both expect a real file at /live/vmlinuz,
# so stage a copy of the Debian-signed kernel without modifying its signature.
mapfile -t KERNELS < <(find "$ISO_TREE/live" -maxdepth 1 -type f -name 'vmlinuz-*' | sort)
if [ "${#KERNELS[@]}" -eq 0 ] && [ -f "$ISO_TREE/live/vmlinuz" ]; then
    KERNELS=("$ISO_TREE/live/vmlinuz")
fi
if [ "${#KERNELS[@]}" -eq 0 ]; then
    echo "ERROR: No vmlinuz kernel found in ${ISO_TREE}/live!"
    exit 1
fi

KERNEL_SRC="${KERNELS[0]}"
if [ -L "$ISO_TREE/live/vmlinuz" ] || [ ! -f "$ISO_TREE/live/vmlinuz" ] \
    || ! cmp -s "$KERNEL_SRC" "$ISO_TREE/live/vmlinuz"; then
    echo "Staging Debian-signed kernel $(basename "$KERNEL_SRC") as /live/vmlinuz..."
    rm -f "$ISO_TREE/live/vmlinuz"
    cp -f "$KERNEL_SRC" "$ISO_TREE/live/vmlinuz"
fi
chmod 644 "$ISO_TREE/live/vmlinuz"
echo "Kernel left as shipped by Debian (no sbsign, no MOK)."

echo "=== Step 3: Building the final UEFI-only ISO ==="
# Keep the ISO metadata of the original image (volume id, application,
# publisher, preparer) so the live medium looks exactly like live-build's.
PVD_INFO="$(xorriso -indev "$ORIG_ISO" -pvd_info 2>/dev/null || true)"
pvd_field() {
    printf '%s\n' "$PVD_INFO" | sed -n "s/^$1 *: //p" | head -n 1
}
VOLUME_ID="$(pvd_field 'Volume Id')"
APP_ID="$(pvd_field 'App Id')"
PUBLISHER_ID="$(pvd_field 'Publisher Id')"
PREPARER_ID="$(pvd_field 'Preparer Id')"

# This is intentionally not the old "-isohybrid-gpt-basdat" line: xorriso
# documents that option as "works only with -isohybrid-mbr", so without an MBR
# template it is silently ignored and no GPT is written (the CI failure this
# script replaces). -append_partition + -appended_part_as_gpt builds a valid
# GPT with a protective 0xEE MBR, an ISO9660 partition and a real ESP, while
# -partition_offset 16 moves the ISO filesystem off LBA 0.
MKISOFS_ARGS=(
    -as mkisofs
    -R -r -J -joliet-long -l -iso-level 3
    -append_partition 2 0xef "$ISO_TREE/boot/grub/efi.img"
    -appended_part_as_gpt
    -partition_offset 16
    -e '--interval:appended_partition_2:all::'
    -no-emul-boot
)
if [ -n "$VOLUME_ID" ]; then
    MKISOFS_ARGS+=(-V "$VOLUME_ID")
fi
if [ -n "$APP_ID" ]; then
    MKISOFS_ARGS+=(-A "$APP_ID")
fi
if [ -n "$PUBLISHER_ID" ]; then
    MKISOFS_ARGS+=(-publisher "$PUBLISHER_ID")
fi
if [ -n "$PREPARER_ID" ]; then
    MKISOFS_ARGS+=(-p "$PREPARER_ID")
fi
# live-build pins every ISO volume date to SOURCE_DATE_EPOCH; do the same so the
# rebuilt image keeps the build reproducible.
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    MKISOFS_ARGS+=("--modification-date=$(date --utc -d "@${SOURCE_DATE_EPOCH}" +%Y%m%d%H%M%S00)")
fi

rm -f "$FINAL_ISO"
echo "Executing xorriso -as mkisofs to generate the final UEFI ISO..."
xorriso "${MKISOFS_ARGS[@]}" -o "$FINAL_ISO" "$ISO_TREE"

echo "=== Step 4: Verification of final ISO ==="
if [ ! -f "$FINAL_ISO" ]; then
    echo "ERROR: Failed to create $FINAL_ISO"
    exit 1
fi

# The image must have exactly one El Torito entry and it must be UEFI.
# xorriso 1.5.6 reports an entry that lives outside the ISO9660 tree (i.e. in
# the appended ESP) as "El Torito img blks : N  <blocks>" instead of a path;
# other versions may print the --interval:appended_partition_2 pseudo-path.
# Accept both for the UEFI entry only, and reject a path to the ISO9660 copy.
TORITO_REPORT="$(xorriso -indev "$FINAL_ISO" -report_el_torito plain 2>/dev/null || true)"
BOOT_IMG_COUNT="$(printf '%s\n' "$TORITO_REPORT" | grep -c '^El Torito boot img :' || true)"
if [ "$BOOT_IMG_COUNT" -ne 1 ]; then
    echo "ERROR: expected exactly one El Torito boot image (got ${BOOT_IMG_COUNT})."
    printf '%s\n' "$TORITO_REPORT"
    exit 1
fi
UEFI_ENTRY="$(printf '%s\n' "$TORITO_REPORT" \
    | sed -n 's/^El Torito boot img : *\([0-9][0-9]*\)  *UEFI  y .*/\1/p' | head -n 1)"
if [ -z "$UEFI_ENTRY" ]; then
    echo "ERROR: no UEFI El Torito boot entry in the final ISO."
    printf '%s\n' "$TORITO_REPORT"
    exit 1
fi
UEFI_TORITO_LINE="$(printf '%s\n' "$TORITO_REPORT" \
    | grep -E "^El Torito (img blks|blks|img path) *: *${UEFI_ENTRY}  " || true)"
if [ -n "$UEFI_TORITO_LINE" ]; then
    # A path to an ISO9660 file would be resolved as a path here; only the
    # appended-partition pseudo-path or a block-range (outside the ISO tree)
    # is acceptable.
    printf '%s\n' "$UEFI_TORITO_LINE" \
        | grep -qE '^(El Torito (img blks|blks) *: *[0-9]+  [0-9]+$|El Torito img path *: *[0-9]+  .*appended_partition_2)' \
        || { echo "ERROR: the UEFI El Torito entry does not use the appended ESP."; \
             printf '%s\n' "$TORITO_REPORT"; exit 1; }
else
    # xorriso could not resolve the image inside the ISO tree (it prints no
    # path line and the boot-img LBA is 0xffffffff), which is expected for an
    # appended partition. Reject any other unresolved UEFI entry.
    printf '%s\n' "$TORITO_REPORT" \
        | grep -qE "^El Torito boot img : *${UEFI_ENTRY}  *UEFI .*4294967295$" \
        || { echo "ERROR: the UEFI El Torito entry does not use the appended ESP."; \
             printf '%s\n' "$TORITO_REPORT"; exit 1; }
fi

# GPT header at LBA 1.
GPT_SIG="$( { dd if="$FINAL_ISO" bs=512 skip=1 count=1 status=none 2>/dev/null | head -c 8; } || true)"
if [ "$GPT_SIG" != "EFI PART" ]; then
    echo "ERROR: no GPT partition table in the final ISO system area."
    xorriso -indev "$FINAL_ISO" -report_system_area plain 2>/dev/null || true
    exit 1
fi

# Protective MBR: 0x55AA signature and a first partition of type 0xEE.
MBR_SIG="$(dd if="$FINAL_ISO" bs=1 skip=510 count=2 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n')"
if [ "$MBR_SIG" != "55aa" ]; then
    echo "ERROR: final ISO has no MBR signature at LBA 0 (expected a protective MBR)."
    exit 1
fi
MBR_TYPE="$(dd if="$FINAL_ISO" bs=1 skip=450 count=1 status=none 2>/dev/null | od -An -tu1 | tr -d ' \n')"
if [ "$MBR_TYPE" != "238" ]; then
    echo "ERROR: first MBR partition is not protective type 0xEE (got ${MBR_TYPE:-none})."
    exit 1
fi

# No Apple Partition Map and no legacy BIOS boot code.
APM_SIG="$(dd if="$FINAL_ISO" bs=1 count=2 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n')"
if [ "$APM_SIG" = "4552" ]; then
    echo "ERROR: Apple Partition Map found in the final ISO system area."
    exit 1
fi
BOOT_CODE_BYTES="$(dd if="$FINAL_ISO" bs=1 count=440 status=none 2>/dev/null | tr -d '\000' | wc -c)"
if [ "$BOOT_CODE_BYTES" -ne 0 ]; then
    echo "ERROR: legacy BIOS boot code found in the MBR (${BOOT_CODE_BYTES} nonzero bytes)."
    exit 1
fi

# The EFI image inside the ISO filesystem must contain shim and GRUB.
EFI_IMG_FINAL="$WORK_DIR/efi-final.img"
if ! xorriso -osirrox on -indev "$FINAL_ISO" -extract /boot/grub/efi.img "$EFI_IMG_FINAL" >/dev/null 2>&1; then
    echo "ERROR: /boot/grub/efi.img missing from the final ISO."
    exit 1
fi
EFI_IMAGE_CONTENT="$(mdir -i "$EFI_IMG_FINAL" ::/EFI/boot 2>/dev/null || true)"
for REQUIRED in BOOTX64 GRUBX64; do
    if ! printf '%s\n' "$EFI_IMAGE_CONTENT" | grep -qi "$REQUIRED"; then
        echo "ERROR: ${REQUIRED}.EFI missing from the EFI boot image."
        printf '%s\n' "$EFI_IMAGE_CONTENT"
        exit 1
    fi
done
if printf '%s\n' "$EFI_IMAGE_CONTENT" | grep -qi 'MMX64'; then
    echo "WARNING: MokManager (MMX64.EFI) is present but unused; no MOK is enrolled."
fi

echo "OK: GPT + protective MBR, appended ESP, no APM and no BIOS boot code."
echo "Final ISO size: $(du -h "$FINAL_ISO" | cut -f1)"
echo "Generating SHA256 checksum..."
sha256sum "$FINAL_ISO" > "${FINAL_ISO}.sha256"
cat "${FINAL_ISO}.sha256"

echo "=== UEFI ISO repack complete ==="
