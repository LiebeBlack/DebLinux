#!/bin/bash
# scripts/sign-and-repack.sh
# Extracts vmlinuz from Debian live ISO, signs it with MOK key using sbsign,
# and repacks the hybrid UEFI bootable ISO using xorriso.

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

WORK_DIR="$(mktemp -d /tmp/iso-sign-XXXXXX)"
cleanup() {
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

echo "=== Step 3: Repacking bootable hybrid ISO with xorriso ==="
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
XORRISO_ARGS+=("-add" "$MOK_CRT" "/MOK.crt")
XORRISO_ARGS+=("-add" "$MOK_DER" "/MOK.der")
XORRISO_ARGS+=("-add" "$MOK_DER" "/live/MOK.der")

# Inject MokManager (mmx64.efi) into EFI boot directory if available on host
if [ -f /usr/lib/shim/mmx64.efi.signed ]; then
    echo "Injecting signed MokManager (mmx64.efi) into EFI boot partition..."
    XORRISO_ARGS+=("-add" "/usr/lib/shim/mmx64.efi.signed" "/EFI/BOOT/mmx64.efi")
fi

echo "Executing xorriso to generate final signed hybrid ISO..."
xorriso "${XORRISO_ARGS[@]}"

echo "=== Step 4: Verification of Final ISO ==="
if [ ! -f "$FINAL_ISO" ]; then
    echo "ERROR: Failed to create $FINAL_ISO"
    exit 1
fi

echo "Final repacked ISO size: $(du -h "$FINAL_ISO" | cut -f1)"
echo "Generating SHA256 checksum..."
sha256sum "$FINAL_ISO" > "${FINAL_ISO}.sha256"
cat "${FINAL_ISO}.sha256"

echo "=== Secure Boot Signing and Repacking Complete! ==="
