#!/bin/bash
###############################################################################
# ONTAP S3 Bench - Smart Installer
# Auto-detect: offline (local wheels) or online (download from internet)
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
REPO_URL="https://raw.githubusercontent.com/NetApptool/ontap-s3-bench/main"
WARP_CDN="https://dl.min.io/aistor/warp/release/linux-amd64/warp"

# Detect mode: offline if wheels/ exists in same dir, otherwise online
if [ -d "$SCRIPT_DIR/wheels" ] && [ -f "$SCRIPT_DIR/ontap_s3_bench.py" ]; then
    MODE="offline"
else
    MODE="online"
fi

main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   ONTAP S3 Bench - Auto Installer ($MODE mode)      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    find_python
    ensure_pip

    if [ "$MODE" = "offline" ]; then
        install_offline
    else
        install_online
    fi

    install_warp
    install_font
    verify
    done_msg
}

find_python() {
    step "Detecting Python 3"
    PYTHON=""
    for cmd in python3 python3.12 python3.11 python3.9 python3.8; do
        if command -v "$cmd" &>/dev/null; then
            PYTHON="$cmd"
            break
        fi
    done
    [ -z "$PYTHON" ] && error "Python 3 not found. Run: sudo yum install -y python3 or sudo dnf install -y python3"
    info "Found: $($PYTHON --version 2>&1) ($PYTHON)"
}

ensure_pip() {
    step "Checking pip"
    if ! $PYTHON -m pip --version &>/dev/null; then
        info "pip not found, installing via ensurepip..."
        $PYTHON -m ensurepip --upgrade 2>&1 || error "Failed to install pip. Run: sudo yum install -y python3-pip"
    fi
    PIP_VER=$($PYTHON -m pip --version 2>&1 | grep -oP '\d+' | head -1)
    if [ "$PIP_VER" -lt 20 ] 2>/dev/null; then
        info "pip too old ($PIP_VER), upgrading..."
        $PYTHON -m pip install --upgrade pip 2>&1 | tail -2
    fi
    info "pip: $($PYTHON -m pip --version 2>&1 | head -1)"
}

get_pkgs() {
    PY_MINOR=$($PYTHON -c "import sys;print(sys.version_info.minor)")
    if [ "$PY_MINOR" -le 7 ]; then
        PKGS="paramiko<3 requests<2.28 matplotlib<3.4 jinja2<3.1 pyyaml numpy<1.20"
        info "Python 3.${PY_MINOR}: using compatible package versions"
    else
        PKGS="paramiko requests matplotlib jinja2 pyyaml python-docx numpy"
    fi
}

install_offline() {
    step "Installing Python dependencies (offline)"
    WHEEL_DIR="$SCRIPT_DIR/wheels"
    info "Found $(ls "$WHEEL_DIR"/*.whl 2>/dev/null | wc -l) wheel files"
    get_pkgs

    $PYTHON -m pip install --quiet --no-index --find-links "$WHEEL_DIR" $PKGS 2>&1 \
        || $PYTHON -m pip install --quiet --break-system-packages --no-index --find-links "$WHEEL_DIR" $PKGS 2>&1 \
        || error "Python dependencies installation failed"

    if ! $PYTHON -c "import docx" 2>/dev/null; then
        $PYTHON -m pip install --quiet --no-index --find-links "$WHEEL_DIR" python-docx 2>&1 \
            || $PYTHON -m pip install --quiet --find-links "$WHEEL_DIR" python-docx 2>&1 \
            || warn "python-docx install failed (Word report unavailable)"
    fi
    info "All Python dependencies installed"

    step "Installing project files"
    mkdir -p "$INSTALL_DIR"/{bin,fonts}
    cp "$SCRIPT_DIR/ontap_s3_bench.py" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/ontap_s3_bench.py"
    cp "$SCRIPT_DIR/config_example.yaml" "$INSTALL_DIR/" 2>/dev/null || true
    [ ! -d "$INSTALL_DIR/wheels" ] && ln -sf "$WHEEL_DIR" "$INSTALL_DIR/wheels" 2>/dev/null || true
    info "Project files installed to $INSTALL_DIR"
}

install_online() {
    step "Installing Python dependencies (online)"
    get_pkgs

    $PYTHON -m pip install --quiet $PKGS 2>&1 \
        || $PYTHON -m pip install --quiet --break-system-packages $PKGS 2>&1 \
        || $PYTHON -m pip install --user --quiet $PKGS 2>&1 \
        || error "Python dependencies installation failed"

    if ! $PYTHON -c "import docx" 2>/dev/null; then
        $PYTHON -m pip install --quiet python-docx 2>&1 || warn "python-docx install failed"
    fi
    info "All Python dependencies installed"

    step "Downloading project files"
    mkdir -p "$INSTALL_DIR"
    for f in ontap_s3_bench.py config_example.yaml; do
        info "Downloading $f..."
        wget -q --no-check-certificate -O "$INSTALL_DIR/$f" "$REPO_URL/$f" 2>/dev/null \
            || curl -skL -o "$INSTALL_DIR/$f" "$REPO_URL/$f" 2>/dev/null \
            || error "Failed to download $f"
    done
    chmod +x "$INSTALL_DIR/ontap_s3_bench.py"
    info "Project files installed to $INSTALL_DIR"
}

install_warp() {
    step "Installing warp"
    mkdir -p "$INSTALL_DIR/bin"

    if [ -f "$SCRIPT_DIR/bin/warp" ]; then
        cp "$SCRIPT_DIR/bin/warp" "$INSTALL_DIR/bin/warp"
    elif [ ! -x "$INSTALL_DIR/bin/warp" ] && ! command -v warp &>/dev/null; then
        info "Downloading warp..."
        wget -q --no-check-certificate -O "$INSTALL_DIR/bin/warp" "$WARP_CDN" 2>/dev/null \
            || curl -skL -o "$INSTALL_DIR/bin/warp" "$WARP_CDN" 2>/dev/null \
            || error "Failed to download warp"
    fi

    chmod +x "$INSTALL_DIR/bin/warp"
    sudo cp "$INSTALL_DIR/bin/warp" /usr/local/bin/warp 2>/dev/null && sudo chmod +x /usr/local/bin/warp
    WARP_VER=$("$INSTALL_DIR/bin/warp" --version 2>&1 | head -1)
    info "warp: $WARP_VER"
}

install_font() {
    step "Installing Chinese font"
    FONT_DIR="/usr/share/fonts/wqy"
    FONT_FILE="$FONT_DIR/wqy-microhei.ttc"

    if [ -f "$FONT_FILE" ]; then
        info "Chinese font already exists"
        return
    fi

    if [ -f "$SCRIPT_DIR/fonts/wqy-microhei.ttc" ]; then
        mkdir -p "$INSTALL_DIR/fonts"
        cp "$SCRIPT_DIR/fonts/wqy-microhei.ttc" "$INSTALL_DIR/fonts/"
        sudo mkdir -p "$FONT_DIR" 2>/dev/null && sudo cp "$SCRIPT_DIR/fonts/wqy-microhei.ttc" "$FONT_DIR/" 2>/dev/null
    else
        # Try system package or download
        if command -v yum &>/dev/null; then
            sudo yum install -y wqy-microhei-fonts 2>/dev/null || true
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y wqy-microhei-fonts 2>/dev/null || true
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y fonts-wqy-microhei 2>/dev/null || true
        fi
    fi

    [ -f "$FONT_FILE" ] && info "Font installed" || warn "Font not available, charts may show squares"
    rm -rf "$HOME/.cache/matplotlib" 2>/dev/null || true
}

verify() {
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
    if command -v warp &>/dev/null || [ -x "$INSTALL_DIR/bin/warp" ]; then
        echo -e "  ${GREEN}OK${NC}  warp ($WARP_VER)"
    else
        echo -e "  ${RED}FAIL${NC}  warp"
        FAIL=1
    fi

    echo -e "\n${CYAN}Project:${NC}"
    echo "  Location: $INSTALL_DIR"
    echo "  Script: ontap_s3_bench.py ($(wc -l < "$INSTALL_DIR/ontap_s3_bench.py") lines)"

    [ "$FAIL" = "1" ] && error "Some dependencies are missing!"
    echo -e "\n${GREEN}All checks passed!${NC}"
}

done_msg() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Installation Complete!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Run:  ${CYAN}cd $INSTALL_DIR && $PYTHON ontap_s3_bench.py${NC}"
    echo ""

    read -p "Launch now? [Y/n]: " LAUNCH
    LAUNCH=${LAUNCH:-Y}
    if [[ "$LAUNCH" =~ ^[Yy]$ ]]; then
        cd "$INSTALL_DIR" && exec $PYTHON ontap_s3_bench.py
    else
        info "Run later: cd $INSTALL_DIR && $PYTHON ontap_s3_bench.py"
    fi
}

main "$@"
