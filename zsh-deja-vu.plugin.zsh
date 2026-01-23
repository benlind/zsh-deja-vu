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

##
# _zsh_deja_vu_get_history_for_dir: Internal helper function that filters
# history entries for a specific directory.
#
# Args:
#   $1 - target_dir: The absolute path of the directory to filter for
#
# Returns:
#   Commands that were run in the specified directory (without the path prefix)
#
# How it works:
#   - History entries are stored in format "/path/to/dir:command"
#   - This function searches for lines starting with the target directory
#   - Returns just the command part, stripping the directory prefix
##
_zsh_deja_vu_get_history_for_dir() {
    local target_dir="$1"
    local prefix="${target_dir}:"

    # Use awk to efficiently scan the history file for matching entries.
    # Pattern matching: lines starting with the target directory path + ":"
    # Output: strips the directory prefix, leaving only the command
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
# Opens an interactive fuzzy finder (fzf) showing commands that were run
# in the *current directory only*. The selected command is placed into
# the command line buffer for editing or execution.
#
# This function is designed to work as a ZLE widget, so it can be bound
# to keyboard shortcuts (default: Ctrl+F).
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

    # Fetch all commands that were run in the current directory
    local history_for_dir
    history_for_dir=$(_zsh_deja_vu_get_history_for_dir "$target_dir")

    # If no history exists for this directory, notify the user and exit
    if [[ -z "$history_for_dir" ]]; then
        # Check if we're in a ZLE widget context (called via keybinding)
        if [[ -n "$WIDGET" ]]; then
            zle -R "zsh-deja-vu: No history for ."
        else
            printf "%s\n" "zsh-deja-vu: No history for ."
        fi
        return 0
    fi

    # Open fzf with the filtered history
    # --tac: reverses the list so most recent commands appear first
    # --query: pre-fills search with current command line buffer (if in ZLE)
    # The prompt shows the current directory name for context
    local selected_command
    local dir_name
    dir_name=${PWD##*/}  # Extract just the directory name (not full path)

    # Build fzf command with optional query parameter
    local fzf_query=""
    if [[ -n "$WIDGET" ]]; then
        fzf_query="$LBUFFER"
    fi

    selected_command=$(
        printf "%s\n" "$history_for_dir" | fzf --tac \
            --height ~40% \
            --prompt="History for ./$dir_name> " \
            --query="$fzf_query"
    )

    # If a command was selected (user didn't cancel with Esc), update the
    # command line buffer. Handle differently based on whether we're in ZLE.
    if [[ -n "$selected_command" ]]; then
        if [[ -n "$WIDGET" ]]; then
            # Called via keybinding: update buffer and redisplay
            LBUFFER=$selected_command
            zle redisplay
        else
            # Called as regular command: push to buffer for next prompt
            print -z "$selected_command"
        fi
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
