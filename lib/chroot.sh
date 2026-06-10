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

  # Write ALL config + passwords to a separate file, printf %q-escaped, then
  # have the wrapper source it. Any value can contain shell metacharacters
  # ($, ", \, backticks, ;) that would otherwise break out of — or inject into —
  # the generated wrapper if interpolated directly. %q makes each value a single
  # safe shell token that round-trips back to the exact original on source.
  local env_file="${MOUNT_POINT}${chroot_installer}/.chroot-env"
  {
    printf 'export INSTALLER_DIR=%q\n'       "${chroot_installer}"
    printf 'export LOG_FILE=%q\n'            "${LOG_FILE}"
    printf 'export PROFILE=%q\n'             "workstation"
    printf 'export HOSTNAME=%q\n'            "${HOSTNAME}"
    printf 'export USERNAME=%q\n'            "${USERNAME}"
    printf 'export TIMEZONE=%q\n'            "${TIMEZONE}"
    printf 'export LOCALE=%q\n'              "${LOCALE}"
    printf 'export KEYMAP=%q\n'              "${KEYMAP}"
    printf 'export BOOTLOADER=%q\n'          "${BOOTLOADER}"
    printf 'export FS_TYPE=%q\n'             "${FS_TYPE}"
    printf 'export SWAP_SIZE=%q\n'           "${SWAP_SIZE}"
    printf 'export GPU_DRIVER=%q\n'          "${GPU_DRIVER}"
    printf 'export EDITOR=%q\n'              "${EDITOR}"
    printf 'export AUR_HELPER=%q\n'          "${AUR_HELPER}"
    printf 'export ENABLE_SSH=%q\n'          "${ENABLE_SSH:-no}"
    printf 'export DOTFILES_REPO=%q\n'       "${DOTFILES_REPO:-}"
    printf 'export DOTFILES_DEST=%q\n'       "${DOTFILES_DEST:-}"
    printf 'export ARCH_INSTALL_REPO=%q\n'   "${ARCH_INSTALL_REPO:-}"
    printf 'export SERVER_INSTALL_REPO=%q\n' "${SERVER_INSTALL_REPO:-}"
    printf 'export MOUNT_POINT=%q\n'         ""
    printf 'export PART_EFI=%q\n'            "${PART_EFI:-}"
    printf 'export PART_SWAP=%q\n'           "${PART_SWAP:-}"
    printf 'export PART_ROOT=%q\n'           "${PART_ROOT:-}"
    printf 'export PART_HOME=%q\n'           "${PART_HOME:-}"
    printf 'export WIPE_HOME=%q\n'           "${WIPE_HOME:-}"
    printf 'export ROOT_SIZE=%q\n'           "${ROOT_SIZE:-}"
    printf 'export SWAP_UUID=%q\n'           "${SWAP_UUID:-}"
    printf 'export DEBUG=%q\n'               "${DEBUG:-0}"
    printf 'export AUTO_MODE=%q\n'           "${AUTO_MODE:-0}"
    printf 'export ROOT_PASSWORD=%q\n'       "${ROOT_PASSWORD:-}"
    printf 'export USER_PASSWORD=%q\n'       "${USER_PASSWORD:-}"
  } > "$env_file"
  chmod 600 "$env_file"

  # Build the wrapper that sources everything and runs the target script
  local wrapper
  wrapper=$(cat <<CHROOT_EOF
#!/usr/bin/env bash
set -euo pipefail

# All config + passwords were written (printf %q-escaped) to .chroot-env;
# sourcing it defines every variable, including INSTALLER_DIR used just below.
source "${chroot_installer}/.chroot-env"

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
    # Ensure password file is removed (should already be gone with rm -rf,
    # but explicitly shred it first for defense in depth)
    local env_file="${chroot_installer}/.chroot-env"
    if [[ -f "$env_file" ]]; then
      shred -u "$env_file" 2>/dev/null || rm -f "$env_file"
    fi
    log_debug "Cleaning up installer copy from chroot"
    rm -rf "$chroot_installer"
  fi
}
