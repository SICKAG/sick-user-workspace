#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

append() {
    local LINE="$1"
    local FILE="$2"

    # Create file if it doesn't exist
    touch "$FILE"

    # Check if the exact line exists; if not, append it
    grep -Fxq "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
}

# ---------------------------------------------------------------------------
# Argument parsing: -t/--tools for non-interactive (pipeline/Docker) mode
# ---------------------------------------------------------------------------
VALID_TOOLS=(default base docker go grpcurl gotools netmon build python proto clang cli)
CHOICES=()
NON_INTERACTIVE=false

usage() {
    echo "Usage: install-recommended-tools [-t|--tools <tool>[,<tool>...] [<tool>...]] [-h|--help]"
    echo ""
    echo "  -t, --tools   Comma- or space-separated list of tools to install."
    echo "                Omit to use interactive dialog selection."
    echo "  -h, --help    Show this help and exit."
    echo ""
    echo "Available tools:"
    echo "  default  Curated default set (base, docker, netmon, go, grpcurl)"
    echo "  base     Base tools (git, openssh-client, vim, python3-setuptools)"
    echo "  docker   Docker and docker-cli tools"
    echo "  go       Install Go (latest available)"
    echo "  grpcurl  grpcurl only (prebuilt binary, no Go required)"
    echo "  gotools  Go tools: grpcurl, gopls, delve debugger (requires Go)"
    echo "  netmon   Network & Monitoring (btop, can-utils...)"
    echo "  build    C/C++ toolchain (gcc, g++, make, cmake, ninja, gdb, ccache)"
    echo "  python   Python dev (pip, venv, python3-dev, pipx)"
    echo "  proto    Protocol Buffers / gRPC codegen (protoc + Go plugins)"
    echo "  clang    LLVM tools (clang, clangd, clang-format, clang-tidy, lldb)"
    echo "  cli      Extra CLI tools (jq, ripgrep, fd, tree, rsync...)"
    echo ""
    echo "Examples:"
    echo "  install-recommended-tools -t default"
    echo "  install-recommended-tools -t base,go,docker"
    echo "  install-recommended-tools --tools base go docker"
}

UNKNOWN_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -t|--tools)
            NON_INTERACTIVE=true
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                IFS=',' read -ra PARTS <<< "$1"
                for PART in "${PARTS[@]}"; do
                    [[ -n "$PART" ]] && CHOICES+=("$PART")
                done
                shift
            done
            ;;
        *)
            UNKNOWN_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#UNKNOWN_ARGS[@]} -gt 0 ]]; then
    echo "❌ Unrecognized arguments: ${UNKNOWN_ARGS[*]}"
    echo ""
    usage
    exit 1
fi

if $NON_INTERACTIVE; then
    INVALID_TOOLS=()
    for TOOL in "${CHOICES[@]}"; do
        FOUND=false
        for VALID in "${VALID_TOOLS[@]}"; do
            [[ "$TOOL" == "$VALID" ]] && FOUND=true && break
        done
        $FOUND || INVALID_TOOLS+=("$TOOL")
    done
    if [[ ${#INVALID_TOOLS[@]} -gt 0 ]]; then
        echo "❌ Unrecognized tools: ${INVALID_TOOLS[*]}"
        echo "   Valid options: ${VALID_TOOLS[*]}"
        exit 1
    fi
fi

echo "🔄 Updating package index..."
apt-get update -y && apt-get upgrade -y

echo "🛠️ Installing curl and ca-certificates..."
apt-get install -y --no-install-recommends ca-certificates curl

if ! $NON_INTERACTIVE; then
    if ! command -v dialog &> /dev/null; then
        echo "Installing dialog..."
        apt-get install -y dialog
    fi

    # Temp file to capture dialog output
    TMP_FILE=$(mktemp)

    # Show checklist using dialog
    dialog --backtitle "Setup Tool Installer" \
           --title "Tool Selection" \
           --checklist "Choose tools to install (use spacebar to select):" 20 78 10 \
        default  "Curated default set (base, docker, netmon, go, grpcurl)" off \
        base     "Base tools (git, openssh-client, vim, python3-setuptools)" on \
        docker   "Docker and docker-cli tools"                         off \
        go       "Install Go (latest)"                                off \
        grpcurl  "grpcurl only (prebuilt binary, no Go required)"      off \
        gotools  "Go tools: grpcurl, gopls, delve debugger (requires Go)" off \
        netmon   "Network & Monitoring (btop, can-utils...)" off \
        build    "C/C++ toolchain (gcc, g++, cmake, ninja, gdb)"   off \
        python   "Python dev (pip, venv, python3-dev, pipx)"       off \
        proto    "Protocol Buffers / gRPC codegen (protoc)"        off \
        clang    "LLVM tools (clang, clangd, clang-format, lldb)"  off \
        cli      "Extra CLI tools (jq, ripgrep, fd, tree...)"      off \
        2>"$TMP_FILE"

    # Handle cancel or ESC
    if [ $? -ne 0 ]; then
        clear
        echo "❌ Installation stopped. Exiting."
        rm -f "$TMP_FILE"
        exit1
    fi

    # Read selections into array
    read -ra CHOICES <<< "$(cat "$TMP_FILE")"
    rm -f "$TMP_FILE"
    clear
fi

if [ ${#CHOICES[@]} -eq 0 ]; then
    echo "❗ No tools selected for installation."
    exit 0
fi

# Parse choices into booleans
INSTALL_BASE=false
INSTALL_DOCKER=false
INSTALL_GO=false
INSTALL_GRPCURL=false
INSTALL_GO_HELPERS=false
INSTALL_NETMON=false
INSTALL_BUILD=false
INSTALL_PYTHON=false
INSTALL_PROTO=false
INSTALL_CLANG=false
INSTALL_CLI=false

for CHOICE in "${CHOICES[@]}"; do
    case "$CHOICE" in
        base)     INSTALL_BASE=true ;;
        docker)   INSTALL_DOCKER=true ;;
        go)       INSTALL_GO=true ;;
        grpcurl)  INSTALL_GRPCURL=true ;;
        gotools)  INSTALL_GO_HELPERS=true ;;
        netmon)   INSTALL_NETMON=true ;;
        build)    INSTALL_BUILD=true ;;
        python)   INSTALL_PYTHON=true ;;
        proto)    INSTALL_PROTO=true ;;
        clang)    INSTALL_CLANG=true ;;
        cli)      INSTALL_CLI=true ;;
        default)
            # Curated default set baked into the primary image
            INSTALL_BASE=true
            INSTALL_DOCKER=true
            INSTALL_NETMON=true
            INSTALL_GO=true
            INSTALL_GRPCURL=true
            ;;
    esac
done

# Install base tools
if $INSTALL_BASE; then
    echo "🛠️ Installing base tools..."
    apt-get install -y --no-install-recommends \
        openssh-client python3-setuptools git vim
fi

# Install Docker
if $INSTALL_DOCKER; then
    echo "🛠️ Installing Docker and docker compose..."
    # Detect host daemon API version
    HOST_API_VERSION=""

    if [ -S /var/run/docker.sock ]; then
        echo "🔍 Detecting host Docker daemon API version..."

        # curl with Unix socket
        if [ -z "$HOST_API_VERSION" ]; then
            HOST_API_VERSION=$(curl -sf --unix-socket /var/run/docker.sock \
                'http://localhost/version' 2>/dev/null \
                | sed -n 's/.*"ApiVersion":"\([^"]*\)".*/\1/p')
        fi

        # strip whitespace, take only first line
        HOST_API_VERSION=$(echo "$HOST_API_VERSION" | tr -d '[:space:]' | head -c 10)
    else
        echo "⚠️  API version could not be detected"
    fi

    if [ -n "$HOST_API_VERSION" ]; then
        echo "✓ Host Docker daemon API version: $HOST_API_VERSION"
    else
        echo "🛠️  Installing latest Docker CLI with DOCKER_API_VERSION=1.43"
    fi

    # Setting up Docker's apt repository - ref: https://docs.docker.com/engine/install/ubuntu/
    install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
        echo "❌ Failed to download Docker GPG key. Check your internet connection."
        exit 1
    fi
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    if ! apt-get update; then
        echo "❌ Failed to update package index for Docker repository. Check your internet connection."
        exit 1
    fi

    # Install packages
    if ! apt-get install -y docker-ce-cli docker-compose-plugin; then
        echo "❌ Failed to install Docker packages."
        exit 1
    fi
    echo "docker-ce-cli installed"

    # persist API fallback 
    EFFECTIVE_DOCKER_API_VERSION="${HOST_API_VERSION:-1.43}"
    echo "DOCKER_API_VERSION=${EFFECTIVE_DOCKER_API_VERSION}" >> /etc/environment
    echo "✓ Docker CLI installed successfully"
fi

# Install Go
if $INSTALL_GO; then

    update-ca-certificates

    echo "🛠️ Installing Go..."

    # Try to detect latest version
    FALLBACK_VERSION="1.26.1"
    GO_VERSION=""
    
    echo "🔍 Detecting latest Go version..."
    # returns string like 
    # go1.26.1
    # time 2026-03-05T20:45:11Z
    LATEST_VERSION=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -n 1 | sed 's/^go//')
    
    if [ -n "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "go" ]; then
        echo "✓ Latest version detected: $LATEST_VERSION"
        GO_VERSION="$LATEST_VERSION"
    else
        echo "⚠️  Latest version could not be determined, using fallback version $FALLBACK_VERSION"
        GO_VERSION="$FALLBACK_VERSION"
    fi
    
    case "$(uname -m)" in
        aarch64) GO_ARCH="linux-arm64" ;;
        armv7l|armv6l|armhf) GO_ARCH="linux-armv6l" ;;
        *) echo "❌ Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
    rm -rf /usr/local/go
    if ! curl -fL "https://go.dev/dl/go${GO_VERSION}.${GO_ARCH}.tar.gz" | tar --no-same-owner --no-same-permissions -C /usr/local -xzf -; then
        echo "❌ Go download or extraction failed."
        exit 1
    fi
    if [ ! -f /usr/local/go/bin/go ]; then
        echo "❌ Go binary not found after extraction."
        exit 1
    fi
    mkdir -p "/etc/profile.d/"
    echo 'export PATH="$PATH:/usr/local/go/bin"' > "/etc/profile.d/go.sh"
    echo 'export PATH="$PATH:${GOPATH:-$HOME/go}/bin"' >> "/etc/profile.d/go.sh"
    . "/etc/profile.d/go.sh"

    # Must be symlinked into /usr/local/bin otherwise bin wont be found on PATH
    ln -sf /usr/local/go/bin/go /usr/local/bin/go
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

    echo "✓ Go $GO_VERSION installed successfully"
fi

# Install grpcurl (prebuilt release binary — avoids fragile Go module builds
# that can fail behind a proxy, e.g. 403s from proxy.golang.org / sum.golang.org)
if $INSTALL_GRPCURL || $INSTALL_GO_HELPERS; then
    GRPCURL_VERSION="1.9.3"
    echo "🛠️ Installing grpcurl v${GRPCURL_VERSION} (/usr/local/bin/grpcurl)..."

    case "$(uname -m)" in
        aarch64)             GRPCURL_ARCH="linux_arm64" ;;
        armv7l|armv6l|armhf) GRPCURL_ARCH="linux_armv7" ;;
        x86_64)              GRPCURL_ARCH="linux_x86_64" ;;
        *) echo "❌ Unsupported architecture for grpcurl: $(uname -m)"; exit 1 ;;
    esac

    GRPCURL_URL="https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_${GRPCURL_ARCH}.tar.gz"
    if curl -fsSL "$GRPCURL_URL" | tar --no-same-owner -C /usr/local/bin -xzf - grpcurl; then
        chmod +x /usr/local/bin/grpcurl
        command -v grpcurl >/dev/null 2>&1 && echo "✓ grpcurl installed successfully"
    else
        echo "❌ grpcurl installation failed."
        exit 1
    fi
fi

# Install Go helper tools (gopls, delve)
if $INSTALL_GO_HELPERS; then
    echo "🛠️ Installing Go helper tools..."

    [ -f /etc/profile.d/go.sh ] && . /etc/profile.d/go.sh

    if ! command -v go >/dev/null 2>&1; then
        echo "❗ Go is required for gopls/delve. Skipping."
    else
        export GOBIN=/usr/local/bin

        # checksum must be disabled if behind proxy!
        export GOSUMDB=off

        echo "🛠️ Installing delve debugger..."
        go install github.com/go-delve/delve/cmd/dlv@latest

        echo "🛠️ Installing gopls..."
        go install golang.org/x/tools/gopls@latest
    fi
fi

if $INSTALL_NETMON; then
    echo "🛠️ Installing Network & Monitoring Tools..."
    apt-get install -y --no-install-recommends btop can-utils iproute2
fi

if $INSTALL_BUILD; then
    echo "🛠️ Installing C/C++ build toolchain..."
    apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build gdb pkg-config ccache
fi

if $INSTALL_PYTHON; then
    echo "🛠️ Installing Python development tools..."
    apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv python3-dev pipx
fi

if $INSTALL_CLANG; then
    echo "🛠️ Installing LLVM/Clang tools..."
    apt-get install -y --no-install-recommends \
        clang clangd clang-format clang-tidy lldb
fi

if $INSTALL_CLI; then
    echo "🛠️ Installing extra CLI tools..."
    apt-get install -y --no-install-recommends \
        jq ripgrep fd-find tree unzip xz-utils rsync file less
    # On Ubuntu the fd binary is 'fdfind' - create a symlink to 'fd'
    if command -v fdfind >/dev/null 2>&1; then
        ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    fi
fi

if $INSTALL_PROTO; then
    echo "🛠️ Installing Protocol Buffers compiler (protoc)..."
    apt-get install -y --no-install-recommends protobuf-compiler

    # Go plugins for protoc (require Go); mirror the gotools approach.
    [ -f /etc/profile.d/go.sh ] && . /etc/profile.d/go.sh
    if command -v go >/dev/null 2>&1; then
        echo "🛠️ Installing protoc Go plugins (protoc-gen-go, protoc-gen-go-grpc)..."
        export GOBIN=/usr/local/bin
        export GOSUMDB=off
        go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
        go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
    else
        echo "❗ Go not found — installed protoc only (skipping Go plugins)."
    fi
fi

echo
echo "✅ Installation complete!"
