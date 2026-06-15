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

        # Build deps for the Rust source builds (the toolchain itself comes
        # from rustup, below). awww needs wayland + the wayland-protocols .xml
        # files + lz4; hyprshell needs gtk4 (>=4.18), libadwaita (>=1.8) and
        # gtk4-layer-shell. Missing libadwaita/wayland-protocols headers are the
        # usual cause of a "cargo build failed" on a fresh Fedora.
        gcc pkgconf-pkg-config
        gtk4-devel libadwaita-devel gtk4-layer-shell-devel
        wayland-devel wayland-protocols-devel libxkbcommon-devel lz4-devel

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
    # build them from source with cargo.
    ensure_rustup || warn "rustup unavailable — the source builds will try a system cargo and may fail."
    # awww is a pure binary, so `--root ~/.local` (on PATH via .bashrc) is enough.
    # It's a cargo workspace with two binary packages (awww + awww-daemon), so
    # both must be named explicitly — a bare `--git` install errors out with
    # "multiple packages with binaries found".
    build_cargo awww install --root "$HOME/.local" --git https://codeberg.org/LGFae/awww awww awww-daemon
    # hyprshell needs more than a binary (systemd unit + data dir) — handled below.
    build_hyprshell_fedora
}

# Path to the cargo from the rustup-managed stable toolchain. Resolved by
# ensure_rustup; build_cargo invokes it explicitly so an older system cargo on
# $PATH can never shadow it during the source builds.
RUSTUP_CARGO=""

# Install/refresh a rustup-managed stable toolchain so the cargo source builds
# get a current rustc. hyprshell's MSRV (rustc 1.92+) outpaces the rust Fedora
# ships, so we must not fall back to a stale system cargo.
ensure_rustup() {
    local rustup_bin=""
    if command -v rustup >/dev/null;        then rustup_bin="$(command -v rustup)"
    elif [[ -x "$HOME/.cargo/bin/rustup" ]]; then rustup_bin="$HOME/.cargo/bin/rustup"
    fi

    if [[ -z "$rustup_bin" ]]; then
        info "Installing rustup (stable toolchain)..."
        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
              | sh -s -- -y --default-toolchain stable --profile minimal --no-modify-path; then
            rustup_bin="$HOME/.cargo/bin/rustup"
        else
            MANUAL_NOTES+=("rustup: install failed — see https://rustup.rs, then build awww/hyprshell with cargo")
            return 1
        fi
    fi

    # Make cargo/rustc available to this script without opening a new shell.
    [[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
    "$rustup_bin" toolchain install stable --profile minimal >/dev/null 2>&1 || true
    "$rustup_bin" update stable >/dev/null 2>&1 || true

    # Resolve the stable toolchain's cargo explicitly (not whatever is on $PATH).
    if RUSTUP_CARGO="$("$rustup_bin" which --toolchain stable cargo 2>/dev/null)" \
        && [[ -n "$RUSTUP_CARGO" ]]; then
        info "Using $("$RUSTUP_CARGO" --version 2>/dev/null) for source builds."
    else
        RUSTUP_CARGO="cargo"
        return 1
    fi
}

# Build/install a Rust binary with cargo, recording a manual note if it fails
# (e.g. the toolchain is older than the package's MSRV, or a -devel header is
# missing). Usage: build_cargo <binary-name> <cargo args...>
build_cargo() {
    local name="$1"; shift
    if command -v "$name" >/dev/null; then
        info "$name already installed — skipping cargo build."
        return
    fi
    local cargo="${RUSTUP_CARGO:-cargo}"
    info "Building $name from source with cargo..."
    if ! "$cargo" "$@"; then
        MANUAL_NOTES+=("$name: cargo build failed. Check that a recent rustup toolchain is active (hyprshell needs rustc 1.92+) and the build -devel headers are installed, then retry: $cargo $*")
    fi
}

# Build + install hyprshell on Fedora (no distro package exists).
#
# Unlike awww, hyprshell is a GTK4 app that needs more than a bare binary: a
# systemd *user unit* and a /usr/share/hyprshell *data dir* (its default
# --system-data-dir). `cargo install` would drop ONLY the binary, so
# `systemctl --user enable hyprshell.service` (run from hyprland.lua autostart)
# would fail with "unit not found" and the daemon would have no data dir.
#
# So we replicate upstream's PKGBUILD: build from the published crate (which
# bundles packaging/hyprshell.service + packaging/usr-share.tar), then install
# the binary, unit and data into the SAME system paths the Arch package uses.
# That also lets the stowed systemd drop-in — which points ExecStart at
# /usr/bin/hyprshell — work unchanged on both distros.
build_hyprshell_fedora() {
    if command -v hyprshell >/dev/null && [[ -f /usr/lib/systemd/user/hyprshell.service ]]; then
        info "hyprshell already installed (binary + unit) — skipping."
        return
    fi
    local cargo="${RUSTUP_CARGO:-cargo}"

    # Resolve the latest non-yanked release from the crates.io sparse index
    # (newline-delimited JSON, one object per version in publish order).
    local ver
    ver="$(curl -fsSL https://index.crates.io/hy/pr/hyprshell 2>/dev/null \
        | jq -rs 'map(select(.yanked | not)) | last | .vers' 2>/dev/null)"
    if [[ -z "$ver" || "$ver" == "null" ]]; then
        MANUAL_NOTES+=("hyprshell: could not resolve latest version from crates.io — build manually from github.com/H3rmt/hyprshell")
        return
    fi

    local tmp; tmp="$(mktemp -d)"
    info "Building hyprshell $ver from source (crate)..."
    if ! curl -fsSL "https://static.crates.io/crates/hyprshell/hyprshell-$ver.crate" \
            | tar -xz -C "$tmp"; then
        MANUAL_NOTES+=("hyprshell: failed to download/extract crate $ver — build manually from github.com/H3rmt/hyprshell")
        rm -rf "$tmp"; return
    fi
    local src="$tmp/hyprshell-$ver"
    if ! ( cd "$src" && RUSTUP_TOOLCHAIN=stable "$cargo" build --release --locked ); then
        MANUAL_NOTES+=("hyprshell: cargo build failed (needs rustc 1.92+ and gtk4/libadwaita/gtk4-layer-shell -devel headers). Retry in $src with: $cargo build --release --locked")
        rm -rf "$tmp"; return
    fi

    info "Installing hyprshell into system paths (binary, unit, data dir)..."
    # Mirror the upstream PKGBUILD package() step (system paths == Arch package).
    sudo install -Dm755 "$src/target/release/hyprshell"   /usr/bin/hyprshell
    sudo install -Dm644 "$src/packaging/hyprshell.service" /usr/lib/systemd/user/hyprshell.service
    sudo rm -rf /usr/share/hyprshell
    sudo mkdir -p /usr/share/hyprshell
    sudo tar -xf "$src/packaging/usr-share.tar" -C /usr/share/hyprshell
    rm -rf "$tmp"
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
# Cross-distro: point spicetify at this machine's Spotify install
# ===========================================================================
# config-xpui.ini ships with empty spotify_path/prefs_path: they must be
# absolute and spicetify does NOT expand ~ or $HOME, so they can't be stored
# portably in the repo. Detect and set them for the current user/install here.
configure_spicetify() {
    command -v spicetify >/dev/null || return
    [[ -f "$HOME/.config/spicetify/config-xpui.ini" ]] || return
    info "Configuring spicetify paths for this machine..."

    # prefs file: native install vs Flatpak
    local prefs
    for prefs in \
        "$HOME/.config/spotify/prefs" \
        "$HOME/.var/app/com.spotify.Client/config/spotify/prefs"; do
        [[ -f "$prefs" ]] && { spicetify config prefs_path "$prefs" >/dev/null 2>&1; break; }
    done

    # Spotify install dir: spotify-launcher (Arch), distro package, or Flatpak
    local sp
    for sp in \
        "$HOME/.local/share/spotify-launcher/install/usr/share/spotify" \
        "/opt/spotify" \
        "/usr/share/spotify" \
        "/var/lib/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify" \
        "$HOME/.local/share/flatpak/app/com.spotify.Client/current/active/files/extra/share/spotify"; do
        if [[ -d "$sp" ]]; then
            spicetify config spotify_path "$sp" >/dev/null 2>&1
            return
        fi
    done
    MANUAL_NOTES+=("spicetify: could not auto-detect spotify_path — once Spotify is installed run 'spicetify config spotify_path <dir>' (then 'spicetify backup apply')")
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
    configure_spicetify
    # The stowed systemd drop-in (hyprshell.service.d/override.conf) now points
    # hyprshell at config.json5 — reload so the override is live before the
    # service is first started by the hyprland.lua autostart.
    systemctl --user daemon-reload 2>/dev/null || true
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
