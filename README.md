# Lunear01's Hyprland Dotfiles

This directory contains all dotfiles for my Arch + Hyprland Setup

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

First, check out the dotfiles repo in your $HOME directory using git

```
$ git clone https://github.com/Lunear01/hyprland-dotfiles.git
$ cd dotfiles
```

then use GNU stow to create symlinks

```
$ stow .
```
