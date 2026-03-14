#!/usr/bin/env bash
# Creates a QEMU/KVM VM for testing the Arch Linux installer.
#
# Creates a UEFI VM with:
# - OVMF firmware (UEFI, no Secure Boot)
# - Configurable RAM, CPUs, and disk size
# - Arch ISO attached as CD-ROM
# - User-mode networking (internet access, no root required)
# - VirtIO disk and network for performance
# - SPICE display with clipboard sharing
#
# Usage: ./tests/linux/create-vm.sh [options]
#
# Options:
#   --name NAME         VM name (default: archtest)
#   --memory MB         RAM in MB (default: 8192)
#   --cpus N            Number of CPUs (default: 2)
#   --disk-size GB      Disk size in GB (default: 60)
#   --iso PATH          Path to Arch ISO (default: auto-detect)
#   --no-launch         Create the VM disk and print the command, don't launch
#   --help              Show this help

set -euo pipefail

# --- Defaults ---

VM_NAME="archtest"
MEMORY_MB=8192
CPUS=2
DISK_SIZE_GB=60
ISO_PATH=""
LAUNCH=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$TESTS_DIR")"
VM_DIR="${TESTS_DIR}/vm"

OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       VM_NAME="$2"; shift 2 ;;
    --memory)     MEMORY_MB="$2"; shift 2 ;;
    --cpus)       CPUS="$2"; shift 2 ;;
    --disk-size)  DISK_SIZE_GB="$2"; shift 2 ;;
    --iso)        ISO_PATH="$2"; shift 2 ;;
    --no-launch)  LAUNCH=false; shift ;;
    --help)
      sed -n '2,/^$/s/^# \?//p' "$0"
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# --- Output helpers ---

print_step() {
  printf '\n\033[36m==>\033[0m %s\n' "$1"
}

print_ok() {
  printf '    \033[32m[OK]\033[0m %s\n' "$1"
}

print_fail() {
  printf '    \033[31m[FAIL]\033[0m %s\n' "$1"
}

print_detail() {
  printf '    \033[90m%s\033[0m\n' "$1"
}

# --- Check dependencies ---

print_step "Checking dependencies..."

for cmd in qemu-system-x86_64 qemu-img; do
  if command -v "$cmd" &>/dev/null; then
    print_ok "$cmd found"
  else
    print_fail "$cmd not found. Install qemu-full."
    exit 1
  fi
done

if [[ ! -f "$OVMF_CODE" ]]; then
  print_fail "OVMF firmware not found: $OVMF_CODE"
  print_detail "Install edk2-ovmf package."
  exit 1
fi
print_ok "OVMF firmware found"

if lsmod | grep -q kvm; then
  print_ok "KVM module loaded"
else
  print_fail "KVM module not loaded. Check your BIOS virtualization settings."
  exit 1
fi

# --- Auto-detect ISO ---

if [[ -z "$ISO_PATH" ]]; then
  # Prefer custom ISO from iso/out/, fall back to tests/iso/
  custom_iso_dir="${REPO_DIR}/iso/out"
  stock_iso_dir="${TESTS_DIR}/iso"

  iso_found=""

  # Check custom ISOs first
  if [[ -d "$custom_iso_dir" ]]; then
    iso_found=$(find "$custom_iso_dir" -name "archinstall-custom-*.iso" -type f 2>/dev/null | sort -r | head -1)
    if [[ -n "$iso_found" ]]; then
      print_detail "Found custom ISO in iso/out/"
    fi
  fi

  # Fall back to stock ISOs
  if [[ -z "$iso_found" && -d "$stock_iso_dir" ]]; then
    iso_found=$(find "$stock_iso_dir" -name "archlinux-*.iso" -type f 2>/dev/null | sort -r | head -1)
  fi

  if [[ -z "$iso_found" ]]; then
    print_fail "No Arch ISO found."
    print_detail "Build a custom ISO:      docker build -t archiso-builder iso/ && docker run --rm --privileged -v \"\$(pwd)\":/build archiso-builder"
    print_detail "Or download a stock ISO:  ./tests/linux/download-iso.sh"
    exit 1
  fi

  ISO_PATH="$iso_found"
fi

if [[ ! -f "$ISO_PATH" ]]; then
  print_fail "ISO not found: $ISO_PATH"
  exit 1
fi

# --- Create VM directory and disk ---

mkdir -p "$VM_DIR"

disk_path="${VM_DIR}/${VM_NAME}.qcow2"
vars_path="${VM_DIR}/${VM_NAME}_VARS.fd"

printf '\n'
printf '\033[36mQEMU/KVM VM Creator - Arch Linux Installer Testing\033[0m\n'
printf '\033[90m==================================================\033[0m\n'

print_step "Configuration"
print_detail "VM Name:     $VM_NAME"
print_detail "Memory:      $MEMORY_MB MB"
print_detail "CPUs:        $CPUS"
print_detail "Disk:        $DISK_SIZE_GB GB (qcow2) -> $disk_path"
print_detail "ISO:         $ISO_PATH"
print_detail "OVMF:        $OVMF_CODE"

# Create disk image
if [[ -f "$disk_path" ]]; then
  print_fail "Disk already exists: $disk_path"
  print_detail "To recreate: rm $disk_path $vars_path; then re-run this script."
  exit 1
fi

print_step "Creating VM disk..."
qemu-img create -f qcow2 "$disk_path" "${DISK_SIZE_GB}G"
print_ok "Disk created: $disk_path"

# Copy OVMF vars (writable copy for this VM's UEFI settings)
cp "$OVMF_VARS" "$vars_path"
print_ok "UEFI vars: $vars_path"

# --- Build QEMU command ---

qemu_cmd=(
  qemu-system-x86_64
  -name "$VM_NAME"
  -machine "q35,accel=kvm"
  -cpu host
  -smp "$CPUS"
  -m "$MEMORY_MB"

  # UEFI firmware
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,file=$vars_path"

  # Virtual disk (VirtIO for performance)
  -drive "file=$disk_path,format=qcow2,if=virtio,cache=writeback"

  # CD-ROM with Arch ISO (boot from this first)
  -cdrom "$ISO_PATH"
  -boot d

  # Network (user-mode — internet access, no root required)
  -nic "user,model=virtio-net-pci"

  # Display
  -display gtk
  -vga virtio

  # USB tablet for better mouse integration
  -device usb-ehci
  -device usb-tablet

  # Monitor on stdio for QEMU commands (quit, snapshot, etc.)
  -monitor stdio
)

# --- Launch or print ---

printf '\n\033[90m==================================================\033[0m\n'
print_ok "VM '$VM_NAME' is ready."

if [[ "$LAUNCH" == "true" ]]; then
  print_step "Launching VM..."
  print_detail "QEMU monitor available on this terminal (type 'quit' to stop VM)"
  print_detail "After install, eject ISO: in the monitor type 'eject ide1-cd0'"
  printf '\n'
  exec "${qemu_cmd[@]}"
else
  print_step "Launch command (run this to start the VM):"
  printf '\n'
  printf '%s \\\n' "${qemu_cmd[0]}"
  for (( i=1; i<${#qemu_cmd[@]}; i++ )); do
    if [[ "${qemu_cmd[$i]}" == -* ]]; then
      printf '  %s' "${qemu_cmd[$i]}"
    else
      printf ' %s' "${qemu_cmd[$i]}"
    fi
    if (( i < ${#qemu_cmd[@]} - 1 )); then
      printf ' \\\n'
    fi
  done
  printf '\n\n'
  print_detail "After install completes, stop the VM and reboot from disk:"
  print_detail "  ${qemu_cmd[0]} ${qemu_cmd[*]:1}" | head -c 0  # suppress
  printf '    # Remove -cdrom and -boot d flags, or eject in the QEMU monitor\n'
  printf '\n'
fi
