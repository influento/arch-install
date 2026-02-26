#!/usr/bin/env bash
# iso/build.sh — Builds a custom Arch Linux ISO with the installer pre-loaded.
# Runs inside the Docker container. Do not run directly on the host.
set -euo pipefail

# --- Configuration ---

BUILD_DIR="/build"
PROFILE_SRC="/usr/share/archiso/configs/releng"
PROFILE_WORK="/tmp/profile"
WORK_DIR="/tmp/archiso-work"
OUTPUT_DIR="${BUILD_DIR}/iso/out"
OVERLAY_DIR="${BUILD_DIR}/iso/overlay"

ISO_NAME="archinstall-custom"
ISO_PUBLISHER="arch-install <https://github.com/user/arch-install>"

# --- Logging ---

log_info() {
  printf '\033[1;32m==> \033[0m%s\n' "$1"
}

log_detail() {
  printf '    \033[0;37m%s\033[0m\n' "$1"
}

log_error() {
  printf '\033[1;31m==> ERROR: \033[0m%s\n' "$1" >&2
}

# --- Preflight checks ---

if [[ ! -d "$PROFILE_SRC" ]]; then
  log_error "archiso releng profile not found at $PROFILE_SRC"
  exit 1
fi

if [[ ! -f "${BUILD_DIR}/install.sh" ]]; then
  log_error "Installer repo not found at $BUILD_DIR. Mount the repo root to /build."
  exit 1
fi

# --- Start build ---

log_info "Building custom Arch Linux ISO"

# Clean previous build artifacts
rm -rf "$PROFILE_WORK" "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"

# --- Step 1: Copy stock releng profile ---

log_info "Copying stock releng profile..."
cp -r "$PROFILE_SRC" "$PROFILE_WORK"

# --- Step 2: Append extra packages ---

if [[ -f "${OVERLAY_DIR}/packages-extra.txt" ]]; then
  log_info "Adding extra packages..."
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line// /}"
    [[ -z "$line" ]] && continue
    log_detail "$line"
    echo "$line" >> "${PROFILE_WORK}/packages.x86_64"
  done < "${OVERLAY_DIR}/packages-extra.txt"
fi

# --- Step 3: Copy airootfs overlays ---

if [[ -d "${OVERLAY_DIR}/airootfs" ]]; then
  log_info "Applying airootfs overlay..."
  cp -r "${OVERLAY_DIR}/airootfs/"* "${PROFILE_WORK}/airootfs/"
fi

# --- Step 4: Inject installer scripts ---

log_info "Injecting installer scripts into ISO..."
local_dest="${PROFILE_WORK}/airootfs/root/arch-install"
mkdir -p "$local_dest"

# Use tar to copy with exclusions (avoids rsync dependency)
tar -C "$BUILD_DIR" \
  --exclude='.git' \
  --exclude='iso/out' \
  --exclude='iso/work' \
  --exclude='tests/iso' \
  --exclude='old_notes' \
  --exclude='.claude' \
  -cf - . | tar -C "$local_dest" -xf -

log_detail "Scripts injected to /root/arch-install/"

# --- Step 4.5: Pre-clone dotfiles repo ---

# Source config to get DOTFILES_REPO URL
# shellcheck source=/dev/null
source "${BUILD_DIR}/config.sh"

if [[ -n "${DOTFILES_REPO:-}" ]]; then
  log_info "Pre-cloning dotfiles repo into ISO..."
  log_detail "$DOTFILES_REPO"
  git clone "$DOTFILES_REPO" "${local_dest}/.dotfiles-cache"
  # Remove .git/config credentials if any, keep repo functional
  log_detail "Dotfiles cached at /root/arch-install/.dotfiles-cache/"
else
  log_info "DOTFILES_REPO not set — skipping dotfiles pre-clone."
fi

# --- Step 5: Patch profiledef.sh ---

log_info "Patching profile configuration..."

# Set custom ISO name
sed -i "s|^iso_name=.*|iso_name=\"${ISO_NAME}\"|" "${PROFILE_WORK}/profiledef.sh"
sed -i "s|^iso_publisher=.*|iso_publisher=\"${ISO_PUBLISHER}\"|" "${PROFILE_WORK}/profiledef.sh"

# Add file permissions for our installer scripts
# Insert before the closing ) of the file_permissions array
sed -i '/^file_permissions=(/,/)/ {
  /)/i\  ["/root/arch-install/install.sh"]="0:0:755"
}' "${PROFILE_WORK}/profiledef.sh"

# --- Step 6: Build the ISO ---

log_info "Running mkarchiso (this will take several minutes)..."
log_detail "Working directory: $WORK_DIR"
log_detail "Output directory: $OUTPUT_DIR"

mkarchiso -v -w "$WORK_DIR" -o "$OUTPUT_DIR" "$PROFILE_WORK"

# --- Step 7: Generate checksum ---

log_info "Generating checksums..."
cd "$OUTPUT_DIR"
iso_file=$(ls -1 "${ISO_NAME}"-*.iso 2>/dev/null | head -1)

if [[ -z "$iso_file" ]]; then
  log_error "No ISO file found in output directory!"
  exit 1
fi

sha256sum "$iso_file" > sha256sums.txt
iso_size=$(du -h "$iso_file" | cut -f1)

log_info "Build complete!"
log_detail "ISO: ${OUTPUT_DIR}/${iso_file}"
log_detail "Size: ${iso_size}"
log_detail "SHA256: $(cut -d' ' -f1 sha256sums.txt)"

# --- Cleanup ---

rm -rf "$WORK_DIR" "$PROFILE_WORK"
log_info "Done."
