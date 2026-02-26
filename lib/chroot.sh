#!/usr/bin/env bash
# lib/chroot.sh — Chroot wrapper for running scripts inside the new system

# Copy the installer into the chroot and run a script there.
# Usage: run_in_chroot <script> [commands...]
# Example: run_in_chroot lib/configure.sh configure_system
# Example: run_in_chroot profiles/workstation.sh   (self-executing scripts)
run_in_chroot() {
  local script="$1"
  shift
  local extra_cmds=("$@")
  # NOTE: Do NOT use /tmp — arch-chroot mounts a fresh tmpfs over /tmp,
  # which would hide any files we copy there.
  local chroot_installer="/root/arch-install"

  # Copy installer tree into chroot
  if [[ ! -d "${MOUNT_POINT}${chroot_installer}" ]]; then
    log_debug "Copying installer to ${MOUNT_POINT}${chroot_installer}"
    cp -a "$INSTALLER_DIR" "${MOUNT_POINT}${chroot_installer}"
  fi

  # Build optional extra command lines
  local extra=""
  if [[ ${#extra_cmds[@]} -gt 0 ]]; then
    local cmd
    for cmd in "${extra_cmds[@]}"; do
      extra="${extra}${cmd}"$'\n'
    done
  fi

  # Build the wrapper that sources everything and runs the target script
  local wrapper
  wrapper=$(cat <<CHROOT_EOF
#!/usr/bin/env bash
set -euo pipefail

export INSTALLER_DIR="${chroot_installer}"
export LOG_FILE="${LOG_FILE}"
export PROFILE="workstation"
export HOSTNAME="${HOSTNAME}"
export USERNAME="${USERNAME}"
export TIMEZONE="${TIMEZONE}"
export LOCALE="${LOCALE}"
export KEYMAP="${KEYMAP}"
export BOOTLOADER="${BOOTLOADER}"
export FS_TYPE="${FS_TYPE}"
export SWAP_SIZE="${SWAP_SIZE}"
export GPU_DRIVER="${GPU_DRIVER}"
export EDITOR="${EDITOR}"
export AUR_HELPER="${AUR_HELPER}"
export DOTFILES_REPO="${DOTFILES_REPO:-}"
export DOTFILES_DEST="${DOTFILES_DEST:-}"
export MOUNT_POINT=""
export PART_EFI="${PART_EFI:-}"
export PART_SWAP="${PART_SWAP:-}"
export PART_ROOT="${PART_ROOT:-}"
export PART_HOME="${PART_HOME:-}"
export WIPE_HOME="${WIPE_HOME:-}"
export ROOT_SIZE="${ROOT_SIZE:-}"
export SWAP_UUID="${SWAP_UUID:-}"
export DEBUG="${DEBUG:-0}"
export AUTO_MODE="${AUTO_MODE:-0}"
export ROOT_PASSWORD="${ROOT_PASSWORD:-}"
export USER_PASSWORD="${USER_PASSWORD:-}"

# Source libraries
source "\${INSTALLER_DIR}/lib/log.sh"
source "\${INSTALLER_DIR}/lib/ui.sh"
source "\${INSTALLER_DIR}/lib/packages.sh"
source "\${INSTALLER_DIR}/lib/services.sh"

# Source the target script (loads functions or executes top-level code)
source "\${INSTALLER_DIR}/${script}"

# Run any extra commands passed as arguments
${extra}
CHROOT_EOF
  )

  # Write wrapper to a file and execute it (instead of piping to bash).
  # Piping consumes stdin, which breaks interactive prompts (passwords, etc.).
  local wrapper_file="${MOUNT_POINT}${chroot_installer}/.chroot-wrapper.sh"
  printf '%s' "$wrapper" > "$wrapper_file"
  chmod +x "$wrapper_file"

  log_debug "Entering chroot to run: $script $extra"
  arch-chroot "$MOUNT_POINT" /usr/bin/bash "${chroot_installer}/.chroot-wrapper.sh"
}

# Cleanup the installer copy from the chroot
cleanup_chroot() {
  local chroot_installer="${MOUNT_POINT}/root/arch-install"
  if [[ -d "$chroot_installer" ]]; then
    log_debug "Cleaning up installer copy from chroot"
    rm -rf "$chroot_installer"
  fi
}
