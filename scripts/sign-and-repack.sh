#!/bin/bash
# scripts/sign-and-repack.sh
# Extracts vmlinuz from Debian live ISO, signs it with MOK key using sbsign,
# adds MokManager to the EFI boot image and repacks the hybrid UEFI ISO.

set -euo pipefail

ORIG_ISO="${1:-}"
FINAL_ISO="${2:-}"
MOK_KEY="${3:-mok/mok.key}"
MOK_CRT="${4:-mok/mok.crt}"
MOK_DER="${5:-mok/mok.der}"

if [ -z "$ORIG_ISO" ] || [ -z "$FINAL_ISO" ]; then
    echo "Usage: $0 <input_original.iso> <output_final.iso> [mok.key] [mok.crt] [mok.der]"
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

echo "=== Step 1: Extracting /live directory from ${ORIG_ISO} ==="
mkdir -p "$WORK_DIR/extracted"
xorriso -osirrox on -indev "$ORIG_ISO" -extract /live "$WORK_DIR/extracted"

# Find actual kernel regular files (excluding symlinks)
KERNELS=$(find "$WORK_DIR/extracted" -type f -name "vmlinuz*" | sort)

if [ -z "$KERNELS" ]; then
    echo "ERROR: No vmlinuz executable found in extracted ISO files!"
    exit 1
fi

echo "=== Step 2: Signing kernel executables with sbsign ==="
for KERNEL in $KERNELS; do
    KNAME=$(basename "$KERNEL")
    echo "Signing kernel binary: ${KNAME}..."
    sbsign --key "$MOK_KEY" --cert "$MOK_CRT" --output "${KERNEL}.signed" "$KERNEL"
    
    echo "Verifying signature on ${KNAME}.signed..."
    sbverify --cert "$MOK_CRT" "${KERNEL}.signed"
    
    # Overwrite extracted kernel with signed version
    mv "${KERNEL}.signed" "$KERNEL"
    chmod 644 "$KERNEL"
done

echo "=== Step 3: Adding MokManager to the EFI boot image ==="
# shim only searches for MokManager on the filesystem it was loaded from, i.e.
# inside /boot/grub/efi.img, and that FAT image is sized with no room left over.
# live-build copies mmx64.efi there only when no signed GRUB is available, so
# the image has to be rebuilt here with MokManager added.
EFI_IMG_OLD="$WORK_DIR/efi-orig.img"
xorriso -osirrox on -indev "$ORIG_ISO" -extract /boot/grub/efi.img "$EFI_IMG_OLD"

if ! mdir -i "$EFI_IMG_OLD" ::/EFI/boot >/dev/null 2>&1; then
    echo "ERROR: ${EFI_IMG_OLD} has no /EFI/boot directory (unexpected EFI boot image layout)."
    exit 1
fi

# Stage the current content of the boot image so the rebuild keeps shim, GRUB
# and the GRUB prefix config that live-build put there.
EFI_STAGE="$WORK_DIR/efi-tree"
mkdir -p "$EFI_STAGE"
mcopy -s -n -m -i "$EFI_IMG_OLD" ::/EFI "$EFI_STAGE"
if mdir -i "$EFI_IMG_OLD" ::/boot >/dev/null 2>&1; then
    mcopy -s -n -m -i "$EFI_IMG_OLD" ::/boot "$EFI_STAGE"
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

echo "=== Step 4: Repacking bootable hybrid ISO with xorriso ==="
# Remove target file if it already exists
rm -f "$FINAL_ISO"

# Build xorriso arguments to update signed kernels and inject MOK certificates
XORRISO_ARGS=(
    "-indev" "$ORIG_ISO"
    "-outdev" "$FINAL_ISO"
    "-boot_image" "any" "keep"
)

# Update each versioned kernel and ensure /live/vmlinuz is updated
FIRST_KERNEL=""
for KERNEL in $KERNELS; do
    KNAME=$(basename "$KERNEL")
    echo "Staging signed kernel for ISO injection: /live/${KNAME}"
    XORRISO_ARGS+=("-update" "$KERNEL" "/live/${KNAME}")
    if [ -z "$FIRST_KERNEL" ]; then
        FIRST_KERNEL="$KERNEL"
    fi
done

# Ensure standard unversioned /live/vmlinuz points to signed kernel
if [ -n "$FIRST_KERNEL" ]; then
    XORRISO_ARGS+=("-update" "$FIRST_KERNEL" "/live/vmlinuz")
fi

# Inject MOK certificates to ISO root and /live so user can enroll them from UEFI MokManager
XORRISO_ARGS+=("-update" "$MOK_CRT" "/MOK.crt")
XORRISO_ARGS+=("-update" "$MOK_DER" "/MOK.der")
XORRISO_ARGS+=("-update" "$MOK_DER" "/live/MOK.der")

# Keep a copy of MokManager on the ISO9660 tree as well: some firmwares can only
# launch it there via their "boot from file" option.
echo "Injecting MokManager (${MMX_SRC}) as /EFI/boot/mmx64.efi..."
XORRISO_ARGS+=("-update" "$MMX_SRC" "/EFI/boot/mmx64.efi")

echo "Staging rebuilt EFI boot image (with MokManager) as /boot/grub/efi.img..."
XORRISO_ARGS+=("-update" "$EFI_IMG_NEW" "/boot/grub/efi.img")

# "* keep" copies the loaded El Torito image bytes, so the rebuilt efi.img would
# never reach the boot entry. "replay", applied after all file changes, drops
# the loaded boot equipment and re-creates it from the tree: the new efi.img
# becomes the EFI boot image and the hybrid MBR/GPT system area is regenerated.
XORRISO_ARGS+=("-boot_image" "any" "replay")

echo "Executing xorriso to generate final signed hybrid ISO..."
xorriso "${XORRISO_ARGS[@]}"

echo "=== Step 5: Verification of Final ISO ==="
if [ ! -f "$FINAL_ISO" ]; then
    echo "ERROR: Failed to create $FINAL_ISO"
    exit 1
fi

# xorriso prints each matched path enclosed in hard single quotes
# ("'/EFI/boot/bootx64.efi'"), so strip them before comparing exact paths.
ISO_FILES="$(xorriso -indev "$FINAL_ISO" -find /EFI/boot -type f 2>/dev/null \
    | sed "s/^'//; s/'$//" || true)"
for REQUIRED in /EFI/boot/bootx64.efi /EFI/boot/mmx64.efi; do
    if ! printf '%s\n' "$ISO_FILES" | grep -qixF "$REQUIRED"; then
        echo "ERROR: ${REQUIRED} missing from the final ISO (Secure Boot chain incomplete)."
        echo "Files present in /EFI/boot on the ISO:"
        printf '%s\n' "$ISO_FILES"
        exit 1
    fi
done

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
echo "Secure Boot chain present: shim (bootx64.efi) + GRUB (grubx64.efi) + MokManager (mmx64.efi)."

echo "Final repacked ISO size: $(du -h "$FINAL_ISO" | cut -f1)"
echo "Generating SHA256 checksum..."
sha256sum "$FINAL_ISO" > "${FINAL_ISO}.sha256"
cat "${FINAL_ISO}.sha256"

echo "=== Secure Boot Signing and Repacking Complete! ==="
