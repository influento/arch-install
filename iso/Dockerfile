FROM archlinux:latest

# Refresh keyring first to avoid signature issues, then install archiso
RUN pacman -Sy --noconfirm archlinux-keyring && \
    pacman -Su --noconfirm archiso git && \
    pacman -Scc --noconfirm

WORKDIR /build

ENTRYPOINT ["/build/iso/build.sh"]
