#!/usr/bin/env bash
# Downloads and verifies the latest Arch Linux ISO.
#
# 1. Queries the Arch Linux releases API for the latest version + SHA256
# 2. Downloads the ISO from the official Tier 1 geo mirror
# 3. Downloads the .sig file from archlinux.org directly
# 4. Verifies the SHA256 checksum
# 5. Verifies the GPG signature (optional, requires gpg)
# 6. Saves everything to tests/iso/
#
# Usage: ./tests/linux/download-iso.sh [--force] [--skip-gpg]

set -euo pipefail

# --- Configuration ---

RELEASES_API_URL="https://archlinux.org/releng/releases/json/"
MIRROR_BASE="https://geo.mirror.pkgbuild.com/iso"
SIG_BASE="https://archlinux.org/iso"
SIGNING_KEY_FINGERPRINT="3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C"
SIGNING_KEY_EMAIL="pierre@archlinux.org"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$(dirname "$SCRIPT_DIR")/iso"

# --- Parse arguments ---

FORCE=false
SKIP_GPG=false

for arg in "$@"; do
  case "$arg" in
    --force)    FORCE=true ;;
    --skip-gpg) SKIP_GPG=true ;;
    *)
      printf 'Usage: %s [--force] [--skip-gpg]\n' "$0" >&2
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

for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    print_fail "$cmd is required but not installed."
    exit 1
  fi
done

# --- Get latest release ---

print_step "Querying Arch Linux releases API..."

release_json=$(curl -fsSL "$RELEASES_API_URL")
version=$(printf '%s' "$release_json" | jq -r '[.releases[] | select(.available == true)] | sort_by(.release_date) | reverse | .[0].version')
expected_sha256=$(printf '%s' "$release_json" | jq -r '[.releases[] | select(.available == true)] | sort_by(.release_date) | reverse | .[0].sha256_sum')
kernel_version=$(printf '%s' "$release_json" | jq -r '[.releases[] | select(.available == true)] | sort_by(.release_date) | reverse | .[0].kernel_version')

if [[ -z "$version" || "$version" == "null" ]]; then
  print_fail "No available release found from the API."
  exit 1
fi

print_ok "Latest release: $version (kernel $kernel_version)"

iso_filename="archlinux-${version}-x86_64.iso"
sig_filename="${iso_filename}.sig"
iso_path="${OUTPUT_DIR}/${iso_filename}"
sig_path="${OUTPUT_DIR}/${sig_filename}"
iso_url="${MIRROR_BASE}/${version}/${iso_filename}"
sig_url="${SIG_BASE}/${version}/${sig_filename}"

# --- Create output directory ---

mkdir -p "$OUTPUT_DIR"

# --- Check if ISO already exists ---

if [[ -f "$iso_path" ]] && [[ "$FORCE" == "false" ]]; then
  print_step "ISO already exists: $iso_path"
  existing_hash=$(sha256sum "$iso_path" | awk '{print $1}')

  if [[ "$existing_hash" == "${expected_sha256,,}" ]]; then
    print_ok "Existing ISO matches latest release ($version). No download needed."
    print_detail "Use --force to re-download."
    exit 0
  else
    print_detail "Existing ISO does not match latest release. Re-downloading..."
    rm -f "$iso_path" "$sig_path"
  fi
fi

# --- Download ISO ---

print_step "Downloading Arch Linux $version ISO..."
print_detail "URL: $iso_url"
curl -fL --progress-bar -o "$iso_path" "$iso_url"

actual_size=$(stat -c%s "$iso_path")
actual_mb=$(( actual_size / 1048576 ))
print_ok "Downloaded: $iso_path (${actual_mb} MB)"

# --- Download signature ---

print_step "Downloading GPG signature..."
print_detail "URL: $sig_url"
curl -fsSL -o "$sig_path" "$sig_url"
print_ok "Downloaded: $sig_path"

# --- Verify SHA256 ---

print_step "Verifying SHA256 checksum..."
print_detail "Expected: $expected_sha256"

actual_sha256=$(sha256sum "$iso_path" | awk '{print $1}')
print_detail "Actual:   $actual_sha256"

if [[ "$actual_sha256" == "${expected_sha256,,}" ]]; then
  print_ok "SHA256 checksum matches."
else
  print_fail "SHA256 MISMATCH! The ISO may be corrupted or tampered with."
  rm -f "$iso_path" "$sig_path"
  exit 1
fi

# --- Verify GPG signature ---

if [[ "$SKIP_GPG" == "true" ]]; then
  print_step "Skipping GPG verification (--skip-gpg flag)."
  print_detail "SHA256 passed - ISO integrity confirmed against the API."
else
  print_step "Verifying GPG signature..."

  if ! command -v gpg &>/dev/null; then
    print_fail "GPG not found. Install gnupg to enable signature verification."
    print_detail "SHA256 passed, so the ISO is likely fine — GPG adds another layer of trust."
  else
    # Fetch the signing key
    print_detail "Fetching Arch Linux release signing key..."
    if ! gpg --auto-key-locate clear,wkd -v --locate-external-key "$SIGNING_KEY_EMAIL" &>/dev/null; then
      print_detail "WKD fetch failed, trying keyserver..."
      gpg --keyserver keyserver.ubuntu.com --recv-keys "$SIGNING_KEY_FINGERPRINT" 2>/dev/null || true
    fi

    # Verify
    print_detail "Verifying signature..."
    if gpg --verify "$sig_path" "$iso_path" 2>/dev/null; then
      print_ok "GPG signature is valid."
    else
      print_fail "GPG signature verification FAILED!"
      print_detail "SHA256 passed, so this may be a key trust issue. Check manually."
    fi
  fi
fi

# --- Summary ---

printf '\n\033[90m=====================================\033[0m\n'
print_ok "ISO ready: $iso_path"
print_detail "Version: $version"
print_detail "Use this ISO to create a QEMU/KVM VM (see tests/README.md)"
printf '\n'
