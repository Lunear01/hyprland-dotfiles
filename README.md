# Lunear01's Hyprland Dotfiles

This directory contains all dotfiles for my Hyprland setup. Supported distros:
**Arch** (pacman + AUR) and **Fedora** (dnf + the `solopasha/hyprland` COPR).


## Pywal-16
- All colors generatations its related scripts are configured to use Pywal-16 for color generation.

## Preview
![Desktop Preview](./assets/desktop.png)
![Rofi](./assets/rofi.png)
![Rofi-Wallpaper](./assets/wallpaper.png)
![Windows](./assets/windows.png)
![Spicetify](./assets/spicetify.png)

## Requirements

Ensure you have the following installed on your system

### Git

```
pacman -S git
```

### Stow

```
pacman -S stow
```

## Installation

First, check out the dotfiles repo in your `$HOME` directory using git

```
$ git clone https://github.com/Lunear01/hyprland-dotfiles.git
$ cd dotfiles
```

### Automated (recommended)

`setup.sh` detects your distro, installs every dependency (packages, AUR/COPR
builds, Nerd Fonts, Flatpaks, nvm), enables the needed services, and symlinks
the configs with stow:

```
$ ./setup.sh            # install everything + stow
$ ./setup.sh --no-stow  # only install packages, skip stowing
```

> On Fedora the Hyprland packages come from the `solopasha/hyprland` COPR, which
> expects a fully-updated base — the script runs `dnf upgrade` first. If a COPR
> dependency is momentarily out of sync you may need to re-run the script later.

### Manual stow only

If the dependencies are already installed, just create the symlinks. A
`.stow-local-ignore` keeps repo-only files (`setup.sh`, `assets/`, `.git`, …)
out of `$HOME`, so only `.bashrc` and `.config` are linked:

```
$ stow .
```
