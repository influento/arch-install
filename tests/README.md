# Testing the Arch Installer

## Hyper-V VM Setup

### 1. Build the Custom ISO

Builds a custom ISO with the installer scripts pre-loaded. Requires Docker.

```bash
docker build -t archiso-builder iso/
docker run --rm --privileged -v "$(pwd)":/build archiso-builder
```

Output: `iso/out/archinstall-custom-*.iso`

On boot, the ISO auto-launches a menu:
1. **Full installation** (interactive)
2. **Test installation** (VM, unattended)
3. **Drop to shell**

### 2. Create the VM

From the project root (requires Administrator):

```powershell
.\tests\create-vm.ps1
```

Creates a Gen 2 UEFI VM with:
- Secure Boot disabled, DVD boot first
- 8 GB RAM (override with `-MemoryMB`)
- 60 GB dynamic VHDX (override with `-DiskSizeGB`)
- 2 vCPUs, connected to Default Switch
- Arch ISO auto-detected (prefers custom from `iso/out/`, falls back to `tests/iso/`)

Options:
- `-Name MyVM` — custom VM name (default: `ArchTest`)
- `-MemoryMB 4096` — override RAM
- `-DiskSizeGB 100` — override disk size
- `-SwitchName "My Switch"` — use a different virtual switch
- `-IsoPath C:\path\to\arch.iso` — use a specific ISO

### 3. Boot and Run

```powershell
Start-VM -Name "ArchTest"
vmconnect localhost "ArchTest"
```

On boot, select **2) Test installation** from the menu. The install runs fully
unattended using `tests/vm-test.conf` (password: `test`).

After install completes, the VM auto-reboots. Remove the DVD to boot from disk:

```powershell
Stop-VM -Name "ArchTest" -Force
Get-VMDvdDrive -VMName "ArchTest" | Remove-VMDvdDrive
Start-VM -Name "ArchTest"
```

### 4. What to Verify After Install

**Services:**
- [ ] `systemctl status sddm` — enabled, running
- [ ] `systemctl status bluetooth` — enabled (inactive without hardware)
- [ ] `systemctl status docker` — active (running)
- [ ] `systemctl status libvirtd` — enabled
- [ ] `systemctl status nftables` — enabled, rules loaded

**Packages:**
- [ ] `docker run hello-world`
- [ ] `google-chrome-stable --version`
- [ ] `shellcheck --version`
- [ ] `fastfetch`
- [ ] `virsh --version`
- [ ] `claude --version`
- [ ] `pacman -Q dropbox python-gpgme`
- [ ] Dev tools: `lazygit`, `fzf`, `bat`, `eza`, `zoxide`, `fd`
- [ ] Languages: `rustc`, `go version`, `dotnet --version`, `node --version`

**System:**
- [ ] `groups $USER` shows: wheel docker libvirt
- [ ] `echo $SHELL` shows: /usr/bin/zsh
- [ ] `ls /etc/sudoers.d/` shows only `00-editor` (temp file cleaned up)
- [ ] Dotfiles deployed: `ls -la ~/.dotfiles`

**GUI (requires display — skip in TTY):**
- [ ] SDDM login screen appears
- [ ] Sway session starts after login
- [ ] Ghostty terminal opens
- [ ] KeePassXC, OBS, GIMP, LibreOffice launch

### 5. Cleanup

To retest from scratch:

```powershell
Remove-VM -Name "ArchTest" -Force
Remove-Item "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\ArchTest.vhdx" -Force
.\tests\create-vm.ps1
```

## Physical Hardware Testing

1. Flash the custom ISO to USB (Rufus or `dd`)
2. Boot from USB on the target machine
3. Select **1) Full installation** from the menu
4. Answer prompts (username, hostname, timezone, passwords, disk)
5. Walk away — install runs unattended after confirmation

For dual-boot: select the correct SSD (not the Windows drive).
