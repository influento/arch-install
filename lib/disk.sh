#!/usr/bin/env bash
# lib/disk.sh — Disk detection, partitioning, formatting, and mounting
# UEFI only. Layout: EFI(1G) + Swap(RAM size, min 8G) + Root(128G) + Home(rest)

# ---------- helpers ----------

# Get total RAM in GiB (rounded up, minimum 8).
detect_swap_size() {
  local ram_gib
  ram_gib=$(awk '/MemTotal/{v=int($2/1024/1024+0.5); print (v<8)?8:v}' /proc/meminfo)
  printf '%dG' "$ram_gib"
}

# Determine the partition device prefix (/dev/sda → /dev/sda, /dev/nvme0n1 → /dev/nvme0n1p).
part_prefix() {
  local disk="$1"
  if [[ "$disk" == *nvme* || "$disk" == *mmcblk* ]]; then
    printf '%sp' "$disk"
  else
    printf '%s' "$disk"
  fi
}

# ---------- main entry ----------

setup_disk() {
  log_section "Disk Setup"

  # Select disk if not set
  if [[ -z "$TARGET_DISK" ]]; then
    TARGET_DISK=$(select_disk)
  fi
  log_info "Target disk: $TARGET_DISK"

  # Compute swap size (RAM-based, min 8G)
  if [[ -z "$SWAP_SIZE" ]]; then
    SWAP_SIZE=$(detect_swap_size)
    log_info "Swap size (auto, RAM-based): $SWAP_SIZE"
  fi

  # Root size default: 128G
  if [[ -z "$ROOT_SIZE" ]]; then
    ROOT_SIZE="128G"
  fi

  # Check for existing /home and ask about wipe
  local prefix
  prefix=$(part_prefix "$TARGET_DISK")
  if [[ -b "${prefix}4" && -z "$WIPE_HOME" ]]; then
    log_warn "Existing partition detected at ${prefix}4 (possibly /home)."
    if confirm "Wipe /home partition? (No = keep existing data, reformat only EFI+swap+root)"; then
      WIPE_HOME="yes"
    else
      WIPE_HOME="no"
    fi
  else
    WIPE_HOME="${WIPE_HOME:-yes}"
  fi

  # Safety confirmation
  if [[ "$WIPE_HOME" == "no" ]]; then
    log_warn "Will WIPE EFI + swap + root on $TARGET_DISK but KEEP /home."
  else
    log_warn "ALL DATA ON $TARGET_DISK WILL BE DESTROYED."
  fi
  confirm "Proceed with partitioning $TARGET_DISK?" || die "Aborted by user."

  partition_workstation "$(part_prefix "$TARGET_DISK")"
  run_logged "Reloading partition table" partprobe "$TARGET_DISK"
  # Wait for kernel to finish creating device nodes (NVMe can be slow)
  run_logged "Waiting for device nodes" udevadm settle
  log_info "Partitions: EFI=$PART_EFI SWAP=$PART_SWAP ROOT=$PART_ROOT HOME=${PART_HOME:-n/a}"

  format_partitions
  mount_partitions
}

# ---------- partitioning ----------

# EFI(1) + Swap(2) + Root/128G(3) + Home/rest(4)
partition_workstation() {
  local prefix="$1"

  if [[ "$WIPE_HOME" == "no" ]]; then
    # Only wipe partitions 1-3, leave 4 (/home) intact
    log_info "Wiping partitions 1-3, preserving partition 4 (/home)..."
    sgdisk -d 1 -d 2 -d 3 "$TARGET_DISK" 2>/dev/null || true
  else
    log_info "Wiping entire partition table..."
    run_logged "Wiping partition table" sgdisk --zap-all "$TARGET_DISK"
  fi

  run_logged "Creating EFI partition (${EFI_SIZE})" \
    sgdisk -n 1:0:+"${EFI_SIZE}" -t 1:ef00 -c 1:"EFI" "$TARGET_DISK"

  run_logged "Creating swap partition (${SWAP_SIZE})" \
    sgdisk -n 2:0:+"${SWAP_SIZE}" -t 2:8200 -c 2:"Swap" "$TARGET_DISK"

  run_logged "Creating root partition (${ROOT_SIZE})" \
    sgdisk -n 3:0:+"${ROOT_SIZE}" -t 3:8300 -c 3:"Root" "$TARGET_DISK"

  if [[ "$WIPE_HOME" == "yes" ]]; then
    run_logged "Creating home partition (remaining space)" \
      sgdisk -n 4:0:0 -t 4:8300 -c 4:"Home" "$TARGET_DISK"
  fi

  PART_EFI="${prefix}1"
  PART_SWAP="${prefix}2"
  PART_ROOT="${prefix}3"
  PART_HOME="${prefix}4"
}

# ---------- formatting ----------

format_partitions() {
  log_info "Formatting partitions..."

  run_logged "Formatting EFI (FAT32)" mkfs.fat -F 32 "$PART_EFI"
  run_logged "Formatting swap" mkswap "$PART_SWAP"

  case "$FS_TYPE" in
    ext4)
      run_logged "Formatting root (ext4)" mkfs.ext4 -F "$PART_ROOT"
      ;;
    btrfs)
      run_logged "Formatting root (btrfs)" mkfs.btrfs -f "$PART_ROOT"
      ;;
    *)
      die "Unsupported filesystem: $FS_TYPE"
      ;;
  esac

  # Home partition (workstation only)
  if [[ -n "$PART_HOME" ]]; then
    if [[ "$WIPE_HOME" == "yes" ]]; then
      case "$FS_TYPE" in
        ext4)  run_logged "Formatting home (ext4)" mkfs.ext4 -F "$PART_HOME" ;;
        btrfs) run_logged "Formatting home (btrfs)" mkfs.btrfs -f "$PART_HOME" ;;
      esac
    else
      log_info "Keeping existing /home filesystem (not formatting)."
    fi
  fi
}

# ---------- mounting ----------

mount_partitions() {
  log_info "Mounting partitions..."

  run_logged "Mounting root" mount "$PART_ROOT" "$MOUNT_POINT"

  mkdir -p "${MOUNT_POINT}/boot"
  run_logged "Mounting EFI at /boot" mount "$PART_EFI" "${MOUNT_POINT}/boot"

  if [[ -n "$PART_HOME" ]]; then
    mkdir -p "${MOUNT_POINT}/home"
    run_logged "Mounting home at /home" mount "$PART_HOME" "${MOUNT_POINT}/home"
  fi

  run_logged "Activating swap" swapon "$PART_SWAP"

  log_info "All partitions mounted."
}
