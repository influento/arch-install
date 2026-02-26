# Architecture - Custom Arch Linux Installer

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Boot mode | **UEFI only** | All modern hardware; simplifies code (no GRUB/MBR path) |
| Bootloader | **systemd-boot** | Lightweight, native UEFI, no GRUB complexity |
| Default filesystem | **ext4** | Battle-tested; btrfs available as option |
| Kernel | **linux + linux-lts** | Both installed; LTS as fallback boot entry |
| Hibernation | **Enabled** | resume hook + swap UUID in boot params |
| Firewall | **nftables** | Kernel-native, modern replacement for iptables |
| DNS resolver | **systemd-resolved** | Modern, integrates with NetworkManager |
| Default editor | **neovim** | Used for visudo, git, etc. |
| Default shell | **zsh + oh-my-zsh** | Bash-compatible, plugin ecosystem, starship prompt |
| Default user | *(prompted)* | No default; user enters username at install time |
| Hostname | *(prompted)* | User types the full hostname directly |
| Timezone | **prompted** (default UTC) | User-facing workstation, prompt for real timezone |
| AUR helper | **yay** | Needed for Chrome, Dropbox, etc. |
| Browser | **Google Chrome** (AUR) | Installed via yay |
| Terminal | **Ghostty** | Single terminal, no fallback needed |
| File manager | **yazi** (TUI) | Lightweight, terminal-native |
| Virtualization | **QEMU/KVM** | Kernel-native hypervisor, virt-manager GUI |

---

## Execution Flow

```
install.sh
  │
  ├── Source lib/*.sh helpers
  ├── Parse CLI arguments (--config, --auto, --dry-run, etc.)
  ├── Load config.sh defaults, then override from CLI/config file
  │
  ├── Preflight checks (lib/checks.sh)
  │   ├── Running as root?
  │   ├── UEFI or BIOS?
  │   ├── Network connectivity?
  │   └── Disk available?
  │
  ├── Interactive prompts (all input collected up front)
  │   ├── Username, hostname, timezone
  │   ├── Root password + user password
  │   └── Disk selection (if multiple)
  │
  ├── Confirmation → everything after this is unattended
  │
  ├── Disk setup (lib/disk.sh)
  │   ├── Auto-detect swap size (RAM, min 8G)
  │   ├── Ask to wipe /home if existing partition found
  │   ├── EFI(1G) + Swap + Root(128G) + Home(rest)
  │   ├── Format filesystems
  │   └── Mount to /mnt (/boot, /home)
  │
  ├── Base install (lib/pacstrap.sh)
  │   ├── Configure mirrors (reflector)
  │   └── pacstrap /mnt <base packages>
  │
  ├── System configuration (lib/configure.sh via chroot)
  │   ├── Generate fstab
  │   ├── Pacman config (parallel downloads, color, multilib)
  │   ├── Timezone + locale
  │   ├── Hostname + /etc/hosts
  │   ├── DNS (systemd-resolved)
  │   ├── Initramfs (+ resume hook for hibernation)
  │   ├── Bootloader (systemd-boot: linux + linux-lts + fallbacks)
  │   ├── Set root + user passwords (collected up front)
  │   ├── Create user with sudo (zsh shell)
  │   └── Enable base services
  │
  ├── Workstation profile (profiles/workstation.sh via chroot)
  │   ├── Temp passwordless sudo for install
  │   ├── Base setup (AUR helper + dotfiles deployment)
  │   ├── Install workstation package lists
  │   ├── Run feature modules (GPU, SDDM, firewall, SSH, virtualization)
  │   ├── Inline setup (docker group, env vars, font cache)
  │   ├── Install AUR packages (google-chrome, dropbox, python-gpgme)
  │   ├── Install global npm tools (claude-code)
  │   ├── Enable services (sddm, bluetooth, docker)
  │   └── Remove temp sudo rule
  │
  ├── Post-chroot fixups (resolv.conf symlink)
  │
  └── Cleanup + reboot
```

---

## Partition Layout

```
/dev/sdX1  1G      EFI System Partition (FAT32)     → /boot
/dev/sdX2  RAM*    Linux Swap (hibernate-capable)
/dev/sdX3  128G    Linux Root (ext4)                 → /
/dev/sdX4  rest    Linux Home (ext4)                 → /home
```

\* Swap = total RAM rounded up, minimum 8G. Hibernation enabled via `resume=` boot param.

On reinstall, the installer detects an existing partition 4 and asks whether to
wipe or keep `/home`. If kept, only partitions 1-3 are recreated.

---

## Dual-Boot Notes

On a machine with two SSDs (e.g., Windows on one, Arch on the other):
- Each SSD gets its own EFI partition and bootloader
- Use the motherboard's UEFI boot menu (F12/F8/Del) to switch between OSes
- systemd-boot does not auto-detect Windows — OS switching is at firmware level
- The installer only touches the selected target disk
