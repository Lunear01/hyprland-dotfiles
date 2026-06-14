#!/usr/bin/env bash
#
# setup.sh — Install all dependencies for Lunear01's Hyprland dotfiles
# and symlink the configs into place with GNU stow.
#
# Supported distros: Arch (pacman + AUR) and Fedora (dnf + COPR + flatpak).
#
# Usage:
#   ./setup.sh            # install everything + stow
#   ./setup.sh --no-stow  # only install packages, skip stowing
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOW=1

for arg in "$@"; do
    case "$arg" in
        --no-stow) STOW=0 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

info()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# Packages that this script cannot install automatically on the current
# distro — collected here and reported at the end.
MANUAL_NOTES=()

[[ "$(id -u)" -eq 0 ]] && die "Do not run this script as root. It uses sudo where needed."

# ---------------------------------------------------------------------------
# Distro detection
# ---------------------------------------------------------------------------
DISTRO=""
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
        *arch*)   DISTRO="arch" ;;
        *fedora*) DISTRO="fedora" ;;
    esac
fi
[[ -z "$DISTRO" ]] && die "Unsupported distro. This script supports Arch and Fedora only."
info "Detected distro: $DISTRO"

# ===========================================================================
# Arch Linux
# ===========================================================================
install_arch() {
    local pacman_pkgs=(
        # base tooling
        git stow base-devel curl

        # Hyprland session + ecosystem
        hyprland hypridle hyprlock hyprpicker hyprpolkitagent uwsm
        xdg-desktop-portal-hyprland qt5-wayland qt6-wayland

        # terminal, launcher, bar, file manager
        kitty rofi waybar nautilus

        # audio / brightness / media / network
        pipewire pipewire-pulse wireplumber pavucontrol
        brightnessctl playerctl networkmanager

        # clipboard + screenshot + notifications
        cliphist wl-clipboard swaync libnotify

        # input method
        fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt

        # theming / color generation / misc
        python imagemagick adw-gtk-theme fastfetch jq cava

        # fonts (Adwaita Sans + plain FiraCode; Nerd fonts handled separately)
        adwaita-fonts

        # flatpak (for Zen browser)
        flatpak
    )

    local aur_pkgs=(
        python-pywal16   # provides `wal` (Pywal-16 fork used by the theming scripts)
        awww-git         # animated wallpaper daemon (`awww` / `awww-daemon`)
        hyprshell        # GNOME-style window/workspace switcher
        hyprshot         # screenshot utility
        overskride       # bluetooth GUI (waybar right-click)
        spicetify-cli    # Spotify theming
    )

    info "Installing official-repo packages (pacman)..."
    sudo pacman -Syu --needed --noconfirm "${pacman_pkgs[@]}"

    # Ensure an AUR helper exists
    local helper=""
    if command -v yay >/dev/null;    then helper="yay"
    elif command -v paru >/dev/null; then helper="paru"
    fi
    if [[ -z "$helper" ]]; then
        info "No AUR helper found. Bootstrapping yay..."
        local tmp; tmp="$(mktemp -d)"
        git clone https://aur.archlinux.org/yay.git "$tmp/yay"
        ( cd "$tmp/yay" && makepkg -si --noconfirm )
        rm -rf "$tmp"
        helper="yay"
    fi

    info "Installing AUR packages ($helper)..."
    "$helper" -S --needed --noconfirm "${aur_pkgs[@]}"
}

# ===========================================================================
# Fedora
# ===========================================================================
install_fedora() {
    # Most of the Hyprland ecosystem lives in the solopasha/hyprland COPR.
    info "Enabling COPR repositories..."
    sudo dnf install -y 'dnf-command(copr)'
    sudo dnf copr enable -y solopasha/hyprland

    local dnf_pkgs=(
        # base tooling
        git stow curl @development-tools

        # Hyprland session + ecosystem (mostly from COPR)
        hyprland hypridle hyprlock hyprpicker hyprpolkitagent uwsm
        xdg-desktop-portal-hyprland qt5-qtwayland qt6-qtwayland

        # terminal, launcher, bar, file manager
        kitty rofi waybar nautilus

        # audio / brightness / media / network
        pipewire pipewire-pulseaudio wireplumber pavucontrol
        brightnessctl playerctl NetworkManager

        # clipboard + screenshot + notifications
        cliphist wl-clipboard SwayNotificationCenter libnotify hyprshot

        # input method
        fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt

        # theming / color generation / misc
        python3 python3-pip pipx ImageMagick adw-gtk3-theme fastfetch jq cava

        # Build deps for awww / hyprshell (Rust toolchain comes from rustup)
        gcc pkgconf-pkg-config
        gtk4-devel gtk4-layer-shell-devel wayland-devel libxkbcommon-devel lz4-devel

        # fonts (Adwaita Sans family; Nerd fonts handled separately)
        adwaita-sans-fonts

        # flatpak (for Zen browser + overskride)
        flatpak
    )

    # COPR packages (hyprland & friends) are built against a fully-updated
    # base, so install often fails with soname/private-API mismatches on a
    # system that hasn't been upgraded yet. Refresh + upgrade first, mirroring
    # the `pacman -Syu` the Arch path does.
    info "Upgrading the base system first (required for the COPR packages)..."
    sudo dnf upgrade --refresh -y || warn "dnf upgrade had issues — continuing, but COPR deps may fail"

    info "Installing packages (dnf)..."
    # Fail loud: a broken COPR dependency must NOT be silently skipped (that would
    # leave Hyprland half-installed). Abort with an actionable hint instead.
    sudo dnf install -y "${dnf_pkgs[@]}" || die \
"dnf install failed. If this is a dependency error on a COPR package (e.g.
   aquamarine or hyprland-qt-support needing a newer system library), the
   solopasha/hyprland COPR is temporarily out of sync with your Fedora release.
   Wait for a COPR rebuild (usually a day or two) and re-run ./setup.sh."

    # --- Foreign packages with no Fedora package -------------------------
    # pywal16 -> pipx (provides `wal`)
    if ! command -v wal >/dev/null; then
        info "Installing pywal16 via pipx..."
        pipx install pywal16 || MANUAL_NOTES+=("pywal16: 'pipx install pywal16' failed — install manually for the 'wal' command")
        pipx ensurepath >/dev/null 2>&1 || true
    fi

    # awww (wallpaper daemon) and hyprshell are not packaged for Fedora —
    # build them from source with cargo. --root ~/.local drops the binaries
    # into ~/.local/bin, which .bashrc already puts on PATH.
    ensure_rustup
    build_cargo "awww" "cargo install --root $HOME/.local --git https://codeberg.org/LGFae/awww"
    build_cargo "hyprshell" "cargo install --root $HOME/.local hyprshell"
}

# Install/refresh a Rust toolchain via rustup so the cargo builds get a
# current rustc (hyprshell's MSRV outpaces Fedora's packaged rust).
ensure_rustup() {
    if ! command -v rustup >/dev/null && [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
        info "Installing rustup (stable toolchain)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
            | sh -s -- -y --default-toolchain stable --no-modify-path \
            || { MANUAL_NOTES+=("rustup: install failed — see https://rustup.rs, then build awww/hyprshell with cargo"); return; }
    fi
    # Make cargo/rustc available to this script without a new shell.
    [[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
    rustup update stable >/dev/null 2>&1 || true
}

# Build a Rust package with cargo, recording a manual note if it fails
# (e.g. the system rustc is older than the package's MSRV).
build_cargo() {
    local name="$1" cmd="$2"
    if command -v "$name" >/dev/null; then
        info "$name already installed — skipping cargo build."
        return
    fi
    info "Building $name from source with cargo..."
    if ! $cmd; then
        MANUAL_NOTES+=("$name: cargo build failed — likely the system Rust is older than the package's MSRV. Install a newer toolchain via rustup and re-run: $cmd")
    fi
}

# ===========================================================================
# Cross-distro: Nerd Fonts
# ===========================================================================
# The configs reference 'FiraCode Nerd Font' (kitty), 'CodeNewRoman Nerd Font
# Propo' (waybar) and Nerd Font symbols. These aren't cleanly packaged on
# either distro, so install them straight from the ryanoasis/nerd-fonts release.
install_nerd_fonts() {
    local font_dir="$HOME/.local/share/fonts"
    local base="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"
    local fonts=(FiraCode CodeNewRoman NerdFontsSymbolsOnly)

    mkdir -p "$font_dir"
    local need=0
    fc-list 2>/dev/null | grep -qi "FiraCode Nerd Font"     || need=1
    fc-list 2>/dev/null | grep -qi "CodeNewRoman Nerd Font" || need=1
    if [[ "$need" -eq 0 ]]; then
        info "Nerd Fonts already present — skipping."
        return
    fi

    info "Installing Nerd Fonts (FiraCode, CodeNewRoman, Symbols)..."
    local tmp; tmp="$(mktemp -d)"
    for f in "${fonts[@]}"; do
        if curl -fsSL "$base/$f.tar.xz" -o "$tmp/$f.tar.xz"; then
            tar -xf "$tmp/$f.tar.xz" -C "$font_dir"
        else
            warn "Could not download Nerd Font: $f"
            MANUAL_NOTES+=("$f Nerd Font: download manually from github.com/ryanoasis/nerd-fonts")
        fi
    done
    rm -rf "$tmp"
    fc-cache -f "$font_dir" >/dev/null 2>&1 || true
}

# ===========================================================================
# Cross-distro: Flatpak apps
# ===========================================================================
install_flatpaks() {
    info "Setting up Flatpak (Flathub)..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    local apps=( app.zen_browser.zen )                 # default browser (hyprland.lua)
    # On Fedora, overskride isn't packaged — use the Flatpak.
    [[ "$DISTRO" == "fedora" ]] && apps+=( io.github.kaii_lb.Overskride )

    for app in "${apps[@]}"; do
        flatpak install -y --noninteractive flathub "$app" || warn "Could not install flatpak: $app"
    done
}

# ===========================================================================
# Cross-distro: spicetify (Fedora has no package; use the official installer)
# ===========================================================================
install_spicetify_fedora() {
    command -v spicetify >/dev/null && return
    info "Installing spicetify-cli via the official installer..."
    curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh \
        || MANUAL_NOTES+=("spicetify-cli: install from https://spicetify.app")
}

# ===========================================================================
# Cross-distro: nvm (referenced in .bashrc, lives in ~/.config/nvm)
# ===========================================================================
install_nvm() {
    [[ -s "$HOME/.config/nvm/nvm.sh" ]] && return
    info "Installing nvm into ~/.config/nvm..."
    export NVM_DIR="$HOME/.config/nvm"
    PROFILE=/dev/null bash -c \
        'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash' \
        || warn "nvm install failed (curl/network?). Install manually if you need node."
}

# ---------------------------------------------------------------------------
# Run installation
# ---------------------------------------------------------------------------
case "$DISTRO" in
    arch)   install_arch ;;
    fedora) install_fedora; install_spicetify_fedora ;;
esac

install_nerd_fonts
install_flatpaks
install_nvm

# ---------------------------------------------------------------------------
# Enable services
# ---------------------------------------------------------------------------
info "Enabling system + user services..."
sudo systemctl enable --now NetworkManager.service || warn "Could not enable NetworkManager"
systemctl --user enable --now hyprpolkitagent.service 2>/dev/null \
    || warn "hyprpolkitagent user service not enabled (run inside a graphical session)"

# ---------------------------------------------------------------------------
# Stow the dotfiles
# ---------------------------------------------------------------------------
if [[ "$STOW" -eq 1 ]]; then
    info "Symlinking dotfiles into \$HOME with stow..."
    cd "$DOTFILES_DIR"
    stow --target="$HOME" --restow . \
        || die "stow failed — resolve conflicts (back up clashing files) and re-run 'stow .'"
else
    info "Skipping stow (--no-stow). Run 'stow .' from $DOTFILES_DIR when ready."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
info "Setup complete!"

if [[ "${#MANUAL_NOTES[@]}" -gt 0 ]]; then
    warn "The following need manual attention on $DISTRO:"
    for note in "${MANUAL_NOTES[@]}"; do
        printf '   - %s\n' "$note"
    done
fi

cat <<'EOF'

Next steps:
  * Log out and start Hyprland (via uwsm, e.g. `uwsm start hyprland`).
  * Generate an initial pywal theme:    wal -i ~/wallpapers/<your-wallpaper>
  * Set a wallpaper:                     awww img ~/wallpapers/pywallpaper.jpg
  * For Spotify theming, run:            spicetify backup apply
  * Restart your shell to load nvm and the new PATH entries.

EOF
