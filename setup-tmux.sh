#!/bin/sh
# shelltoolbox tmux installer — Debian 13 (trixie) only.
#
# Automates these steps:
#   1. Install apt dependencies (tmux, and git which TPM needs)
#   2. Install TPM (Tmux Plugin Manager) to ~/.tmux/plugins/tpm
#   3. Copy tmux.conf to the canonical dir ~/.local/share/shelltoolbox
#   4. Symlink it to ~/.config/tmux/tmux.conf (backing up anything in the way)
#
# Idempotent: every step checks state before acting, so re-running is safe.

set -eu

SCRIPT_DIR=$(unset CDPATH && cd -- "$(dirname -- "$0")" && pwd -P)
SHELLTOOLBOXDIR="$HOME/.local/share/shelltoolbox"
DEPENDENCIES="git tmux"
TPM_URL="https://github.com/tmux-plugins/tpm"
TPM_DIR="$HOME/.tmux/plugins/tpm"

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

install_tpm() {
	# Test for the file tmux.conf's `run` line executes, not just the
	# directory — a previously interrupted clone can leave one behind.
	if [ -f "$TPM_DIR/tpm" ]; then
		return 0
	fi

	print_colored "$YELLOW" "Installing TPM (Tmux Plugin Manager)..."
	mkdir -p "$(dirname -- "$TPM_DIR")"
	if ! git clone "$TPM_URL" "$TPM_DIR"; then
		# git leaves a partial clone behind on failure; remove it so
		# re-running this script retries from a clean slate.
		rm -rf "$TPM_DIR"
		fail "Failed to clone TPM."
	fi
	print_colored "$GREEN" "TPM installed to $TPM_DIR."
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
	print_colored "$YELLOW" "Installing tmux config to $SHELLTOOLBOXDIR..."
	mkdir -p "$SHELLTOOLBOXDIR"

	for config_file in tmux.conf setup-tmux.sh; do
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
	if [ -f "$SHELLTOOLBOXDIR/setup-tmux.sh" ]; then
		chmod +x "$SHELLTOOLBOXDIR/setup-tmux.sh"
	fi

	if [ ! -e "$SHELLTOOLBOXDIR/tmux.conf" ]; then
		fail "tmux.conf was not found in $SCRIPT_DIR."
	fi
	link_file "$SHELLTOOLBOXDIR/tmux.conf" "$HOME/.config/tmux/tmux.conf"

	# tmux only reads the XDG config when ~/.tmux.conf is absent, so a
	# file there would silently shadow the config we just linked.
	if [ -e "$HOME/.tmux.conf" ] || [ -L "$HOME/.tmux.conf" ]; then
		# shellcheck disable=SC2088 # paths in this message are display text
		print_colored "$YELLOW" "~/.tmux.conf exists and takes precedence over ~/.config/tmux/tmux.conf; remove or rename it."
	fi
}

check_environment
install_dependencies
install_tpm
install_configs

print_colored "$GREEN" "tmux setup complete. Start a session with 'tmux', then press Ctrl+Space followed by I to install the plugins."