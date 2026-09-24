#!/bin/bash
# Seeds ~/.zshrc.local from dot_zshrc_local.example the FIRST time this
# runs on a machine - and never again. If ~/.zshrc.local already exists
# (e.g. Michael's machine, where it's live and holds real overrides), it
# is left completely untouched.
set -uo pipefail

HOME_DIR="${CHEZMOI_HOME_DIR:-$HOME}"
SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"

TARGET="${HOME_DIR}/.zshrc.local"
EXAMPLE="${SOURCE_DIR}/dot_zshrc_local.example"

echo "==> [zshrc.local] Checking for an existing ~/.zshrc.local..."

if [ -e "$TARGET" ]; then
  echo "    ~/.zshrc.local already exists - leaving it exactly as it is."
  exit 0
fi

if [ ! -f "$EXAMPLE" ]; then
  echo "    !! Could not find the starter template at ${EXAMPLE}."
  echo "    !! Creating an empty ~/.zshrc.local instead."
  : > "$TARGET"
  exit 0
fi

cp "$EXAMPLE" "$TARGET"
echo "    Created ${TARGET} from the starter template (dot_zshrc_local.example)."
echo "    Edit it freely - chezmoi will never overwrite it."

exit 0
