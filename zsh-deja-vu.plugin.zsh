# zsh-deja-vu.plugin.zsh
#
# "That feeling you've run this command *here* before?"
#
# Logs Zsh command history per directory and provides `djvu` (static)
# and `djvi` (interactive) to query it.

# --- Configuration ---

# Set the location of the directory-specific history file.
# Uses $ZDOTDIR if set (common for zsh configs), otherwise $HOME.
: "${ZSH_DEJA_VU_HISTORY_FILE:=${ZDOTDIR:-$HOME}/.zsh_deja_vu_history}"

# --- History Logging ---

autoload -U add-zsh-hook

# Runs *before* a command is executed
_zsh_deja_vu_preexec() {
    local cmd="$1"

    # Don't log empty commands
    if [[ -z "$cmd" ]]; then
        return
    fi

    # Don't log our own plugin's commands (prevents feedback loop)
    case "$cmd" in
        (djvu*|djvi*) return 0 ;;
    esac

    # Log in format: /full/path/to/dir:<command>
    print -r -- "$(pwd):$cmd" >> "$ZSH_DEJA_VU_HISTORY_FILE"
}

# Register the hook
add-zsh-hook preexec _zsh_deja_vu_preexec

# --- Query Functions ---

# Shared helper to get filtered history for a directory
_zsh_deja_vu_get_history_for_dir() {
    local target_dir="$1"
    local prefix="${target_dir}:"

    # Use awk to find and print matching lines, stripping the prefix
    awk -v pfx="$prefix" '
        $0 ~ "^" pfx {
            print substr($0, length(pfx) + 1)
        }
    ' "$ZSH_DEJA_VU_HISTORY_FILE"
}

##
# djvu: (Déjà vu) Shows command history for the current or a specified directory.
#
# Usage:
#   djvu        # Shows history for the *current* directory
#   djvu <path> # Shows history for the *specified* path
##
djvu() {
    if [[ ! -f "$ZSH_DEJA_VU_HISTORY_FILE" ]]; then
        printf "%s\n" "zsh-deja-vu: No history logged yet."
        printf "%s\n" "Run a few commands to populate $ZSH_DEJA_VU_HISTORY_FILE"
        return 1
    fi

    local target_dir
    local dir_label

    if [[ -n "$1" ]]; then
        # User provided a path.
        if [[ ! -d "$1" ]]; then
             printf "djvu: error: directory not found: %s\n" "$1"
             return 1
        fi
        # ":A" is Zsh magic to resolve to an absolute, real path
        target_dir="${1:A}"
        dir_label="$1"
    else
        # No path provided, use current directory.
        target_dir="$(pwd)"
        dir_label="."
    fi

    local output
    output=$(_zsh_deja_vu_get_history_for_dir "$target_dir")

    if [[ -z "$output" ]]; then
        printf "djvu: No history found for: %s\n" "$target_dir"
    else
        printf "--- Déjà Vu for %s (%s) ---\n" "$dir_label" "$target_dir"
        # Use 'printf' to safely print the output variable
        printf "%s\n" "$output" | nl -b a -w 6
    fi
}

##
# djvi: (Déjà Vu Interactive)
#
# Searches the command history for the *current directory* with fzf
# and places the selected command into the command line buffer.
##
djvi() {
    if ! command -v fzf &>/dev/null; then
        printf "%s\n" "zsh-deja-vu: Error: fzf (fuzzy finder) is not installed."
        printf "%s\n" "Please install fzf to use the 'djvi' command."
        return 1
    fi

    if [[ ! -f "$ZSH_DEJA_VU_HISTORY_FILE" ]]; then
        printf "%s\n" "zsh-deja-vu: No history logged yet."
        return 1
    fi

    local target_dir
    target_dir="$(pwd)"

    # Get history for the current directory
    local history_for_dir
    history_for_dir=$(_zsh_deja_vu_get_history_for_dir "$target_dir")

    if [[ -z "$history_for_dir" ]]; then
        zle -R "zsh-deja-vu: No history for ."
        return 0
    fi

    # Use fzf to select a command and populate the buffer.
    local selected_command
    local dir_name
    dir_name=${PWD##*/}
    selected_command=$(
        printf "%s\n" "$history_for_dir" | fzf --tac \
            --height ~40% \
            --prompt="History for ./$dir_name> " \
            --query="$LBUFFER"
    )

    # If a command was selected, update the buffer and redraw the line.
    if [[ -n "$selected_command" ]]; then
        LBUFFER=$selected_command
        zle redisplay
    fi
}

# --- ZLE & Keybinding Setup ---

# Register `djvi` as a Zsh Line Editor (zle) widget
zle -N djvi-widget djvi

# Check if the widget is already bound to a key.
# If not, set our default `Ctrl+F`.
# Users can override this in their .zshrc if they want a different key.
if ! bindkey -L | grep -q "djvi-widget"; then
    bindkey '^F' djvi-widget
fi
