<#
.SYNOPSIS
    Creates a Hyper-V VM for testing the Arch Linux installer.

.DESCRIPTION
    Creates a Generation 2 (UEFI) VM with:
    - Secure Boot disabled (required for Arch ISO)
    - Configurable RAM and CPU
    - Dynamic expanding VHDX
    - Arch ISO attached as DVD
    - Connected to Default Switch for internet access
    - Boot order set to DVD first

    Requires Administrator privileges (will self-elevate if needed).

.PARAMETER Name
    VM name. Default: ArchTest

.PARAMETER MemoryMB
    RAM in MB. Default: 8192

.PARAMETER CPUs
    Number of virtual processors. Default: 2

.PARAMETER DiskSizeGB
    VHDX disk size in GB. Default: 60

.PARAMETER SwitchName
    Hyper-V virtual switch name. Default: Default Switch

.PARAMETER IsoPath
    Path to the Arch ISO. Default: auto-detect from tests/iso/

.EXAMPLE
    .\tests\create-vm.ps1
    .\tests\create-vm.ps1 -Name MyArch -MemoryMB 4096 -DiskSizeGB 100
#>

param(
    [string]$Name = "ArchTest",
    [int]$MemoryMB = 8192,
    [int]$CPUs = 2,
    [int]$DiskSizeGB = 60,
    [string]$SwitchName = "Default Switch",
    [string]$IsoPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Self-elevation ---

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host "Hyper-V requires Administrator privileges. Elevating..." -ForegroundColor Yellow

    # Rebuild the argument list preserving all parameters
    # Values with spaces must be wrapped in escaped quotes for Start-Process
    $argList = @("-ExecutionPolicy", "Bypass", "-File", "`"$($MyInvocation.MyCommand.Path)`"")
    if ($Name)       { $argList += "-Name";       $argList += "`"$Name`"" }
    if ($MemoryMB)   { $argList += "-MemoryMB";   $argList += $MemoryMB }
    if ($CPUs)       { $argList += "-CPUs";       $argList += $CPUs }
    if ($DiskSizeGB) { $argList += "-DiskSizeGB"; $argList += $DiskSizeGB }
    if ($SwitchName) { $argList += "-SwitchName"; $argList += "`"$SwitchName`"" }
    if ($IsoPath)    { $argList += "-IsoPath";    $argList += "`"$IsoPath`"" }

    Start-Process powershell -Verb RunAs -ArgumentList $argList -Wait
    exit 0
}

# --- Functions ---

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> " -ForegroundColor Cyan -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    [OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [FAIL] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Detail {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

# --- Resolve defaults ---

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# ISO path - auto-detect: prefer custom ISO from iso/out/, fall back to tests/iso/
if (-not $IsoPath) {
    $repoRoot = Split-Path -Parent $ScriptDir
    $customIsoDir = Join-Path (Join-Path $repoRoot "iso") "out"
    $stockIsoDir = Join-Path $ScriptDir "iso"

    # Check for custom ISO first
    $isos = @(Get-ChildItem -Path $customIsoDir -Filter "archinstall-custom-*.iso" -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending)

    if ($isos.Count -gt 0) {
        Write-Detail "Found custom ISO in iso/out/"
    }
    else {
        # Fall back to stock ISO
        $isos = @(Get-ChildItem -Path $stockIsoDir -Filter "archlinux-*.iso" -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending)
    }

    if ($isos.Count -eq 0) {
        Write-Fail "No Arch ISO found."
        Write-Host "    Build a custom ISO:       docker build -t archiso-builder iso/ && docker run --rm --privileged -v `"`$(pwd)`":/build archiso-builder" -ForegroundColor Yellow
        Write-Host "    Or download a stock ISO:  .\tests\download-iso.ps1" -ForegroundColor Yellow
        if ([Environment]::UserInteractive -and -not $env:CI) { Read-Host "Press Enter to exit" }
        exit 1
    }

    $IsoPath = $isos[0].FullName
}

if (-not (Test-Path $IsoPath)) {
    Write-Fail "ISO not found: $IsoPath"
    if ([Environment]::UserInteractive -and -not $env:CI) { Read-Host "Press Enter to exit" }
    exit 1
}

# --- Main ---

Write-Host ""
Write-Host "Hyper-V VM Creator - Arch Linux Installer Testing" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor DarkGray

# Check if VM already exists
$existingVm = Get-VM -Name $Name -ErrorAction SilentlyContinue
if ($existingVm) {
    Write-Fail "VM '$Name' already exists."
    Write-Detail "To recreate: Remove-VM -Name '$Name' -Force; then re-run this script."
    Write-Detail "To just start: Start-VM -Name '$Name'"
    if ([Environment]::UserInteractive -and -not $env:CI) { Read-Host "Press Enter to exit" }
    exit 1
}

# Check virtual switch exists
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $switch) {
    Write-Fail "Virtual switch '$SwitchName' not found."
    Write-Detail "Available switches:"
    Get-VMSwitch | ForEach-Object { Write-Detail "  - $($_.Name) ($($_.SwitchType))" }
    if ([Environment]::UserInteractive -and -not $env:CI) { Read-Host "Press Enter to exit" }
    exit 1
}

# Determine VHDX path
$vmHost = Get-VMHost
$vhdxDir = $vmHost.VirtualHardDiskPath
if (-not $vhdxDir) {
    $vhdxDir = "C:\Hyper-V\Virtual Hard Disks"
}
$vhdxPath = Join-Path $vhdxDir "$Name.vhdx"

Write-Step "Configuration"
Write-Detail "VM Name:     $Name"
Write-Detail "Memory:      $MemoryMB MB"
Write-Detail "CPUs:        $CPUs"
Write-Detail "Disk:        $DiskSizeGB GB (dynamic) -> $vhdxPath"
Write-Detail "Switch:      $SwitchName"
Write-Detail "ISO:         $IsoPath"

# Create VM
Write-Step "Creating VM: $Name"
$vm = New-VM -Name $Name `
    -Generation 2 `
    -MemoryStartupBytes ($MemoryMB * 1MB) `
    -NewVHDPath $vhdxPath `
    -NewVHDSizeBytes ($DiskSizeGB * 1GB) `
    -SwitchName $SwitchName

Write-Ok "VM created."

# Configure processors
Write-Step "Configuring hardware..."
Set-VMProcessor -VM $vm -Count $CPUs
Write-Ok "CPUs: $CPUs"

# Disable Secure Boot (required for Arch ISO)
Set-VMFirmware -VM $vm -EnableSecureBoot Off
Write-Ok "Secure Boot: disabled"

# Add DVD drive with ISO
$dvd = Add-VMDvdDrive -VM $vm -Path $IsoPath -Passthru
Write-Ok "DVD: $IsoPath"

# Set boot order: DVD first, then hard disk
$hdd = Get-VMHardDiskDrive -VM $vm
Set-VMFirmware -VM $vm -BootOrder $dvd, $hdd
Write-Ok "Boot order: DVD -> HDD"

# Enable checkpoints
Set-VM -VM $vm -CheckpointType Standard
Write-Ok "Checkpoints: enabled (standard)"

# Summary
Write-Host ""
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Ok "VM '$Name' is ready."
Write-Host ""
Write-Host "    Next steps:" -ForegroundColor White
Write-Host "    1. Start the VM:  " -NoNewline -ForegroundColor DarkGray
Write-Host "Start-VM -Name '$Name'" -ForegroundColor Cyan
Write-Host "    2. Connect to it: " -NoNewline -ForegroundColor DarkGray
Write-Host "vmconnect localhost '$Name'" -ForegroundColor Cyan
Write-Host "    3. At the Arch live prompt, get the installer scripts in"
Write-Host "    4. Run: bash install.sh --config tests/vm-test.conf" -ForegroundColor Cyan
Write-Host ""

if ([Environment]::UserInteractive -and -not $env:CI) { Read-Host "Press Enter to exit" }
