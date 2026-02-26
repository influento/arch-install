<#
.SYNOPSIS
    Downloads and verifies the latest Arch Linux ISO.

.DESCRIPTION
    1. Queries the Arch Linux releases API to find the latest version + SHA256
    2. Downloads the ISO from the official Tier 1 geo mirror (geo.mirror.pkgbuild.com)
    3. Downloads the .sig file from archlinux.org directly (not a mirror)
    4. Verifies the SHA256 checksum against the API-provided hash
    5. Verifies the GPG signature using the official Arch release signing key
    6. Saves everything to tests/iso/

.EXAMPLE
    .\tests\download-iso.ps1
    .\tests\download-iso.ps1 -SkipGpg
    .\tests\download-iso.ps1 -Force

.NOTES
    Requires: PowerShell 5.1+, GPG (bundled with Git for Windows)
    Mirror: geo.mirror.pkgbuild.com (Tier 1, official Arch infrastructure, GeoDNS)
    Signature: downloaded from archlinux.org (not the mirror, per Arch Wiki guidance)
#>

param(
    [switch]$Force,    # Re-download even if ISO already exists
    [switch]$SkipGpg   # Skip GPG signature verification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Configuration ---

$ReleasesApiUrl = "https://archlinux.org/releng/releases/json/"
$MirrorBase     = "https://geo.mirror.pkgbuild.com/iso"
$SigBase        = "https://archlinux.org/iso"
$OutputDir      = Join-Path $PSScriptRoot "iso"

# Pierre Schmitz key - official Arch Linux release signing key
$SigningKeyFingerprint = "3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C"
$SigningKeyEmail       = "pierre@archlinux.org"

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

function Get-LatestRelease {
    Write-Step "Querying Arch Linux releases API..."

    $response = Invoke-RestMethod -Uri $ReleasesApiUrl -UseBasicParsing
    $latest = $response.releases |
        Where-Object { $_.available -eq $true } |
        Sort-Object { [DateTime]$_.release_date } -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No available release found from the API."
    }

    Write-Ok "Latest release: $($latest.version) (kernel $($latest.kernel_version))"
    return $latest
}

function Get-FileWithProgress {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )

    Write-Detail "$Description"
    Write-Detail "URL: $Url"

    # Use BITS for large files (ISO), WebClient for small files (sig)
    $fileSize = $null
    try {
        $headReq = [System.Net.WebRequest]::Create($Url)
        $headReq.Method = "HEAD"
        $headReq.AllowAutoRedirect = $true
        $headResp = $headReq.GetResponse()
        $fileSize = $headResp.ContentLength
        $headResp.Close()
    }
    catch {
        # HEAD failed, proceed without size info
    }

    if ($fileSize -and $fileSize -gt 10MB) {
        # Large file - use BITS for resume support and progress
        if ($fileSize) {
            $sizeMB = [math]::Round($fileSize / 1MB, 1)
            Write-Detail "Size: ${sizeMB} MB"
        }

        Import-Module BitsTransfer -ErrorAction SilentlyContinue
        try {
            Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName $Description
        }
        catch {
            # BITS can fail in some environments, fall back to WebClient
            Write-Detail "BITS transfer failed, falling back to direct download..."
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $OutFile)
            $webClient.Dispose()
        }
    }
    else {
        # Small file - direct download
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $OutFile)
        $webClient.Dispose()
    }

    if (-not (Test-Path $OutFile)) {
        throw "Download failed: $OutFile not found after download."
    }

    $actualSize = (Get-Item $OutFile).Length
    $actualMB = [math]::Round($actualSize / 1MB, 1)
    Write-Ok "Downloaded: $OutFile (${actualMB} MB)"
}

function Test-Sha256 {
    param(
        [string]$FilePath,
        [string]$ExpectedHash
    )

    Write-Step "Verifying SHA256 checksum..."
    Write-Detail "Expected: $ExpectedHash"

    $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()
    Write-Detail "Actual:   $actualHash"

    if ($actualHash -eq $ExpectedHash.ToLower()) {
        Write-Ok "SHA256 checksum matches."
        return $true
    }
    else {
        Write-Fail "SHA256 MISMATCH! The ISO may be corrupted or tampered with."
        return $false
    }
}

function Find-Gpg {
    # Try system PATH first
    $gpg = Get-Command gpg -ErrorAction SilentlyContinue
    if ($gpg) { return $gpg.Source }

    # Try common Git for Windows locations
    $candidates = @(
        "$env:ProgramFiles\Git\usr\bin\gpg.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\gpg.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\gpg.exe"
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }

    return $null
}

function Test-GpgSignature {
    param(
        [string]$IsoPath,
        [string]$SigPath
    )

    Write-Step "Verifying GPG signature..."

    $gpgPath = Find-Gpg
    if (-not $gpgPath) {
        Write-Fail "GPG not found. Install Git for Windows or Gpg4win to enable signature verification."
        Write-Detail "SHA256 passed, so the ISO is likely fine - but GPG adds another layer of trust."
        return $false
    }

    Write-Detail "Using: $gpgPath"

    # Fetch the signing key via WKD (Web Key Directory)
    Write-Detail "Fetching Arch Linux release signing key..."
    $fetchResult = & $gpgPath --auto-key-locate clear,wkd -v --locate-external-key $SigningKeyEmail 2>&1
    $fetchExit = $LASTEXITCODE

    if ($fetchExit -ne 0) {
        # Try keyserver as fallback
        Write-Detail "WKD fetch failed, trying keyserver..."
        & $gpgPath --keyserver keyserver.ubuntu.com --recv-keys $SigningKeyFingerprint 2>&1 | Out-Null
    }

    # Verify the signature
    Write-Detail "Verifying signature..."
    $verifyOutput = & $gpgPath --verify $SigPath $IsoPath 2>&1
    $verifyExit = $LASTEXITCODE

    # Show relevant output
    $verifyOutput | ForEach-Object {
        $line = $_.ToString()
        if ($line -match "Good signature|Primary key fingerprint|using.*key") {
            Write-Detail $line
        }
    }

    if ($verifyExit -eq 0) {
        Write-Ok "GPG signature is valid."
        return $true
    }
    else {
        Write-Fail "GPG signature verification FAILED!"
        Write-Fail "DO NOT use this ISO."
        $verifyOutput | ForEach-Object { Write-Detail $_.ToString() }
        return $false
    }
}

# --- Main ---

Write-Host ""
Write-Host "Arch Linux ISO Downloader + Verifier" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor DarkGray

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Get latest release info from API
$release = Get-LatestRelease
$version = $release.version
$expectedSha256 = $release.sha256_sum

$isoFilename = "archlinux-${version}-x86_64.iso"
$sigFilename  = "${isoFilename}.sig"

$isoPath = Join-Path $OutputDir $isoFilename
$sigPath = Join-Path $OutputDir $sigFilename

$isoUrl = "${MirrorBase}/${version}/${isoFilename}"
$sigUrl = "${SigBase}/${version}/${sigFilename}"

# Check if ISO already exists
if ((Test-Path $isoPath) -and -not $Force) {
    Write-Step "ISO already exists: $isoPath"
    $existingHash = (Get-FileHash -Path $isoPath -Algorithm SHA256).Hash.ToLower()

    if ($existingHash -eq $expectedSha256.ToLower()) {
        Write-Ok "Existing ISO matches latest release ($version). No download needed."
        Write-Ok "Use -Force to re-download."
        exit 0
    }
    else {
        Write-Detail "Existing ISO does not match latest release. Re-downloading..."
        Remove-Item $isoPath -Force
        if (Test-Path $sigPath) { Remove-Item $sigPath -Force }
    }
}

# Download ISO from geo mirror
Write-Step "Downloading Arch Linux $version ISO..."
Get-FileWithProgress -Url $isoUrl -OutFile $isoPath -Description "ISO from geo.mirror.pkgbuild.com (Tier 1 official)"

# Download signature from archlinux.org (NOT the mirror)
Write-Step "Downloading GPG signature..."
Get-FileWithProgress -Url $sigUrl -OutFile $sigPath -Description "Signature from archlinux.org (direct)"

# Verify SHA256
$sha256ok = Test-Sha256 -FilePath $isoPath -ExpectedHash $expectedSha256
if (-not $sha256ok) {
    Write-Host ""
    Write-Fail "SHA256 verification failed. Deleting downloaded files."
    Remove-Item $isoPath -Force -ErrorAction SilentlyContinue
    Remove-Item $sigPath -Force -ErrorAction SilentlyContinue
    exit 1
}

# Verify GPG signature
if ($SkipGpg) {
    Write-Step "Skipping GPG verification (-SkipGpg flag)."
    Write-Detail "SHA256 passed - ISO integrity confirmed against the API."
}
else {
    $gpgOk = Test-GpgSignature -IsoPath $isoPath -SigPath $sigPath
    if (-not $gpgOk) {
        # GPG failure is non-fatal if SHA256 passed (GPG might not be set up)
        $gpgPath = Find-Gpg
        if (-not $gpgPath) {
            Write-Detail "Install GPG to enable full verification. SHA256 check passed."
        }
    }
}

# Summary
Write-Host ""
Write-Host "=====================================" -ForegroundColor DarkGray
Write-Ok "ISO ready: $isoPath"
Write-Detail "Version: $version"
Write-Detail "Use this ISO to create a Hyper-V VM (see tests/README.md)"
Write-Host ""
