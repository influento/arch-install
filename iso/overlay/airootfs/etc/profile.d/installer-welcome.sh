#!/usr/bin/env bash
# Auto-launch installer menu on first login
if [[ -d /root/arch-install ]] && [[ -z "${_INSTALLER_SHOWN:-}" ]]; then
  export _INSTALLER_SHOWN=1

  printf '\n'
  printf '\033[1;36m  ===  Custom Arch Linux Installer  ===\033[0m\n'
  printf '\n'
  printf '  1) \033[1mFull installation\033[0m (interactive)\n'
  printf '  2) \033[1mTest installation\033[0m (VM, unattended)\n'
  printf '  3) \033[1mDrop to shell\033[0m\n'
  printf '\n'
  printf '  Select [1-3]: '

  read -r choice
  case "$choice" in
    1)
      bash /root/arch-install/install.sh
      ;;
    2)
      bash /root/arch-install/install.sh --config /root/arch-install/tests/vm-test.conf --auto
      ;;
    3|*)
      printf '\n  Dropped to shell. Run manually:\n'
      printf '    \033[1mbash /root/arch-install/install.sh\033[0m\n'
      printf '    \033[1mbash /root/arch-install/install.sh --help\033[0m\n\n'
      ;;
  esac
fi
