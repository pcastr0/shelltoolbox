#!/bin/sh -e

RC=$(tput sgr0)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)

LINUXTOOLBOXDIR="$HOME/linuxtoolbox"
GITPATH=$(dirname "$(realpath "$0")")
SUDO_CMD=""

DEPENDENCIES="bash bash-completion tar bat tree multitail fastfetch wget curl unzip
fontconfig trash-cli vim git starship fzf zoxide"

print_colored() {
    printf "%s%s%s\n" "$1" "$2" "$RC"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

die() {
    print_colored "$RED" "$1"
    exit 1
}

check_environment() {
    [ -r /etc/debian_version ] || die "This script supports Debian 13 only."
    case "$(cat /etc/debian_version)" in
        13*) ;;
        *) die "This script supports Debian 13 only (found $(cat /etc/debian_version))." ;;
    esac

    if [ "$(id -u)" -eq 0 ]; then
        SUDO_CMD=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
        sudo -v || die "sudo access is required to run this script."
    else
        die "Run as root or install sudo."
    fi

    [ -w "$GITPATH" ] || die "Can't write to $GITPATH"
}

# setup_directories() {
#     mkdir -p "$LINUXTOOLBOXDIR"
#     rm -rf "$LINUXTOOLBOXDIR/mybash"

#     print_colored "$YELLOW" "Cloning mybash into $LINUXTOOLBOXDIR/mybash"
#     git clone https://github.com/ChrisTitusTech/mybash "$LINUXTOOLBOXDIR/mybash" \
#         || die "Failed to clone mybash repository"
#     print_colored "$GREEN" "Cloned mybash repository"
# }

install_dependencies() {
    print_colored "$YELLOW" "Installing dependencies..."
    $SUDO_CMD apt-get update
    # shellcheck disable=SC2086
    $SUDO_CMD apt-get install -y $DEPENDENCIES

    if ! command_exists nvim; then
        DEPENDENCIES="${DEPENDENCIES} neovim"
    fi

    install_font
}

install_font() {
    FONT_NAME="Caskaydia Nerd Font Mono"
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CascadiaMono.zip"
    FONT_DIR="$HOME/.local/share/fonts/$FONT_NAME"

    if fc-list :family | grep -iq "$FONT_NAME"; then
        printf "Font '%s' is already installed.\n" "$FONT_NAME"
        return
    fi

    printf "Installing font '%s'\n" "$FONT_NAME"
    wget -q --spider "$FONT_URL" || {
        print_colored "$YELLOW" "Font URL not accessible, skipping font install."
        return
    }

    TEMP_DIR=$(mktemp -d)
    wget -q "$FONT_URL" -O "$TEMP_DIR/font.zip"
    unzip -q "$TEMP_DIR/font.zip" -d "$TEMP_DIR"
    mkdir -p "$FONT_DIR"
    mv "$TEMP_DIR"/*.ttf "$FONT_DIR"/
    fc-cache -f
    rm -rf "$TEMP_DIR"
    printf "'%s' installed successfully.\n" "$FONT_NAME"
}

install_starship_and_fzf() {
    if ! command_exists starship; then
        if ! curl -sS https://starship.rs/install.sh | sh; then
            print_colored "$RED" "Something went wrong during starship install!"
            exit 1
        fi
    else
        printf "Starship already installed\n"
    fi

    if ! command_exists fzf; then
        if [ -d "$HOME/.fzf" ]; then
            print_colored "$YELLOW" "FZF directory already exists. Skipping installation."
        else
            git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
            ~/.fzf/install
        fi
    else
        printf "Fzf already installed\n"
    fi
}

install_zoxide() {
    if ! command_exists zoxide; then
        if ! curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
            print_colored "$RED" "Something went wrong during zoxide install!"
            exit 1
        fi
    else
        printf "Zoxide already installed\n"
    fi
}

create_fastfetch_config() {
    USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    CONFIG_DIR="$USER_HOME/.config/fastfetch"
    CONFIG_FILE="$CONFIG_DIR/config.jsonc"
    
    mkdir -p "$CONFIG_DIR"
    [ -e "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
    
    if ! ln -svf "$GITPATH/config.jsonc" "$CONFIG_FILE"; then
        print_colored "$RED" "Failed to create symbolic link for fastfetch config"
        exit 1
    fi
}

link_config() {
    CONFIG_HOME="$HOME/.config"

    # fastfetch
    mkdir -p "$CONFIG_HOME/fastfetch"
    ln -svf "$GITPATH/config.jsonc" "$CONFIG_HOME/fastfetch/config.jsonc" \
        || die "Failed to link fastfetch config"

    # bash + starship
    if [ -e "$HOME/.bashrc" ] && [ ! -L "$HOME/.bashrc" ]; then
        print_colored "$YELLOW" "Backing up existing .bashrc to ~/.bashrc.bak"
        mv "$HOME/.bashrc" "$HOME/.bashrc.bak" || die "Can't back up .bashrc"
    fi

    ln -svf "$GITPATH/.bashrc" "$HOME/.bashrc" \
        && ln -svf "$GITPATH/starship.toml" "$CONFIG_HOME/starship.toml" \
        || die "Failed to create symbolic links"

    if [ ! -f "$HOME/.bash_profile" ]; then
        echo '[ -f ~/.bashrc ] && . ~/.bashrc' > "$HOME/.bash_profile"
        print_colored "$GREEN" "Created ~/.bash_profile"
    fi
}

# Main
check_environment
# setup_directories
install_dependencies
install_starship_and_fzf
install_zoxide
create_fastfetch_config
link_config

print_colored "$GREEN" "Done!"
echo "Restart your shell to see the changes."
