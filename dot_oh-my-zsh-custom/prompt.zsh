# prompt.zsh — Anthropic-palette-driven agnoster prompt (recolor only).
#
# This is a straight recolor of the original prompt: same two-line layout,
# same glyphs (⠠⠵ / ○ / ✔ / ✘✘✘), same git-dirty logic. The only change is
# that every hardcoded xterm-256 color index below has been remapped onto
# one of the terminal's 16 ANSI slots (indices 0-15), which the terminal
# profile defines to match the shared palette. See theme-colors.zsh in this
# same directory for the palette-to-tool mapping this all derives from;
# change the palette in the iTerm2 profile and this prompt moves with it.

# removes user@hostname from agnoster prompt
prompt_context() {
  if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
    prompt_segment black default "%(!.%{%F{yellow}%}.)"
  fi
}

function virtualenv_info {
    [ $VIRTUAL_ENV ] && echo '('`basename $VIRTUAL_ENV`') '
}

function prompt_char {
    git branch >/dev/null 2>/dev/null && echo '⠠⠵' && return
    echo '○'
}

function box_name {
    [ -f ~/.box-name ] && cat ~/.box-name || echo ${SHORT_HOST:-$HOST}
}

PROMPT="╭─%{$FG[010]%}%n%{$reset_color%} %{$FG[008]%}at%{$reset_color%} %{$FG[004]%}$(box_name)%{$reset_color%} %{$FG[008]%}in%{$reset_color%} %{$terminfo[bold]$FG[011]%}%~%{$reset_color%}\$(git_prompt_info) %*
╰─\$(virtualenv_info)\$(prompt_char) "

ZSH_THEME_GIT_PROMPT_PREFIX=" %{$FG[008]%}on%{$reset_color%} %{$FG[015]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$FG[009]%}✘✘✘"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$FG[010]%}✔"
