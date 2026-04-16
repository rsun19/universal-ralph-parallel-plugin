#!/usr/bin/env bash
# Ralph Wiggum Installer
# Makes scripts executable and optionally adds ralph to your PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

print_banner() {
  cat << 'BANNER'
  ╔══════════════════════════════════════════════╗
  ║  Ralph Wiggum - Universal AI Agent Teams     ║
  ║  Installer                                   ║
  ╚══════════════════════════════════════════════╝
BANNER
}

usage() {
  cat << EOF
Usage: ./install.sh [options]

Options:
  --link               Symlink ralph to /usr/local/bin (requires sudo)
  --prefix <path>      Copy Ralph into <path> (e.g. ~/.local, /opt/ralph)
                       then symlinks <path>/bin/ralph to /usr/local/bin
  -h, --help           Show this help

Install methods:
  ./install.sh                 # Clone/extract: make scripts executable
  ./install.sh --link          # Clone/extract: also add to PATH via symlink
  ./install.sh --prefix ~/.local   # Binary/tarball: install to ~/.local/
EOF
}

check_dependencies() {
  local missing=()

  command -v bash >/dev/null 2>&1 || missing+=("bash")
  command -v jq >/dev/null 2>&1 || missing+=("jq")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required dependencies: ${missing[*]}"
    echo ""
    echo "Install them:"
    if [[ "$(uname)" == "Darwin" ]]; then
      echo "  brew install ${missing[*]}"
    else
      echo "  sudo apt-get install ${missing[*]}"
    fi
    exit 1
  fi

  echo "All dependencies satisfied."
}

set_executable() {
  local base="$1"
  chmod +x "${base}/bin/ralph"
  chmod +x "${base}/bin/ralph-interactive.sh"
  chmod +x "${base}/adapters/claude-code/hooks/"*.sh 2>/dev/null || true
  chmod +x "${base}/adapters/claude-code/ralph-claude-teams.sh" 2>/dev/null || true
  chmod +x "${base}/adapters/claude-code/scripts/"*.sh 2>/dev/null || true
}

make_executable() {
  echo "Making scripts executable..."
  set_executable "$SCRIPT_DIR"
  echo "Done."
}

symlink_to_path() {
  local link_path="/usr/local/bin/ralph"

  if [[ -L "$link_path" ]] || [[ -f "$link_path" ]]; then
    echo "Removing existing $link_path"
    sudo rm -f "$link_path"
  fi

  echo "Creating symlink: $link_path -> ${SCRIPT_DIR}/bin/ralph"
  sudo ln -s "${SCRIPT_DIR}/bin/ralph" "$link_path"
  echo "Done. You can now run 'ralph' from anywhere."
}

install_to_prefix() {
  local prefix="$1"
  local dest="${prefix}/share/ralph-wiggum"

  echo "Installing Ralph to ${dest}..."
  mkdir -p "$dest"
  mkdir -p "${prefix}/bin"

  cp -R "${SCRIPT_DIR}/lib" "$dest/"
  cp -R "${SCRIPT_DIR}/bin" "$dest/"
  cp -R "${SCRIPT_DIR}/adapters" "$dest/"
  cp -R "${SCRIPT_DIR}/templates" "$dest/"
  cp -R "${SCRIPT_DIR}/docs" "$dest/" 2>/dev/null || true
  cp "${SCRIPT_DIR}/ralph.config.example.json" "$dest/" 2>/dev/null || true
  cp "${SCRIPT_DIR}/README.md" "$dest/" 2>/dev/null || true

  set_executable "$dest"

  # Create a wrapper script (not a symlink) so RALPH_ROOT is baked in
  cat > "${prefix}/bin/ralph" << WRAPPER
#!/usr/bin/env bash
export RALPH_ROOT="${dest}"
exec "\${RALPH_ROOT}/bin/ralph" "\$@"
WRAPPER
  chmod +x "${prefix}/bin/ralph"
  echo "Installed to ${dest}"
  echo "Wrapper created at ${prefix}/bin/ralph"

  # If prefix/bin isn't in PATH, offer a symlink to /usr/local/bin
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "${prefix}/bin"; then
    echo ""
    echo "  ${prefix}/bin is not in your PATH."
    echo "  Add it to your shell profile:"
    echo "    export PATH=\"${prefix}/bin:\$PATH\""
    echo ""
    echo "  Or symlink to /usr/local/bin:"
    echo "    sudo ln -sf \"${prefix}/bin/ralph\" /usr/local/bin/ralph"
  fi
}

main() {
  local do_link=false
  local prefix=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --link) do_link=true; shift ;;
      --prefix)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: --prefix requires a path argument"; usage; exit 1
        fi
        prefix="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  print_banner
  check_dependencies

  if [[ -n "$prefix" ]]; then
    install_to_prefix "$prefix"
  else
    make_executable

    if [[ "$do_link" == "true" ]]; then
      symlink_to_path
    fi

    echo ""
    if [[ "$do_link" == "false" ]]; then
      echo "Scripts are ready. To add 'ralph' to your PATH:"
      echo "  ./install.sh --link"
      echo ""
      echo "Or add this to your shell profile:"
      echo "  export PATH=\"${SCRIPT_DIR}/bin:\$PATH\""
    fi
  fi

  echo ""
  echo "Get started:"
  echo "  ralph init"
}

main "$@"
