#!/usr/bin/env bash
# modules/gpu.sh — GPU driver detection and installation

install_gpu_driver() {
  log_section "GPU Driver Setup"

  local driver="$GPU_DRIVER"

  # Auto-detect if set to auto
  if [[ "$driver" == "auto" ]]; then
    if lspci | grep -qi 'nvidia'; then
      driver="nvidia"
    elif lspci | grep -qi 'amd\|radeon'; then
      driver="amd"
    elif lspci | grep -qi 'intel'; then
      driver="intel"
    else
      driver="none"
    fi
    log_info "Auto-detected GPU: $driver"
  fi

  case "$driver" in
    nvidia)
      log_info "Installing NVIDIA drivers (DKMS for dual-kernel support)..."
      pacman -S --noconfirm --needed \
        nvidia-dkms \
        nvidia-utils \
        nvidia-settings \
        lib32-nvidia-utils \
        libva-nvidia-driver \
        egl-wayland
      # nvidia-dkms builds modules for both linux and linux-lts via headers

      # Add nvidia kernel modules to initramfs for early KMS
      log_info "Configuring NVIDIA early KMS..."
      sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
      run_logged "Rebuilding initramfs with NVIDIA modules" mkinitcpio -P

      # Enable DRM modeset for Wayland support
      mkdir -p /etc/modprobe.d
      echo 'options nvidia_drm modeset=1 fbdev=1' > /etc/modprobe.d/nvidia.conf

      log_info "NVIDIA drivers installed with Wayland/DRM support."
      ;;
    amd)
      log_info "Installing AMD drivers..."
      pacman -S --noconfirm --needed \
        mesa \
        lib32-mesa \
        vulkan-radeon \
        lib32-vulkan-radeon \
        libva-mesa-driver \
        lib32-libva-mesa-driver \
        mesa-vdpau \
        lib32-mesa-vdpau
      # AMD uses open-source drivers in the kernel — no DKMS needed

      log_info "AMD drivers installed (mesa + Vulkan + VA-API)."
      ;;
    intel)
      log_info "Installing Intel drivers..."
      pacman -S --noconfirm --needed \
        mesa \
        lib32-mesa \
        vulkan-intel \
        lib32-vulkan-intel \
        intel-media-driver
      # Intel uses open-source i915 kernel module — no DKMS needed

      log_info "Intel drivers installed (mesa + Vulkan + VA-API)."
      ;;
    none)
      log_info "Skipping GPU driver installation."
      ;;
    *)
      log_warn "Unknown GPU driver: $driver — skipping."
      ;;
  esac
}

install_gpu_driver
