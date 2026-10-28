#!/bin/sh
# shelltoolbox installer — Debian 13 (trixie) only.
#
# Automates these steps:
#   1. Install apt dependencies
#   2. Install Starship to ~/.local/bin
#   3. Install the CaskaydiaMono Nerd Font to ~/.local/share/fonts
#   4. Copy configs to the canonical dir ~/.local/share/shelltoolbox
#   5. Symlink them into ~ and ~/.config (backing up anything in the way)
#   6. Point Ptyxis / GNOME Terminal at the Nerd Font via gsettings
#
# Idempotent: every step checks state before acting, so re-running is safe.

set -eu

SCRIPT_DIR=$(unset CDPATH && cd -- "$(dirname -- "$0")" && pwd -P)
SHELLTOOLBOXDIR="$HOME/.local/share/shelltoolbox"
DEPENDENCIES="bash-completion bat tree multitail fastfetch vim neovim trash-cli fzf zoxide curl fontconfig tar xz-utils"
NERD_FONT_FAMILY="CaskaydiaMono Nerd Font"
NERD_FONT_SIZE=12
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.tar.xz"
STARSHIP_URL="https://starship.rs/install.sh"

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
	RC=$(tput sgr0)
	RED=$(tput setaf 1)
	YELLOW=$(tput setaf 3)
	GREEN=$(tput setaf 2)
else
	RC=
	RED=
	YELLOW=
	GREEN=
fi

print_colored() {
	color=$1
	message=$2
	printf '%s%s%s\n' "$color" "$message" "$RC"
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

fail() {
	print_colored "$RED" "ERROR: $1"
	exit 1
}

sudo_cmd() {
	if command_exists sudo; then
		sudo "$@"
	elif command_exists doas && [ -f /etc/doas.conf ]; then
		doas "$@"
	else
		su -c "$*"
	fi
}

# Debian 13 only: /etc/debian_version reads "13.7" on a current trixie
# point release (or "trixie/sid" on a testing install).
check_environment() {
	if [ ! -r /etc/debian_version ]; then
		fail "This installer supports Debian 13 only; /etc/debian_version was not found."
	fi

	debian_version=$(cat /etc/debian_version)
	case $debian_version in
	13.* | trixie/sid) ;;
	*)
		fail "This installer supports Debian 13 only; found Debian version '$debian_version'."
		;;
	esac

	if ! command_exists apt-get; then
		fail "apt-get was not found; this installer supports Debian 13 only."
	fi
}

# Echo the $DEPENDENCIES packages that are not yet installed,
# space-separated; prints nothing when everything is already present.
missing_dependencies() {
	missing=
	# shellcheck disable=SC2086
	for pkg in $DEPENDENCIES; do
		if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
			missing="$missing $pkg"
		fi
	done
	echo "${missing# }"
}

install_dependencies() {
	missing=$(missing_dependencies)
	if [ -z "$missing" ]; then
		return 0
	fi

	print_colored "$YELLOW" "Installing missing dependencies with apt..."
	sudo_cmd apt-get update
	# shellcheck disable=SC2086
	sudo_cmd apt-get install -y $missing
}

install_starship() {
	if command_exists starship; then
		return 0
	fi

	print_colored "$YELLOW" "Installing Starship..."
	mkdir -p "$HOME/.local/bin"
	starship_installer=$(mktemp)
	if ! curl -fsSL "$STARSHIP_URL" -o "$starship_installer"; then
		rm -f "$starship_installer"
		fail "Failed to download the Starship installer."
	fi
	if ! sh "$starship_installer" -y -b "$HOME/.local/bin"; then
		rm -f "$starship_installer"
		fail "Starship installation failed."
	fi
	rm -f "$starship_installer"
	print_colored "$GREEN" "Starship installed to $HOME/.local/bin."
}

install_nerd_font() {
	if fc-list 2>/dev/null | grep -qi "$NERD_FONT_FAMILY"; then
		return 0
	fi

	print_colored "$YELLOW" "Installing $NERD_FONT_FAMILY..."
	font_temp_dir=$(mktemp -d)
	font_archive="$font_temp_dir/CascadiaMono.tar.xz"
	font_unpack_dir="$font_temp_dir/unpacked"
	font_dir="$HOME/.local/share/fonts/CaskaydiaMonoNerdFont"
	mkdir -p "$font_unpack_dir" "$font_dir"

	if ! curl -fsSL "$NERD_FONT_URL" -o "$font_archive"; then
		rm -rf "$font_temp_dir"
		fail "Failed to download $NERD_FONT_FAMILY."
	fi
	if ! tar -xJf "$font_archive" -C "$font_unpack_dir"; then
		rm -rf "$font_temp_dir"
		fail "Failed to extract $NERD_FONT_FAMILY."
	fi

	# Verify the payload we just unpacked — not the destination dir,
	# which may hold stale files from an earlier failed run.
	if ! find "$font_unpack_dir" -type f -name 'CaskaydiaMonoNerdFont-*.ttf' -print -quit | grep -q .; then
		rm -rf "$font_temp_dir"
		fail "No standard CaskaydiaMono Nerd Font files were found in the archive."
	fi
	find "$font_unpack_dir" -type f -name 'CaskaydiaMonoNerdFont-*.ttf' -exec cp {} "$font_dir"/ \;
	rm -rf "$font_temp_dir"

	fc-cache -f >/dev/null 2>&1
	print_colored "$GREEN" "$NERD_FONT_FAMILY installed."
}

backup_existing() {
	target=$1
	if [ -e "$target" ] || [ -L "$target" ]; then
		backup="$target.bak.$(date +%Y%m%d%H%M%S)"
		mv "$target" "$backup"
		print_colored "$YELLOW" "Backed up $target to $backup"
	fi
}

link_file() {
	source=$1
	target=$2
	target_dir=$(dirname -- "$target")

	mkdir -p "$target_dir"

	if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
		return 0
	fi
	# Anything else in the way — file or foreign symlink — gets a
	# timestamped backup, never a silent delete.
	backup_existing "$target"

	ln -s "$source" "$target"
	print_colored "$GREEN" "Linked $target"
}

install_configs() {
	print_colored "$YELLOW" "Installing configs to $SHELLTOOLBOXDIR..."
	mkdir -p "$SHELLTOOLBOXDIR"
	for config_file in .bashrc starship.toml config.jsonc setup-sh.sh starship-theme; do
		source_file="$SCRIPT_DIR/$config_file"
		target_file="$SHELLTOOLBOXDIR/$config_file"
		# Skip files missing from the checkout, and never copy a file
		# onto itself (cp exits non-zero when source and target share
		# an inode, which kills the script under set -e).
		if [ ! -e "$source_file" ] || [ "$source_file" = "$target_file" ]; then
			continue
		fi
		cp -p "$source_file" "$target_file"
	done
	for executable in setup-sh.sh starship-theme; do
		if [ -f "$SHELLTOOLBOXDIR/$executable" ]; then
			chmod +x "$SHELLTOOLBOXDIR/$executable"
		fi
	done

	link_file "$SHELLTOOLBOXDIR/.bashrc" "$HOME/.bashrc"
	link_file "$SHELLTOOLBOXDIR/starship.toml" "$HOME/.config/starship.toml"
	link_file "$SHELLTOOLBOXDIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
}

configure_terminal_font() {
	if ! command_exists gsettings; then
		print_colored "$YELLOW" "Set your terminal font to '$NERD_FONT_FAMILY' manually."
		return 0
	fi

	terminal_schemas=$(gsettings list-schemas 2>/dev/null || true)
	terminal_configured=0

	if printf '%s\n' "$terminal_schemas" | grep -q '^org.gnome.Ptyxis$'; then
		ptyxis_backup="$SHELLTOOLBOXDIR/terminal-font-ptyxis.backup"
		if [ ! -f "$ptyxis_backup" ]; then
			{
				printf 'use-system-font=%s\n' "$(gsettings get org.gnome.Ptyxis use-system-font)"
				printf 'font-name=%s\n' "$(gsettings get org.gnome.Ptyxis font-name)"
			} >"$ptyxis_backup"
		fi
		gsettings set org.gnome.Ptyxis use-system-font false
		gsettings set org.gnome.Ptyxis font-name "$NERD_FONT_FAMILY $NERD_FONT_SIZE"
		terminal_configured=1
	fi

	if printf '%s\n' "$terminal_schemas" | grep -q '^org.gnome.Terminal.ProfilesList$'; then
		gnome_profile=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
		if [ -n "$gnome_profile" ]; then
			gnome_schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$gnome_profile/"
			gnome_backup="$SHELLTOOLBOXDIR/terminal-font-gnome.backup"
			if [ ! -f "$gnome_backup" ]; then
				{
					printf 'profile=%s\n' "$gnome_profile"
					printf 'use-system-font=%s\n' "$(gsettings get "$gnome_schema" use-system-font)"
					printf 'font=%s\n' "$(gsettings get "$gnome_schema" font)"
				} >"$gnome_backup"
			fi
			gsettings set "$gnome_schema" use-system-font false
			gsettings set "$gnome_schema" font "$NERD_FONT_FAMILY $NERD_FONT_SIZE"
			terminal_configured=1
		fi
	fi

	if [ "$terminal_configured" -eq 1 ]; then
		print_colored "$GREEN" "Configured the terminal to use $NERD_FONT_FAMILY."
	else
		print_colored "$YELLOW" "Set your terminal font to '$NERD_FONT_FAMILY' manually."
	fi
}

check_environment
install_dependencies
install_starship
install_nerd_font
install_configs
configure_terminal_font

print_colored "$GREEN" "Installation complete. Restart your shell or run: exec bash"
