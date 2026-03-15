#!/usr/bin/env bash
set -e

echo "🖥️  Applying advanced terminal settings..."

updated_count=0

BASH_START_MARKER="# >>> fedora-advanced-terminal >>>"
BASH_END_MARKER="# <<< fedora-advanced-terminal <<<"
INPUT_START_MARKER="# >>> fedora-advanced-terminal >>>"
INPUT_END_MARKER="# <<< fedora-advanced-terminal <<<"

read -r -d '' BASH_BLOCK << 'EOF' || true
# >>> fedora-advanced-terminal >>>
# Managed by fedora/scripts/22_terminal.sh
case $- in
    *i*) ;;
    *) return ;;
esac

# Long-lived history tuned for multi-session engineering workflows.
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T "
shopt -s histappend cmdhist checkwinsize

__fedora_history_sync() {
    history -a
    history -n
}

if [[ "${PROMPT_COMMAND:-}" != *"__fedora_history_sync"* ]]; then
    PROMPT_COMMAND="__fedora_history_sync${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}"
fi

export PAGER="${PAGER:-less}"
export LESS="${LESS:--FRX --use-color}"

if command -v fzf >/dev/null 2>&1; then
    export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height=45% --layout=reverse --border}"
fi

export CDPATH=".:${HOME}:${HOME}/projects"

if command -v eza >/dev/null 2>&1; then
    alias ls='eza --group-directories-first --icons=auto'
    alias ll='eza -alh --git --group-directories-first --icons=auto'
else
    alias ls='ls --color=auto'
    alias ll='ls -alFh --color=auto'
fi
alias la='ls -A'
alias l='ls -CF'

if command -v batcat >/dev/null 2>&1; then
    alias cat='batcat --paging=never'
elif command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never'
fi

if command -v rg >/dev/null 2>&1; then
    alias grep='rg --smart-case'
fi

if command -v git >/dev/null 2>&1; then
    alias gs='git status -sb'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
fi

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
else
    __fedora_git_branch() {
        local branch
        branch="$(git branch --show-current 2>/dev/null || true)"
        [ -n "$branch" ] && printf " (%s)" "$branch"
    }

    __fedora_prompt_exit() {
        local ec="$?"
        # Use readline markers from command substitution to avoid literal \[ \] output.
        [ "$ec" -ne 0 ] && printf "\001\e[1;31m\002[%s]\001\e[0m\002 " "$ec"
    }

    PS1='$(__fedora_prompt_exit)\[\e[1;34m\]\u@\h\[\e[0m\]:\[\e[1;36m\]\w\[\e[0m\]$(__fedora_git_branch)\n\$ '
fi
# <<< fedora-advanced-terminal <<<
EOF

read -r -d '' INPUT_BLOCK << 'EOF' || true
# >>> fedora-advanced-terminal >>>
set completion-ignore-case on
set show-all-if-ambiguous on
set menu-complete-display-prefix on
set mark-symlinked-directories on
set mark-directories on
set colored-stats on
set visible-stats on
set bell-style none
"\e[A": history-search-backward
"\e[B": history-search-forward
# <<< fedora-advanced-terminal <<<
EOF

ensure_file() {
    local path="$1"
    local owner="$2"

    if [ ! -f "$path" ]; then
        touch "$path"
        chown "$owner":"$owner" "$path"
    fi
}

upsert_managed_block() {
    local file_path="$1"
    local start_marker="$2"
    local end_marker="$3"
    local block_content="$4"
    local escaped_block_content
    local owner="$5"
    local tmp_file
    local action

    ensure_file "$file_path" "$owner"
    tmp_file="$(mktemp)"
    # Escape backslashes before passing through awk -v to preserve literals.
    escaped_block_content="${block_content//\\/\\\\}"

    awk -v start="$start_marker" -v end="$end_marker" -v block="$escaped_block_content" '
        BEGIN {
            in_block = 0
            replaced = 0
        }
        $0 == start {
            if (!replaced) {
                print block
                replaced = 1
            }
            in_block = 1
            next
        }
        in_block && $0 == end {
            in_block = 0
            next
        }
        !in_block {
            print
        }
        END {
            if (!replaced) {
                if (NR > 0) {
                    print ""
                }
                print block
            }
        }
    ' "$file_path" > "$tmp_file"

    if cmp -s "$file_path" "$tmp_file"; then
        action="already present"
    else
        if grep -Fxq "$start_marker" "$file_path" && grep -Fxq "$end_marker" "$file_path"; then
            action="updated"
        else
            action="added"
        fi
        mv "$tmp_file" "$file_path"
        chown "$owner":"$owner" "$file_path"
        updated_count=$((updated_count + 1))
        tmp_file=""
    fi

    [ -n "$tmp_file" ] && rm -f "$tmp_file"
    echo "$action"
}

while IFS=: read -r username _ uid _ _ home _; do
    if [ "$uid" -lt 1000 ] || [ "$username" = "nobody" ] || [ ! -d "$home" ]; then
        continue
    fi

    bashrc="$home/.bashrc"
    inputrc="$home/.inputrc"
    bashrc_action="$(upsert_managed_block "$bashrc" "$BASH_START_MARKER" "$BASH_END_MARKER" "$BASH_BLOCK" "$username")"
    inputrc_action="$(upsert_managed_block "$inputrc" "$INPUT_START_MARKER" "$INPUT_END_MARKER" "$INPUT_BLOCK" "$username")"

    case "$bashrc_action" in
        "added") echo "✅ Added advanced Bash terminal settings for $username" ;;
        "updated") echo "♻️  Updated advanced Bash terminal settings for $username" ;;
        *) echo "ℹ️  Advanced Bash terminal settings already present for $username" ;;
    esac

    case "$inputrc_action" in
        "added") echo "✅ Added advanced Readline settings for $username" ;;
        "updated") echo "♻️  Updated advanced Readline settings for $username" ;;
        *) echo "ℹ️  Advanced Readline settings already present for $username" ;;
    esac
done < /etc/passwd

if [ "$updated_count" -eq 0 ]; then
    echo "ℹ️  No terminal setting updates were needed."
fi
