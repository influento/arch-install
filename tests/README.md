# Testing the Arch Installer

## Directory Layout

```
tests/
├── linux/              # QEMU/KVM scripts (Linux host)
│   ├── create-vm.sh
│   └── download-iso.sh
├── windows/            # Hyper-V scripts (Windows host)
│   ├── create-vm.ps1
│   └── download-iso.ps1
├── vm-test.conf        # Shared VM test config
└── README.md
```

## Building the Custom ISO

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

---

## Linux (QEMU/KVM)

### Prerequisites

- `qemu-full` (provides `qemu-system-x86_64`)
- `edk2-ovmf` (UEFI firmware)
- KVM enabled (check: `lsmod | grep kvm`)

### 1. Download the ISO

```bash
./tests/linux/download-iso.sh
```

Downloads the latest Arch ISO, verifies SHA256 and GPG signature. Saves to `tests/iso/`.

Options:
- `--force` — re-download even if ISO exists
- `--skip-gpg` — skip GPG signature verification

### 2. Create and Launch the VM

```bash
./tests/linux/create-vm.sh
```

Creates a UEFI VM with QEMU/KVM and launches it immediately:
- 8 GB RAM, 2 CPUs, 60 GB VirtIO disk
- OVMF UEFI firmware (no Secure Boot)
- User-mode networking (internet access, no root required)
- ISO auto-detected (prefers custom from `iso/out/`, falls back to `tests/iso/`)
- QEMU monitor on stdio for VM control

Options:
- `--name NAME` — VM name (default: `archtest`)
- `--memory MB` — RAM in MB (default: `8192`)
- `--cpus N` — number of CPUs (default: `2`)
- `--disk-size GB` — disk size in GB (default: `60`)
- `--iso PATH` — use a specific ISO
- `--no-launch` — create disk and print command without launching

### 3. Run the Install

On boot, select **2) Test installation** from the menu. The install runs fully
unattended using `tests/vm-test.conf` (password: `test`).

After install completes, the VM auto-reboots. Eject the ISO to boot from disk:
- In the QEMU monitor (the terminal where you launched): type `eject ide1-cd0`
- Or stop the VM and re-launch without the `-cdrom` and `-boot d` flags

### 4. Cleanup

To retest from scratch:

```bash
rm tests/vm/archtest.qcow2 tests/vm/archtest_VARS.fd
./tests/linux/create-vm.sh
```

---

## Windows (Hyper-V)

### 1. Download the ISO

```powershell
.\tests\windows\download-iso.ps1
```

Options:
- `-Force` — re-download even if ISO exists
- `-SkipGpg` — skip GPG signature verification

### 2. Create the VM

From the project root (requires Administrator):

```powershell
.\tests\windows\create-vm.ps1
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

On boot, select **2) Test installation** from the menu.

After install completes, remove the DVD to boot from disk:

```powershell
Stop-VM -Name "ArchTest" -Force
Get-VMDvdDrive -VMName "ArchTest" | Remove-VMDvdDrive
Start-VM -Name "ArchTest"
```

### 4. Cleanup

```powershell
Remove-VM -Name "ArchTest" -Force
Remove-Item "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\ArchTest.vhdx" -Force
.\tests\windows\create-vm.ps1
```

---

## VM Test Config

The shared config `tests/vm-test.conf` works with both hypervisors.

**Note:** The `TARGET_DISK` is set to `/dev/vda` (QEMU VirtIO). If testing with
Hyper-V, change it to `/dev/sda`.

---

## What to Verify After Install

**Services:**
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
- [ ] `ls /etc/sudoers.d/` shows `00-editor` and `10-nopasswd` (temp file cleaned up)
- [ ] Dotfiles deployed: `ls ~/dev/infra/dotfiles`
- [ ] Infra repos cloned: `ls ~/dev/infra/` shows dotfiles, arch-install, debian-server

**GUI (requires display — skip in TTY):**
- [ ] TTY1 autologin works (user is logged in automatically)
- [ ] Sway starts automatically on login
- [ ] Ghostty terminal opens
- [ ] KeePassXC, OBS, GIMP, LibreOffice launch

## Physical Hardware Testing

1. Flash the custom ISO to USB (Ventoy or `dd`)
2. Boot from USB on the target machine
3. Select **1) Full installation** from the menu
4. Answer prompts (username, hostname, timezone, passwords, disk)
5. Walk away — install runs unattended after confirmation

For dual-boot: select the correct SSD (not the Windows drive).
