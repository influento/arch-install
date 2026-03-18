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
- **Bluetooth**: Removed blueman, replaced with custom Waybar BT widget (in dotfiles repo)
- **Custom apps**: Generic GitHub release installer (`packages/custom-apps.conf` + `lib/packages.sh`)

## Testing

- [x] ShellCheck all scripts (clean as of current session)
- [x] Hyper-V VM test setup (configs + README in tests/windows/)
- [x] QEMU/KVM VM test setup (download-iso.sh + create-vm.sh in tests/linux/)
- [x] Test workstation profile end-to-end in VM (packages, services, dotfiles all verified)
- [x] Test dotfiles integration in VM (symlinks, zsh, .config/* all correct)
- [x] Test on physical hardware (AMD GPU, dual-boot — system installs and boots, Sway black screen was dotfiles-side)

## Bluetooth Persistence Test Plan

Test the Keychron BT keyboard across all sleep/boot scenarios.
Run these in order and report results to Claude Code after each step.

0. **Diagnose connect/disconnect cycle** — RESOLVED
   - Root cause: blueman pairs but does NOT bond — no `[LinkKey]` written to `/var/lib/bluetooth/.../info`
   - Without a stored link key, pairing works in-session but is lost on reboot
   - The keyboard reconnects after reboot, host has no link key, keyboard drops: `Reason.Remote`
   - Fix: pair via `bluetoothctl pair <MAC>` which performs full SSP bonding (link key persisted)
   - Also ran `bluetoothctl trust <MAC>` and `bluetoothctl connect <MAC>`
   - Verified `[LinkKey]` section now exists in the stored device info file
   - `ClassicBondedOnly=false` in input.conf was a red herring — it allows input without bonding,
     but the real problem was that blueman never created a bond in the first place
1. **Pair + trust** — done via `bluetoothctl pair/trust/connect` (blueman pairing is insufficient)
   - Verified: Paired=yes, Bonded=yes, Trusted=yes, Connected=yes
2. **Cold boot** — PASSED — keyboard auto-connected on boot
   - `bluetoothctl devices Connected` — shows the Keychron
3. **swaylock** — lock the screen (`swaylock`), type password on BT keyboard, unlock
4. **Suspend** — `systemctl suspend`, wake the machine, try typing immediately
   - If keyboard doesn't respond, wait ~5s for the sleep hook to restart bluetooth
   - `bluetoothctl devices Connected` — verify reconnection
5. **Hibernate** — `systemctl hibernate`, power back on, try typing
   - Same checks as suspend
6. **Suspend + swaylock** — lock screen, close lid / suspend, wake, type password to unlock

If any step fails, run `journalctl -u bluetooth --since "5 min ago"` and share the output.

### Resolved: Blueman replaced with custom Waybar widget

Blueman paired devices without bonding (no `[LinkKey]` persisted), breaking BT keyboards on
every reboot. Replaced with a custom Waybar bluetooth widget (in dotfiles repo) that wraps
`bluetoothctl` directly — proper SSP bonding, scan, pair, trust, connect, disconnect.
Blueman removed from `packages/workstation.list`.

## Future Ideas (Backlog)

- [ ] Interactive feature selection (TUI menu with `gum` or `dialog`)
- [ ] Feature flags system (enable/disable features via config or menu)
- [ ] Test with different disk layouts (single disk, NVMe, multiple disks)
- [ ] Idempotency checks (re-running scripts doesn't break things)
- [ ] Error recovery (resume after failure)
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
