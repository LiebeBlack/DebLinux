#!/bin/bash
# scripts/sign-and-repack.sh
# Extracts the Debian live ISO tree, signs its kernel(s) with the MOK key,
# rebuilds the EFI boot image with MokManager, injects the MOK certificates and
# the EFI boot set into that tree, and builds the final hybrid UEFI ISO with the
# same mkisofs options live-build used (mirrored in /etc/auto/config).

set -euo pipefail

ORIG_ISO="${1:-}"
FINAL_ISO="${2:-}"
MOK_KEY="${3:-mok/mok.key}"
MOK_CRT="${4:-mok/mok.crt}"
MOK_DER="${5:-mok/mok.der}"
MOK_CER="${6:-${MOK_DER%.der}.cer}"

if [ -z "$ORIG_ISO" ] || [ -z "$FINAL_ISO" ]; then
    echo "Usage: $0 <input_original.iso> <output_final.iso> [mok.key] [mok.crt] [mok.der] [mok.cer]"
    exit 1
fi

if [ ! -f "$ORIG_ISO" ]; then
    echo "ERROR: Input ISO not found: $ORIG_ISO"
    exit 1
fi

if [ ! -f "$MOK_KEY" ] || [ ! -f "$MOK_CRT" ]; then
    echo "ERROR: MOK key or certificate not found ($MOK_KEY, $MOK_CRT)"
    exit 1
fi

# Ensure DER format exists for MokManager
if [ ! -f "$MOK_DER" ]; then
    echo "Converting $MOK_CRT to DER format ($MOK_DER)..."
    openssl x509 -in "$MOK_CRT" -outform DER -out "$MOK_DER"
fi

# .cer is the same DER certificate under the extension some firmware file
# pickers filter on; derive it when an older keypair did not ship one.
if [ ! -f "$MOK_CER" ]; then
    cp "$MOK_DER" "$MOK_CER"
fi

# MokManager is the shim component that enrolls the MOK key, so the build host
# must provide it. Debian ships mmx64.efi.signed, Ubuntu ships mmx64.efi; both
# are signed by the Microsoft UEFI CA and therefore accepted by the firmware.
MMX_SRC=""
for CANDIDATE in /usr/lib/shim/mmx64.efi.signed /usr/lib/shim/mmx64.efi; do
    if [ -f "$CANDIDATE" ]; then
        MMX_SRC="$CANDIDATE"
        break
    fi
done

if [ -z "$MMX_SRC" ]; then
    echo "ERROR: MokManager (mmx64.efi) not found. Install 'shim-signed' on the build host."
    exit 1
fi

WORK_DIR="$(mktemp -d /tmp/iso-sign-XXXXXX)"
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

echo "=== Step 2: Signing kernel executables with sbsign ==="
mapfile -t KERNELS < <(find "$ISO_TREE/live" -maxdepth 1 -type f -name 'vmlinuz*' | sort)

if [ "${#KERNELS[@]}" -eq 0 ]; then
    echo "ERROR: No vmlinuz executable found in ${ISO_TREE}/live!"
    exit 1
fi

for KERNEL in "${KERNELS[@]}"; do
    KNAME=$(basename "$KERNEL")
    echo "Signing kernel binary: ${KNAME}..."
    sbsign --key "$MOK_KEY" --cert "$MOK_CRT" --output "${KERNEL}.signed" "$KERNEL"

    echo "Verifying signature on ${KNAME}..."
    sbverify --cert "$MOK_CRT" "${KERNEL}.signed"

    mv -f "${KERNEL}.signed" "$KERNEL"
    chmod 644 "$KERNEL"
done

# /live/vmlinuz is a symlink on live-build images; when it is a separate file it
# has to carry the signed image as well.
SIGNED_KERNEL="$(printf '%s\n' "${KERNELS[@]}" | grep -v '/vmlinuz$' | head -n 1 || true)"
SIGNED_KERNEL="${SIGNED_KERNEL:-${KERNELS[0]}}"
if [ ! -f "$ISO_TREE/live/vmlinuz" ] || ! cmp -s "$SIGNED_KERNEL" "$ISO_TREE/live/vmlinuz"; then
    echo "Staging signed kernel as /live/vmlinuz..."
    cp -f "$SIGNED_KERNEL" "$ISO_TREE/live/vmlinuz"
    chmod 644 "$ISO_TREE/live/vmlinuz"
fi

echo "=== Step 3: Adding MokManager to the EFI boot image ==="
# shim only searches for MokManager on the filesystem it was loaded from, i.e.
# inside /boot/grub/efi.img, and that FAT image is sized with no room left over.
# live-build copies mmx64.efi there only when no signed GRUB is available, so
# the image has to be rebuilt here with MokManager added.
EFI_IMG_OLD="$WORK_DIR/efi-orig.img"
cp "$ISO_TREE/boot/grub/efi.img" "$EFI_IMG_OLD"

if ! mdir -i "$EFI_IMG_OLD" ::/EFI/boot >/dev/null 2>&1; then
    echo "ERROR: ${EFI_IMG_OLD} has no /EFI/boot directory (unexpected EFI boot image layout)."
    exit 1
fi

# Stage the current content of the boot image so the rebuild keeps shim, GRUB
# and the GRUB prefix config that live-build put there.
EFI_STAGE="$WORK_DIR/efi-tree"
mkdir -p "$EFI_STAGE"

# mtools is not consistent about whether a directory copy also creates the
# source directory itself, so normalise the result instead of relying on it:
# after this, <stage>/EFI/boot and <stage>/boot/grub always exist.
ensure_subdir() {
    local PARENT="$1"
    local REL="$2"
    local FOUND

    [ -d "$PARENT/$REL" ] && return 0
    FOUND="$(find "$PARENT" -maxdepth 3 -type d -path "*/$REL" 2>/dev/null | head -n 1 || true)"
    if [ -n "$FOUND" ]; then
        mkdir -p "$PARENT/$(dirname "$REL")"
        mv "$FOUND" "$PARENT/$REL"
        return 0
    fi
    return 1
}

mcopy -s -n -m -i "$EFI_IMG_OLD" ::/EFI "$EFI_STAGE"
ensure_subdir "$EFI_STAGE" EFI/boot \
    || { echo "ERROR: cannot stage /EFI/boot from the EFI boot image."; exit 1; }
if mdir -i "$EFI_IMG_OLD" ::/boot >/dev/null 2>&1; then
    mcopy -s -n -m -i "$EFI_IMG_OLD" ::/boot "$EFI_STAGE"
    ensure_subdir "$EFI_STAGE" boot/grub || true
fi

echo "Adding MokManager ($(basename "$MMX_SRC")) to the EFI boot image..."
cp "$MMX_SRC" "$EFI_STAGE/EFI/boot/mmx64.efi"

# Size the new FAT image as live-build does: content bytes plus 4 KiB per
# directory, rounded up in 32-block steps with 55 blocks of headroom.
EFI_BYTES=$(find "$EFI_STAGE" -type f -exec stat -c %s {} + | awk '{total += $1} END {print total + 0}')
EFI_DIRS=$(find "$EFI_STAGE" -type d | wc -l)
EFI_BLOCKS=$(( ( (EFI_BYTES + 4096 * (EFI_DIRS + 1)) / 1024 + 55) / 32 * 32 ))

EFI_IMG_NEW="$WORK_DIR/efi.img"
rm -f "$EFI_IMG_NEW"
mkfs.msdos -C "$EFI_IMG_NEW" "$EFI_BLOCKS" >/dev/null
mmd -i "$EFI_IMG_NEW" ::EFI ::EFI/boot
mcopy -m -i "$EFI_IMG_NEW" "$EFI_STAGE"/EFI/boot/* "::EFI/boot"
if [ -d "$EFI_STAGE/boot/grub" ]; then
    mmd -i "$EFI_IMG_NEW" ::boot ::boot/grub
    mcopy -m -i "$EFI_IMG_NEW" "$EFI_STAGE"/boot/grub/* "::boot/grub"
fi

EFI_IMAGE_CONTENT="$(mdir -i "$EFI_IMG_NEW" ::/EFI/boot 2>/dev/null || true)"
for REQUIRED in BOOTX64 GRUBX64 MMX64; do
    if ! printf '%s\n' "$EFI_IMAGE_CONTENT" | grep -qi "$REQUIRED"; then
        echo "ERROR: ${REQUIRED}.EFI missing from the rebuilt EFI boot image."
        exit 1
    fi
done
cp -f "$EFI_IMG_NEW" "$ISO_TREE/boot/grub/efi.img"

echo "=== Step 4: Injecting MOK material and the EFI boot set ==="
install -m 0644 "$MOK_CRT" "$ISO_TREE/MOK.crt"
install -m 0644 "$MOK_DER" "$ISO_TREE/MOK.der"
install -m 0644 "$MOK_CER" "$ISO_TREE/MOK.cer"
install -m 0644 "$MOK_DER" "$ISO_TREE/live/MOK.der"

# Reuse the names already present in the tree instead of adding a second file
# that only differs in case, and mirror the whole set so a firmware
# "boot from file" menu can start shim and find its second stage next to it.
efi_tree_name() {
    local BASE="$1"
    local MATCH

    MATCH="$(find "$ISO_TREE/EFI/boot" -maxdepth 1 -type f -iname "$BASE" -printf '%f\n' 2>/dev/null \
        | head -n 1 || true)"
    printf '%s\n' "${MATCH:-$BASE}"
}

mkdir -p "$ISO_TREE/EFI/boot"

# Use the staging tree as the source: FAT names come back in upper case, so
# look them up case-insensitively and install them under the canonical name
# (or the one the tree already uses).
stage_file() {
    find "$EFI_STAGE" -type f -iname "$1" 2>/dev/null | sort | head -n 1
}

GRUB_CFG_STAGE="$(find "$EFI_STAGE" -type f -path '*/boot/grub/grub.cfg' 2>/dev/null | head -n 1 || true)"
if [ -z "$GRUB_CFG_STAGE" ]; then
    GRUB_CFG_STAGE="$(stage_file grub.cfg)"
fi

EFI_SRC=(
    "$(stage_file bootx64.efi)"
    "$(stage_file grubx64.efi)"
    "$(stage_file mmx64.efi)"
    "$GRUB_CFG_STAGE"
)
EFI_CANONICAL=(bootx64.efi grubx64.efi mmx64.efi grub.cfg)
PROBLEMS=0
for INDEX in 0 1 2 3; do
    if [ -z "${EFI_SRC[$INDEX]:-}" ] || [ ! -f "${EFI_SRC[$INDEX]}" ]; then
        echo "ERROR: ${EFI_CANONICAL[$INDEX]} not found in the rebuilt EFI boot image."
        PROBLEMS=1
    fi
done
if [ "$PROBLEMS" -ne 0 ]; then
    echo "Content of the rebuilt EFI boot image:"
    find "$EFI_STAGE" -type f 2>/dev/null | sort
    exit 1
fi

EFI_TREE_NAMES=()
for INDEX in 0 1 2 3; do
    EFI_DEST="$(efi_tree_name "${EFI_CANONICAL[$INDEX]}")"
    EFI_TREE_NAMES+=("$EFI_DEST")
    install -m 0644 "${EFI_SRC[$INDEX]}" "$ISO_TREE/EFI/boot/$EFI_DEST"
done

echo "=== Step 5: Building the final hybrid UEFI ISO ==="
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

# Same options live-build passes in binary_iso (xorriso -as mkisofs ...):
# -R -r -J -joliet-long -l -iso-level 3, the EFI El Torito entry and the
# hybrid MBR/GPT + APM layout that makes the image bootable from a USB stick.
MKISOFS_ARGS=(
    -as mkisofs
    -R -r -J -joliet-long -l -iso-level 3
    -e boot/grub/efi.img -no-emul-boot
    -isohybrid-gpt-basdat -isohybrid-apm-hfsplus
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
echo "Executing xorriso -as mkisofs to generate the final signed hybrid ISO..."
xorriso "${MKISOFS_ARGS[@]}" -o "$FINAL_ISO" "$ISO_TREE"

echo "=== Step 6: Verification of Final ISO ==="
if [ ! -f "$FINAL_ISO" ]; then
    echo "ERROR: Failed to create $FINAL_ISO"
    exit 1
fi

# The El Torito UEFI entry is what the firmware actually boots. A previous
# approach updated the tree with -indev/-outdev and lost this entry silently,
# so check the boot record of the finished image explicitly.
TORITO_REPORT="$(xorriso -indev "$FINAL_ISO" -report_el_torito plain 2>/dev/null || true)"
printf '%s\n' "$TORITO_REPORT" | grep -q 'UEFI' \
    || { echo "ERROR: no UEFI El Torito boot entry in the final ISO."; exit 1; }
printf '%s\n' "$TORITO_REPORT" | grep -q '/boot/grub/efi.img' \
    || { echo "ERROR: the UEFI El Torito entry does not use /boot/grub/efi.img."; exit 1; }

# The hybrid system area must still carry a GPT, otherwise the image only boots
# as a CD and not from a USB stick.
GPT_SIG="$( { dd if="$FINAL_ISO" bs=512 skip=1 count=1 status=none 2>/dev/null | head -c 8; } || true)"
if [ "$GPT_SIG" != "EFI PART" ]; then
    echo "ERROR: no GPT partition table in the final ISO system area."
    xorriso -indev "$FINAL_ISO" -report_system_area plain 2>/dev/null || true
    exit 1
fi
echo "OK: El Torito UEFI entry and hybrid GPT are present."

# The firmware boots the EFI image, not the ISO9660 copy, so check inside it.
EFI_IMG_FINAL="$WORK_DIR/efi-final.img"
if ! xorriso -osirrox on -indev "$FINAL_ISO" -extract /boot/grub/efi.img "$EFI_IMG_FINAL" >/dev/null 2>&1; then
    echo "ERROR: /boot/grub/efi.img missing from the final ISO."
    exit 1
fi

EFI_IMAGE_CONTENT="$(mdir -i "$EFI_IMG_FINAL" ::/EFI/boot 2>/dev/null || true)"
for REQUIRED in BOOTX64 GRUBX64 MMX64; do
    if ! printf '%s\n' "$EFI_IMAGE_CONTENT" | grep -qi "$REQUIRED"; then
        echo "ERROR: ${REQUIRED}.EFI missing from the EFI boot image (/boot/grub/efi.img)."
        echo "Content of /EFI/boot inside the EFI boot image:"
        printf '%s\n' "$EFI_IMAGE_CONTENT"
        exit 1
    fi
done

# Extract the mirrored files back out of the ISO and compare them byte for byte.
INDEX=0
for EFI_SOURCE in "${EFI_SRC[@]}"; do
    EFI_DEST="${EFI_TREE_NAMES[$INDEX]}"
    INDEX=$((INDEX + 1))
    CHECK_FILE="$WORK_DIR/check-${EFI_DEST}"
    if ! xorriso -osirrox on -indev "$FINAL_ISO" \
        -extract "/EFI/boot/${EFI_DEST}" "$CHECK_FILE" >/dev/null 2>&1; then
        echo "ERROR: /EFI/boot/${EFI_DEST} missing from the final ISO (firmware boot-from-file would fail)."
        exit 1
    fi
    if ! cmp -s "$EFI_SOURCE" "$CHECK_FILE"; then
        echo "ERROR: /EFI/boot/${EFI_DEST} on the final ISO differs from the EFI boot image copy."
        exit 1
    fi
done
echo "Secure Boot chain present: shim + GRUB + MokManager inside efi.img and /EFI/boot."

echo "Final ISO size: $(du -h "$FINAL_ISO" | cut -f1)"
echo "Generating SHA256 checksum..."
sha256sum "$FINAL_ISO" > "${FINAL_ISO}.sha256"
cat "${FINAL_ISO}.sha256"

echo "=== Secure Boot Signing and Repacking Complete! ==="
