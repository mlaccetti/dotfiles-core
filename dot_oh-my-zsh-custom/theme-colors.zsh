# theme-colors.zsh
#
# Shell-side glue for the Anthropic-derived 16-color ANSI palette.
# oh-my-zsh auto-sources every *.zsh file under $ZSH_CUSTOM/, so this file
# needs no .zshrc edit to take effect.
#
# The single source of truth for the palette is the terminal profile itself
# (iTerm2 Dynamic Profile / .itermcolors, see ../iterm2/). Everything below
# reads the terminal's 16 ANSI slots by name/number rather than hardcoding
# hex, so changing the palette in one place (the iTerm2 profile) and
# reloading the terminal moves bat, zsh-syntax-highlighting, and the prompt
# (see prompt.zsh) together.
#
# ANSI slot reference (for humans reading this file):
#   0 black  1 red      2 green   3 yellow
#   4 blue   5 magenta  6 cyan    7 white
#   8 br-black(gray) 9 br-red 10 br-green 11 br-yellow
#   12 br-blue 13 br-magenta 14 br-cyan 15 br-white

# --- bat -----------------------------------------------------------------
# "ansi" tells bat to emit plain ANSI SGR codes for syntax highlighting
# instead of its own fixed-hex themes, so bat's colors are whatever the
# terminal's 16-color palette says they are.
export BAT_THEME="ansi"

# --- zsh-syntax-highlighting ----------------------------------------------
# Guard: only configure the highlighter if the plugin is actually loaded,
# so this file is a no-op (not an error) in a shell that doesn't have it.
if (( ${+ZSH_HIGHLIGHT_VERSION} )) || (( ${+functions[_zsh_highlight]} )); then
  # `main` is the default highlighter (commands, strings, etc). `brackets`
  # is OFF by default upstream; enabling it here turns on nested
  # bracket/brace/paren coloring and matching-bracket-under-cursor
  # highlighting, per the user's explicit request.
  ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

  typeset -gA ZSH_HIGHLIGHT_STYLES

  # Bracket nesting depth 1-5, cycling through visually distinct hues that
  # are chosen to stay distinguishable from each other and from the
  # prompt's own colors (see prompt.zsh's mapping table). Numeric ANSI
  # codes are used so bright (8-15) slots are reachable, not just the
  # base 8 color names.
  ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=12'   # br-blue
  ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=11'   # br-yellow
  ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=14'   # br-cyan
  ZSH_HIGHLIGHT_STYLES[bracket-level-4]='fg=13'   # br-magenta
  ZSH_HIGHLIGHT_STYLES[bracket-level-5]='fg=10'   # br-green

  # Unmatched/invalid bracket: bright red, unmistakably an error color.
  ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=9,bold'  # br-red

  # Cursor sitting on a bracket highlights its matching partner: bright
  # white on the near-background black swatch (slot 0), giving a clear
  # "selection" look distinct from every nesting-level color above.
  ZSH_HIGHLIGHT_STYLES[cursor-matchingbracket]='fg=15,bg=0,bold'
fi
