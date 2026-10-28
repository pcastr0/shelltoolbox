#!/bin/sh
# shelltoolbox uninstaller — reverses everything setup-sh.sh did.
#
#   1. Restore the terminal font from the installer's gsettings backups
#   2. Unlink ~/.bashrc, starship.toml, fastfetch config and starship-theme,
#      restoring the .bak.<timestamp> backups the installer made
#   3. Remove ~/.local/share/shelltoolbox (the canonical copies)
#   4. Remove the CaskaydiaMono Nerd Font
#   5. Remove the Starship binary
#   6. Remove the apt dependencies
#
# Idempotent: every step checks state before acting, so re-running is safe.
# Pass -y/--yes to skip the confirmation prompt.

set -eu

SHELLTOOLBOXDIR="$HOME/.local/share/shelltoolbox"
DEPENDENCIES="bash-completion bat tree multitail fastfetch vim neovim trash-cli fzf zoxide curl fontconfig tar xz-utils"
NERD_FONT_FAMILY="CaskaydiaMono Nerd Font"
NERD_FONT_DIR="$HOME/.local/share/fonts/CaskaydiaMonoNerdFont"

if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
	RC=$(tput sgr0)
	YELLOW=$(tput setaf 3)
	GREEN=$(tput setaf 2)
else
	RC=
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

sudo_cmd() {
	if command_exists sudo; then
		sudo "$@"
	elif command_exists doas && [ -f /etc/doas.conf ]; then
		doas "$@"
	else
		su -c "$*"
	fi
}

# The installer backed targets up as "<target>.bak.<timestamp>" next to the
# target itself; the timestamps are fixed-width, so lexical order is age
# order. Move the newest one back over the target.
restore_backup() {
	target=$1
	newest=
	for backup in "$target".bak.*; do
		[ -f "$backup" ] || continue
		# Glob expansion is sorted, and the fixed-width timestamps make
		# alphabetical order chronological — so the last match is newest.
		newest=$backup
	done

	if [ -n "$newest" ]; then
		mv "$newest" "$target"
		print_colored "$GREEN" "Restored $target from $newest"
		return 0
	fi
	return 1
}

# Remove a symlink only if it points into SHELLTOOLBOXDIR — never touch a
# foreign link or a regular file the user put there after installing.
unlink_target() {
	target=$1

	if [ -L "$target" ] && [ "$(readlink "$target")" = "$SHELLTOOLBOXDIR/$(basename -- "$target")" ]; then
		rm "$target"
	elif [ -L "$target" ]; then
		print_colored "$YELLOW" "Leaving foreign symlink $target alone."
		return 0
	else
		return 0
	fi
}

unlink_and_restore() {
	target=$1

	if [ -L "$target" ]; then
		unlink_target "$target"
	fi

	if [ -e "$target" ]; then
		return 0 # a real file is in place; nothing to restore
	fi

	if restore_backup "$target"; then
		return 0
	fi

	# No backup exists (the installer created the link fresh). For ~/.bashrc
	# fall back to Debian's stock skeleton so the user is not left without
	# a shell config.
	if [ "$target" = "$HOME/.bashrc" ] && [ -f /etc/skel/.bashrc ]; then
		cp /etc/skel/.bashrc "$target"
		print_colored "$GREEN" "Restored $target from /etc/skel/.bashrc"
	fi
}

remove_configs() {
	print_colored "$YELLOW" "Unlinking configs and restoring backups..."
	unlink_and_restore "$HOME/.bashrc"
	unlink_and_restore "$HOME/.config/starship.toml"
	unlink_and_restore "$HOME/.config/fastfetch/config.jsonc"
	unlink_and_restore "$HOME/.local/bin/starship-theme"

	# Drop ~/.config/fastfetch if we created it and it is now empty.
	if [ -d "$HOME/.config/fastfetch" ]; then
		rmdir "$HOME/.config/fastfetch" 2>/dev/null || true
	fi
}

# Run BEFORE remove_shelltoolbox_dir: the backups this reads live inside it.
restore_terminal_font() {
	ptyxis_backup="$SHELLTOOLBOXDIR/terminal-font-ptyxis.backup"
	gnome_backup="$SHELLTOOLBOXDIR/terminal-font-gnome.backup"

	command_exists gsettings || return 0

	if [ -f "$ptyxis_backup" ]; then
		gsettings set org.gnome.Ptyxis use-system-font "$(sed -n 's/^use-system-font=//p' "$ptyxis_backup")"
		gsettings set org.gnome.Ptyxis font-name "$(sed -n 's/^font-name=//p' "$ptyxis_backup")"
		print_colored "$GREEN" "Restored Ptyxis font settings."
	fi

	if [ -f "$gnome_backup" ]; then
		gnome_profile=$(sed -n 's/^profile=//p' "$gnome_backup")
		if [ -n "$gnome_profile" ]; then
			gnome_schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$gnome_profile/"
			gsettings set "$gnome_schema" use-system-font "$(sed -n 's/^use-system-font=//p' "$gnome_backup")"
			gsettings set "$gnome_schema" font "$(sed -n 's/^font=//p' "$gnome_backup")"
			print_colored "$GREEN" "Restored GNOME Terminal font settings."
		fi
	fi
}

remove_shelltoolbox_dir() {
	if [ -d "$SHELLTOOLBOXDIR" ]; then
		rm -rf "$SHELLTOOLBOXDIR"
		print_colored "$GREEN" "Removed $SHELLTOOLBOXDIR"
	fi
}

remove_nerd_font() {
	if [ -d "$NERD_FONT_DIR" ]; then
		rm -rf "$NERD_FONT_DIR"
		print_colored "$GREEN" "Removed $NERD_FONT_FAMILY"
		command_exists fc-cache && fc-cache -f >/dev/null 2>&1
	fi
}

remove_starship() {
	if [ -f "$HOME/.local/bin/starship" ]; then
		rm -f "$HOME/.local/bin/starship"
		print_colored "$GREEN" "Removed ~/.local/bin/starship"
	fi
}

# apt is all-or-nothing: one still-needed package (e.g. tar, which dpkg
# depends on) aborts the entire transaction, so nothing gets removed.
# Filter the list down first to packages nothing installed Depends or
# Pre-Depends on — Recommends do not block removal, so they are excluded.
# Deliberately conservative: a package whose only dependents are also
# being removed may still be kept, which is a missed cleanup, never a
# breakage.
removable_dependencies() {
	removable=
	# shellcheck disable=SC2086
	for pkg in $DEPENDENCIES; do
		dependents=$(apt-cache rdepends --installed \
			--no-recommends --no-suggests --no-conflicts \
			--no-breaks --no-replaces --no-enhances "$pkg" 2>/dev/null |
			sed -e '1d' -e '/^Reverse Depends:$/d' -e 's/^[[:space:]]*//' -e '/^$/d')
		if [ -n "$dependents" ]; then
			# >&2: this function's stdout is captured by the caller as
			# the package list, so diagnostics must not go there.
			print_colored "$YELLOW" "Keeping $pkg (needed by: $(printf '%s\n' "$dependents" | tr '\n' ' '))" >&2
		else
			removable="$removable $pkg"
		fi
	done
	echo "${removable# }"
}

remove_dependencies() {
	removable=$(removable_dependencies)
	if [ -z "$removable" ]; then
		print_colored "$YELLOW" "No apt dependencies are safe to remove."
		return 0
	fi
	print_colored "$YELLOW" "Removing apt dependencies: $removable"
	# shellcheck disable=SC2086
	sudo_cmd apt-get remove -y $removable
	print_colored "$GREEN" "Removed the shelltoolbox apt dependencies."
}

confirm() {
	ASSUME_YES=$1
	[ "$ASSUME_YES" -eq 1 ] && return 0

	print_colored "$YELLOW" "This will remove:"
	printf '  %s\n' "$SHELLTOOLBOXDIR" "$NERD_FONT_DIR" "$HOME/.local/bin/starship"
	printf '  the shelltoolbox symlinks in ~, ~/.config and ~/.local/bin\n'
	printf '  the apt packages from the install that nothing installed depends on:\n    %s\n' "$DEPENDENCIES"
	printf 'Run with -y to skip this prompt.\n'
	printf 'Proceed? [y/N] '
	read -r answer
	case $answer in
	y | Y | yes | YES) ;;
	*)
		print_colored "$YELLOW" "Aborted; nothing was changed."
		exit 0
		;;
	esac
}

ASSUME_YES=0
for arg in "$@"; do
	case $arg in
	-y | --yes) ASSUME_YES=1 ;;
	*)
		printf 'Usage: %s [-y|--yes]\n' "$0" >&2
		exit 1
		;;
	esac
done

confirm "$ASSUME_YES"
restore_terminal_font
remove_configs
remove_shelltoolbox_dir
remove_nerd_font
remove_starship
remove_dependencies

print_colored "$GREEN" "Uninstall complete. Restart your shell or run: exec bash"