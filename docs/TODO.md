# TODO - Custom Arch Linux Installer

## Completed

- **Phase 0**: Foundation (entry point, logging, checks, config system)
- **Phase 1**: Base system (disk, pacstrap, configure, bootloader, user creation)
- **Phase 2**: Workstation profile (Sway/Wayland desktop, dev tools, GPU, audio, dotfiles integration)
- **Unattended mode**: `--auto` flag for fully non-interactive installs, all input collected up front
- **Custom ISO**: Docker + archiso, auto-launch menu on boot (full / test / shell)
- **Virtualization**: QEMU/KVM + virt-manager module
- **Desktop apps**: Obsidian, KeePassXC, OBS, GIMP, LibreOffice installed directly
- **Clipboard history**: cliphist (Wayland-native)
- **Blue light filter**: wlsunset (Wayland-native)
- **Claude Code**: installed via npm globally
- **Phase 3**: Configuration deployment (dotfiles integration complete, user configs in dotfiles repo)

## Phase 4: Interactive Feature Selection

- [ ] Simple TUI menu using `gum` or `dialog` for optional features
- [ ] Feature flags system (enable/disable features via config or menu)

## Phase 5: Testing and Hardening

- [x] ShellCheck all scripts (clean as of current session)
- [x] Hyper-V VM test setup (configs + README in tests/)
- [x] Test workstation profile end-to-end in VM (packages, services, dotfiles all verified)
- [x] Test dotfiles integration in VM (symlinks, zsh, .config/* all correct)
- [x] Test on physical hardware (AMD GPU, dual-boot — system installs and boots, Sway black screen was dotfiles-side)
- [ ] Test with different disk layouts (single disk, NVMe, multiple disks)
- [ ] Idempotency checks (re-running scripts doesn't break things)
- [ ] Error recovery (resume after failure)

## Future Ideas (Backlog)

- [ ] Optional module: Gaming (Steam, Lutris, gamemode, mangohud)
- [ ] Optional module: Remote desktop (remmina, freerdp)
- [ ] Optional module: Container orchestration (k3s, podman)
- [ ] Encryption support (LUKS)
- [ ] Btrfs snapshots with Snapper
- [ ] Secure Boot support
- [ ] Post-install update/maintenance script
- [ ] Hardware-specific quirks (laptop lid, touchpad, etc.)

---

## Reference Links

- [Arch Wiki - Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [archinstall](https://github.com/archlinux/archinstall)
- [omarchy](https://github.com/basecamp/omarchy)
