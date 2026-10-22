# ~/.bashrc — Zenith Linux
# El shell por defecto de los usuarios nuevos es fish; esto cubre bash.

[[ $- != *i* ]] && return

export PATH="$HOME/.local/bin:$PATH"

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi

if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons=auto --group-directories-first'
    alias ll='eza -lah --icons=auto --group-directories-first --git'
    alias la='eza -a --icons=auto'
    alias tree='eza --tree --icons=auto'
fi

if command -v bat >/dev/null 2>&1; then
    alias cat='bat --style=plain'
fi

alias grep='grep --color=auto'
alias zenith-update='zenith update'
