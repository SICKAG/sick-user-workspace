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
VALID_TOOLS=(base docker go gotools netmon)
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
    echo "  base     Base tools (git, openssh-client, etc.)"
    echo "  docker   Docker and docker-cli tools"
    echo "  go       Install Go (latest available)"
    echo "  gotools  Go tools: grpcurl, gopls, delve debugger (requires Go)"
    echo "  netmon   Network & Monitoring (btop, can-utils...)"
    echo ""
    echo "Examples:"
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

echo "📦 Installing curl and ca-certificates..."
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
        base     "Base tools (git, openssh-client, etc.)"       on \
        docker   "Docker and docker-cli tools"                         off \
        go       "Install Go (latest)"                                off \
        gotools  "Go tools: grpcurl, gopls, delve debugger (requires Go)" off \
        netmon   "Network & Monitoring (btop, can-utils...)" off \
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
INSTALL_GO_HELPERS=false
INSTALL_NETMON=false

for CHOICE in "${CHOICES[@]}"; do
    case "$CHOICE" in
        base)     INSTALL_BASE=true ;;
        docker)   INSTALL_DOCKER=true ;;
        go)       INSTALL_GO=true ;;
        gotools)  INSTALL_GO_HELPERS=true ;;
        netmon)   INSTALL_NETMON=true ;;
    esac
done

# Install base tools
if $INSTALL_BASE; then
    echo "📦 Installing base tools..."
    apt-get install -y --no-install-recommends \
        openssh-client python3-setuptools git vim
fi

# Install Docker
if $INSTALL_DOCKER; then
    echo "🐳 Installing Docker and docker compose..."
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
        echo "    Installing latest Docker CLI with DOCKER_API_VERSION=1.43"
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

    echo "🐹 Installing Go..."

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

    echo "✓ Go $GO_VERSION installed successfully"
fi

# Install grpcurl
if $INSTALL_GO_HELPERS; then
     echo "🛠️ Installing Go helper tools..."

    [ -f /etc/profile.d/go.sh ] && . /etc/profile.d/go.sh

    if ! command -v go >/dev/null 2>&1; then
        echo "❗ Go is required for tools. Skipping grpcurl, delve and gopls installation."
    else
        export GOBIN=/usr/local/bin

        echo "🛰️ Installing grpcurl (/usr/local/bin/grpcurl)..."
        if go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest; then
            command -v grpcurl >/dev/null 2>&1 && echo "✓ grpcurl installed successfully"
        else
            echo "❌ grpcurl installation failed."
            exit 1
        fi

        # Install delve debugger
        echo "🐛 Installing delve debugger..."
        go install github.com/go-delve/delve/cmd/dlv@latest

        # Install gopls
        echo "🔧 Installing gopls..."
        go install golang.org/x/tools/gopls@latest
    fi
fi

# Install Network & Monitoring Tools
if $INSTALL_NETMON; then
    echo "🌐 Installing Network & Monitoring Tools..."
    apt-get install -y --no-install-recommends btop can-utils iproute2
fi

echo
echo "✅ Installation complete!"
