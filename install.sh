#!/bin/bash
###############################################################################
# ONTAP S3 Bench - One-Click Auto Deploy Script
# Auto download, install all dependencies, and launch interactive mode
# Supports: RHEL/CentOS/Rocky 8+ | Ubuntu/Debian 20+
###############################################################################
set -e

REPO_URL="https://raw.githubusercontent.com/NetApptool/ontap-s3-bench/main"
INSTALL_DIR="$HOME/ontap-s3-bench"
PYTHON=""
PIP=""

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "\n${CYAN}========== $1 ==========${NC}"; }

# --- Detect package manager ---
detect_pkg_mgr() {
    if command -v dnf &>/dev/null; then
        PKG_MGR="dnf"
        PKG_INSTALL="dnf install -y"
    elif command -v yum &>/dev/null; then
        PKG_MGR="yum"
        PKG_INSTALL="yum install -y"
    elif command -v apt-get &>/dev/null; then
        PKG_MGR="apt"
        PKG_INSTALL="apt-get install -y"
    else
        error "Unsupported package manager. Need dnf/yum/apt-get."
    fi
    info "Package manager: $PKG_MGR"
}

# --- Install system packages ---
install_system_deps() {
    step "Installing system dependencies"

    if [ "$PKG_MGR" = "apt" ]; then
        sudo apt-get update -qq
        sudo $PKG_INSTALL python3 python3-pip python3-venv python3-dev \
            wget curl tar gcc make libffi-dev libssl-dev \
            fonts-wqy-microhei 2>&1 | tail -5
    else
        # RHEL/CentOS/Rocky
        sudo $PKG_INSTALL python3 python3-pip python3-devel \
            wget curl tar gcc make libffi-devel openssl-devel 2>&1 | tail -5

        # EPEL for extra packages (ignore if already installed)
        if [ "$PKG_MGR" = "dnf" ]; then
            sudo dnf install -y epel-release 2>/dev/null || true
        else
            sudo yum install -y epel-release 2>/dev/null || true
        fi
    fi

    info "System dependencies installed"
}

# --- Find Python 3 ---
find_python() {
    step "Detecting Python 3"

    for cmd in python3 python3.12 python3.11 python3.10 python3.9; do
        if command -v "$cmd" &>/dev/null; then
            PYTHON="$cmd"
            break
        fi
    done

    [ -z "$PYTHON" ] && error "Python 3 not found after installation"

    PY_VER=$($PYTHON --version 2>&1)
    info "Found: $PY_VER ($PYTHON)"

    # Find pip
    for cmd in pip3 pip3.12 pip3.11 pip3.10 pip3.9; do
        if command -v "$cmd" &>/dev/null; then
            PIP="$cmd"
            break
        fi
    done

    # Fallback: use python -m pip
    if [ -z "$PIP" ]; then
        if $PYTHON -m pip --version &>/dev/null; then
            PIP="$PYTHON -m pip"
            info "Using: $PYTHON -m pip"
        else
            warn "pip not found, installing via ensurepip..."
            $PYTHON -m ensurepip --upgrade 2>/dev/null || sudo $PKG_INSTALL python3-pip
            PIP="$PYTHON -m pip"
        fi
    else
        info "Found: $($PIP --version 2>&1)"
    fi
}

# --- Install Python dependencies ---
install_python_deps() {
    step "Installing Python dependencies"

    # Upgrade pip first
    $PIP install --upgrade pip 2>&1 | tail -1

    # All required packages (including numpy which is missing from requirements.txt)
    PACKAGES=(
        "paramiko>=3.0"
        "requests>=2.28"
        "matplotlib>=3.6"
        "jinja2>=3.1"
        "pyyaml>=6.0"
        "python-docx>=1.0"
        "numpy"
        "urllib3"
    )

    for pkg in "${PACKAGES[@]}"; do
        pkg_name=$(echo "$pkg" | sed 's/[><=].*//')
        if $PYTHON -c "import $pkg_name" 2>/dev/null; then
            info "$pkg_name - already installed"
        else
            info "Installing $pkg_name ..."
            $PIP install "$pkg" 2>&1 | tail -1
        fi
    done

    # Special case: yaml module name differs from package name
    if ! $PYTHON -c "import yaml" 2>/dev/null; then
        $PIP install pyyaml 2>&1 | tail -1
    fi
    if ! $PYTHON -c "import docx" 2>/dev/null; then
        $PIP install python-docx 2>&1 | tail -1
    fi

    info "All Python dependencies installed"
}

# --- Download project files ---
download_project() {
    step "Downloading ontap-s3-bench"

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Download main script
    info "Downloading ontap_s3_bench.py ..."
    wget -q --no-check-certificate -O ontap_s3_bench.py "${REPO_URL}/ontap_s3_bench.py" \
        || curl -skL -o ontap_s3_bench.py "${REPO_URL}/ontap_s3_bench.py"

    # Download config example
    info "Downloading config_example.yaml ..."
    wget -q --no-check-certificate -O config_example.yaml "${REPO_URL}/config_example.yaml" \
        || curl -skL -o config_example.yaml "${REPO_URL}/config_example.yaml"

    # Verify download
    if [ ! -s ontap_s3_bench.py ]; then
        error "Download failed: ontap_s3_bench.py is empty"
    fi

    LINE_COUNT=$(wc -l < ontap_s3_bench.py)
    info "Downloaded successfully ($LINE_COUNT lines)"
}

# --- Install Chinese font for matplotlib charts ---
install_font() {
    step "Installing Chinese font (for report charts)"

    FONT_DIR="/usr/share/fonts/wqy"
    FONT_FILE="$FONT_DIR/wqy-microhei.ttc"

    if [ -f "$FONT_FILE" ]; then
        info "Chinese font already exists"
        return
    fi

    # Try system package first
    if [ "$PKG_MGR" = "apt" ]; then
        sudo apt-get install -y fonts-wqy-microhei 2>/dev/null && return || true
    else
        sudo $PKG_INSTALL wqy-microhei-fonts 2>/dev/null && return || true
    fi

    # Fallback: download from GitHub
    info "Downloading font from GitHub..."
    sudo mkdir -p "$FONT_DIR"
    FONT_URL="https://github.com/anthonyfok/fonts-wqy-microhei/raw/master/wqy-microhei.ttc"
    sudo wget -q --no-check-certificate -O "$FONT_FILE" "$FONT_URL" 2>/dev/null \
        || sudo curl -skL -o "$FONT_FILE" "$FONT_URL" 2>/dev/null || true

    if [ -f "$FONT_FILE" ] && [ -s "$FONT_FILE" ]; then
        sudo fc-cache -f 2>/dev/null || true
        info "Chinese font installed"
    else
        warn "Font download failed - charts may show squares for Chinese characters"
    fi

    # Clear matplotlib font cache
    rm -rf "$HOME/.cache/matplotlib" 2>/dev/null || true
}

# --- Pre-download warp binary ---
install_warp() {
    step "Pre-downloading MinIO warp"

    WARP_PATH="/usr/local/bin/warp"
    if [ -x "$WARP_PATH" ]; then
        info "warp already installed: $($WARP_PATH --version 2>&1 | head -1)"
        return
    fi

    WARP_URL="https://dl.min.io/aistor/warp/release/linux-amd64/warp"
    info "Downloading warp from MinIO CDN..."

    wget -q --no-check-certificate -O /tmp/warp "$WARP_URL" \
        || curl -skL -o /tmp/warp "$WARP_URL"

    if [ -s /tmp/warp ]; then
        sudo cp /tmp/warp "$WARP_PATH"
        sudo chmod +x "$WARP_PATH"
        rm -f /tmp/warp
        info "warp installed: $($WARP_PATH --version 2>&1 | head -1)"
    else
        warn "warp download failed - the script will try again during Step 5"
    fi
}

# --- Verify everything ---
verify() {
    step "Verification"

    echo -e "\n${CYAN}System:${NC}"
    echo "  OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "  Python: $($PYTHON --version 2>&1)"
    echo "  pip: $($PIP --version 2>&1 | head -1)"

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

    echo -e "\n${CYAN}System tools:${NC}"
    for tool in wget tar sudo; do
        if command -v "$tool" &>/dev/null; then
            echo -e "  ${GREEN}OK${NC}  $tool"
        else
            echo -e "  ${RED}FAIL${NC}  $tool"
            FAIL=1
        fi
    done

    if command -v warp &>/dev/null; then
        echo -e "  ${GREEN}OK${NC}  warp ($(warp --version 2>&1 | head -1))"
    else
        echo -e "  ${YELLOW}WARN${NC}  warp (will be downloaded during test)"
    fi

    echo -e "\n${CYAN}Project:${NC}"
    echo "  Location: $INSTALL_DIR"
    echo "  Script: ontap_s3_bench.py ($(wc -l < "$INSTALL_DIR/ontap_s3_bench.py") lines)"

    if [ "$FAIL" = "1" ]; then
        error "Some dependencies are missing!"
    fi

    echo -e "\n${GREEN}All checks passed!${NC}"
}

# --- Main ---
main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║     ONTAP S3 Bench - One-Click Auto Installer       ║"
    echo "║     Auto download + dependencies + launch           ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    detect_pkg_mgr
    install_system_deps
    find_python
    install_python_deps
    download_project
    install_font
    install_warp
    verify

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
