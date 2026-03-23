#!/bin/bash
###############################################################################
# ONTAP S3 Bench - Offline Installer
# All dependencies bundled, no internet required
###############################################################################
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
step()  { echo -e "\n${CYAN}========== $1 ==========${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/ontap-s3-bench"

main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   ONTAP S3 Bench - Offline Installer                ║"
    echo "║   All dependencies bundled, no internet required    ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # --- Check package contents ---
    step "Checking package contents"
    [ -f "$SCRIPT_DIR/ontap_s3_bench.py" ] || error "ontap_s3_bench.py not found"
    [ -f "$SCRIPT_DIR/bin/warp" ]           || error "bin/warp not found"
    [ -d "$SCRIPT_DIR/wheels" ]             || error "wheels/ directory not found"
    info "Package contents OK"

    # --- Find Python 3 ---
    step "Detecting Python 3"
    PYTHON=""
    for cmd in python3 python3.12 python3.11 python3.9 python3.8; do
        if command -v "$cmd" &>/dev/null; then
            PYTHON="$cmd"
            break
        fi
    done
    [ -z "$PYTHON" ] && error "Python 3 not found. Install python3 first: sudo dnf install -y python3"
    PY_VER=$($PYTHON --version 2>&1)
    info "Found: $PY_VER ($PYTHON)"

    # --- Ensure pip is available ---
    step "Checking pip"
    if ! $PYTHON -m pip --version &>/dev/null; then
        info "pip not found, installing via ensurepip..."
        $PYTHON -m ensurepip --upgrade 2>&1 || error "Failed to install pip. Run: sudo dnf install -y python3-pip"
    fi
    info "pip: $($PYTHON -m pip --version 2>&1 | head -1)"

    # --- Install Python dependencies from local wheels ---
    step "Installing Python dependencies (offline)"
    WHEEL_DIR="$SCRIPT_DIR/wheels"
    WHEEL_COUNT=$(ls "$WHEEL_DIR"/*.whl 2>/dev/null | wc -l)
    info "Found $WHEEL_COUNT wheel files"

    # Detect Python version to choose compatible package versions
    PY_MINOR=$($PYTHON -c "import sys;print(sys.version_info.minor)")
    if [ "$PY_MINOR" -le 7 ]; then
        # Python 3.6/3.7: use older compatible versions
        PKGS="paramiko<3 requests<2.28 matplotlib<3.4 jinja2<3.1 pyyaml numpy<1.20"
        info "Python 3.${PY_MINOR} detected, using compatible package versions"
    else
        PKGS="paramiko requests matplotlib jinja2 pyyaml python-docx numpy"
    fi

    $PYTHON -m pip install --quiet \
        --no-index --find-links "$WHEEL_DIR" \
        $PKGS 2>&1 \
        || $PYTHON -m pip install --quiet --break-system-packages \
            --no-index --find-links "$WHEEL_DIR" \
            $PKGS 2>&1 \
        || error "Python dependencies installation failed"

    # python-docx: try wheel first, fall back to source tarball
    if ! $PYTHON -c "import docx" 2>/dev/null; then
        $PYTHON -m pip install --quiet --no-index --find-links "$WHEEL_DIR" python-docx 2>&1 \
            || $PYTHON -m pip install --quiet --find-links "$WHEEL_DIR" python-docx 2>&1 \
            || warn "python-docx install failed (Word report will be unavailable)"
    fi

    info "All Python dependencies installed"

    # --- Install project files ---
    step "Installing project files"
    mkdir -p "$INSTALL_DIR"/{bin,fonts}

    cp "$SCRIPT_DIR/ontap_s3_bench.py" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/ontap_s3_bench.py"
    cp "$SCRIPT_DIR/config_example.yaml" "$INSTALL_DIR/" 2>/dev/null || true

    # Keep wheels accessible for the script's auto-install fallback
    if [ ! -d "$INSTALL_DIR/wheels" ]; then
        ln -sf "$WHEEL_DIR" "$INSTALL_DIR/wheels" 2>/dev/null \
            || cp -r "$WHEEL_DIR" "$INSTALL_DIR/wheels"
    fi
    info "Project files installed to $INSTALL_DIR"

    # --- Install warp ---
    step "Installing warp"
    cp "$SCRIPT_DIR/bin/warp" "$INSTALL_DIR/bin/warp"
    chmod +x "$INSTALL_DIR/bin/warp"

    # Try system-wide install
    if sudo cp "$INSTALL_DIR/bin/warp" /usr/local/bin/warp 2>/dev/null; then
        sudo chmod +x /usr/local/bin/warp
        info "warp installed to /usr/local/bin/warp"
    else
        warn "Cannot write to /usr/local/bin, using $INSTALL_DIR/bin/warp"
        export PATH="$INSTALL_DIR/bin:$PATH"
    fi
    WARP_VER=$("$INSTALL_DIR/bin/warp" --version 2>&1 | head -1)
    info "warp version: $WARP_VER"

    # --- Install font ---
    step "Installing Chinese font"
    if [ -f "$SCRIPT_DIR/fonts/wqy-microhei.ttc" ]; then
        cp "$SCRIPT_DIR/fonts/wqy-microhei.ttc" "$INSTALL_DIR/fonts/"

        # Try system-wide install
        FONT_DIR="/usr/share/fonts/wqy"
        if sudo mkdir -p "$FONT_DIR" 2>/dev/null && \
           sudo cp "$SCRIPT_DIR/fonts/wqy-microhei.ttc" "$FONT_DIR/" 2>/dev/null; then
            sudo fc-cache -f 2>/dev/null || true
            info "Font installed to $FONT_DIR"
        else
            info "Font available at $INSTALL_DIR/fonts/ (no root access for system install)"
        fi
    else
        warn "Font file not found in package, charts may show squares for Chinese"
    fi

    # Clear matplotlib font cache
    rm -rf "$HOME/.cache/matplotlib" 2>/dev/null || true

    # --- Verify ---
    step "Verification"
    echo -e "\n${CYAN}Python packages:${NC}"
    FAIL=0
    for mod in paramiko requests matplotlib jinja2 yaml docx numpy; do
        if $PYTHON -c "import $mod" 2>/dev/null; then
            echo -e "  ${GREEN}OK${NC}  $mod"
        else
            echo -e "  ${RED}FAIL${NC}  $mod"
            FAIL=1
        fi
    done

    echo -e "\n${CYAN}Tools:${NC}"
    if [ -x "$INSTALL_DIR/bin/warp" ]; then
        echo -e "  ${GREEN}OK${NC}  warp ($WARP_VER)"
    else
        echo -e "  ${RED}FAIL${NC}  warp"
        FAIL=1
    fi

    echo -e "\n${CYAN}Project:${NC}"
    echo "  Location: $INSTALL_DIR"
    LINE_COUNT=$(wc -l < "$INSTALL_DIR/ontap_s3_bench.py")
    echo "  Script: ontap_s3_bench.py ($LINE_COUNT lines)"

    if [ "$FAIL" = "1" ]; then
        error "Some dependencies are missing!"
    fi

    echo -e "\n${GREEN}All checks passed!${NC}"

    # --- Done ---
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Installation Complete!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Run options:"
    echo -e "  ${CYAN}Interactive:${NC}  cd $INSTALL_DIR && $PYTHON ontap_s3_bench.py"
    echo -e "  ${CYAN}Config file:${NC}  cd $INSTALL_DIR && $PYTHON ontap_s3_bench.py --config config.yaml"
    echo -e "  ${CYAN}Dry run:${NC}      cd $INSTALL_DIR && $PYTHON ontap_s3_bench.py --dry-run"
    echo ""

    # Ask to launch
    read -p "Launch interactive mode now? [Y/n]: " LAUNCH
    LAUNCH=${LAUNCH:-Y}
    if [[ "$LAUNCH" =~ ^[Yy]$ ]]; then
        echo ""
        cd "$INSTALL_DIR"
        exec $PYTHON ontap_s3_bench.py
    else
        info "You can run it later: cd $INSTALL_DIR && $PYTHON ontap_s3_bench.py"
    fi
}

main "$@"
