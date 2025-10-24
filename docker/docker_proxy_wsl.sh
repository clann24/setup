#!/bin/bash
#
# Docker Proxy Setup for WSL2 Ubuntu
# Configures Docker to use Windows host SOCKS5 proxy via Privoxy bridge
#
# Usage: sudo ./docker_proxy_wsl.sh [SOCKS5_PORT]
# Default SOCKS5 port: 1080
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SOCKS5_HOST="127.0.0.1"
SOCKS5_PORT="${1:-1080}"
PRIVOXY_PORT="8118"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_wsl() {
    if ! grep -qi microsoft /proc/version; then
        log_warning "This script is designed for WSL2. Proceeding anyway..."
    fi
}

test_socks5() {
    log_info "Testing SOCKS5 connectivity at ${SOCKS5_HOST}:${SOCKS5_PORT}..."
    if timeout 3 bash -c "echo > /dev/tcp/${SOCKS5_HOST}/${SOCKS5_PORT}" 2>/dev/null; then
        log_success "SOCKS5 proxy is reachable"
        return 0
    else
        log_error "Cannot connect to SOCKS5 proxy at ${SOCKS5_HOST}:${SOCKS5_PORT}"
        log_error "Please ensure:"
        log_error "  1. Windows proxy client is running"
        log_error "  2. 'Allow LAN' is enabled"
        log_error "  3. SOCKS5 is listening on port ${SOCKS5_PORT}"
        exit 1
    fi
}

install_privoxy() {
    log_info "Installing Privoxy..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y privoxy >/dev/null 2>&1
    log_success "Privoxy installed"
}

configure_privoxy() {
    log_info "Configuring Privoxy to forward to ${SOCKS5_HOST}:${SOCKS5_PORT}..."
    
    # Backup original config
    if [[ ! -f /etc/privoxy/config.bak ]]; then
        cp /etc/privoxy/config /etc/privoxy/config.bak
        log_info "Backed up original config to /etc/privoxy/config.bak"
    fi
    
    # Remove existing forward rules
    sed -i '/^forward-socks5/d' /etc/privoxy/config
    
    # Add SOCKS5 forwarding
    echo "forward-socks5t / ${SOCKS5_HOST}:${SOCKS5_PORT} ." >> /etc/privoxy/config
    
    # Ensure listen address is set
    if ! grep -q "^listen-address 127.0.0.1:${PRIVOXY_PORT}" /etc/privoxy/config; then
        if grep -q "^#\?listen-address" /etc/privoxy/config; then
            sed -i "s/^#\?listen-address.*/listen-address 127.0.0.1:${PRIVOXY_PORT}/" /etc/privoxy/config
        else
            echo "listen-address 127.0.0.1:${PRIVOXY_PORT}" >> /etc/privoxy/config
        fi
    fi
    
    log_success "Privoxy configured"
}

start_privoxy() {
    log_info "Starting Privoxy service..."
    systemctl enable privoxy >/dev/null 2>&1
    systemctl restart privoxy
    
    # Wait for service to start
    sleep 2
    
    if systemctl is-active --quiet privoxy; then
        log_success "Privoxy is running on 127.0.0.1:${PRIVOXY_PORT}"
    else
        log_error "Failed to start Privoxy"
        exit 1
    fi
}

configure_docker_proxy() {
    log_info "Configuring Docker daemon proxy..."
    
    # Create systemd drop-in directory
    mkdir -p /etc/systemd/system/docker.service.d
    
    # Create proxy configuration
    cat > /etc/systemd/system/docker.service.d/proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:${PRIVOXY_PORT}"
Environment="HTTPS_PROXY=http://127.0.0.1:${PRIVOXY_PORT}"
Environment="NO_PROXY=localhost,127.0.0.1,docker-registry.example.com,.corp"
EOF
    
    log_success "Docker proxy configuration created"
}

configure_docker_daemon() {
    log_info "Configuring Docker daemon settings..."
    
    # Backup existing daemon.json
    if [[ -f /etc/docker/daemon.json ]]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
        log_info "Backed up existing daemon.json"
    fi
    
    # Create daemon.json with IPv6 disabled and DNS servers
    cat > /etc/docker/daemon.json <<'EOF'
{
  "ipv6": false,
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
    
    log_success "Docker daemon.json configured"
}

disable_ipv6() {
    log_info "Disabling IPv6 at system level..."
    
    # Apply immediately
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
    sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null
    
    # Make persistent
    if ! grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf <<'EOF'

# Disable IPv6 for Docker proxy compatibility
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
        log_success "IPv6 disabled and persisted to /etc/sysctl.conf"
    else
        log_info "IPv6 already disabled in /etc/sysctl.conf"
    fi
}

configure_ipv4_preference() {
    log_info "Configuring IPv4 preference in DNS resolution..."
    
    # Backup gai.conf
    if [[ ! -f /etc/gai.conf.bak ]]; then
        cp /etc/gai.conf /etc/gai.conf.bak 2>/dev/null || true
    fi
    
    # Add IPv4 preference
    if ! grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
        echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
        log_success "IPv4 preference configured in /etc/gai.conf"
    else
        log_info "IPv4 preference already configured"
    fi
}

restart_docker() {
    log_info "Restarting Docker daemon..."
    systemctl daemon-reload
    systemctl restart docker
    
    # Wait for Docker to start
    sleep 3
    
    if systemctl is-active --quiet docker; then
        log_success "Docker daemon restarted successfully"
    else
        log_error "Failed to restart Docker"
        exit 1
    fi
}

verify_setup() {
    log_info "Verifying setup..."
    
    echo ""
    log_info "=== Configuration Summary ==="
    
    # Check SOCKS5
    if nc -zv ${SOCKS5_HOST} ${SOCKS5_PORT} 2>&1 | grep -q succeeded; then
        log_success "SOCKS5: ${SOCKS5_HOST}:${SOCKS5_PORT} ✓"
    else
        log_error "SOCKS5: ${SOCKS5_HOST}:${SOCKS5_PORT} ✗"
    fi
    
    # Check Privoxy
    if ss -ltn | grep -q ":${PRIVOXY_PORT}"; then
        log_success "Privoxy: 127.0.0.1:${PRIVOXY_PORT} ✓"
    else
        log_error "Privoxy: 127.0.0.1:${PRIVOXY_PORT} ✗"
    fi
    
    # Check Docker proxy environment
    DOCKER_ENV=$(systemctl show docker --property=Environment 2>/dev/null || echo "")
    if echo "$DOCKER_ENV" | grep -q "HTTP_PROXY"; then
        log_success "Docker proxy environment ✓"
    else
        log_error "Docker proxy environment ✗"
    fi
    
    # Check IPv6 status
    IPV6_STATUS=$(sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | awk '{print $3}')
    if [[ "$IPV6_STATUS" == "1" ]]; then
        log_success "IPv6 disabled ✓"
    else
        log_warning "IPv6 not disabled ✗"
    fi
    
    echo ""
    log_info "=== Testing Proxy Chain ==="
    
    # Test with curl
    if command -v curl >/dev/null 2>&1; then
        if http_proxy=http://127.0.0.1:${PRIVOXY_PORT} https_proxy=http://127.0.0.1:${PRIVOXY_PORT} \
           curl -s -m 10 https://api.ipify.org >/dev/null 2>&1; then
            log_success "Proxy chain test (curl) ✓"
        else
            log_warning "Proxy chain test (curl) ✗"
        fi
    fi
    
    # Test Docker pull
    log_info "Testing Docker pull (this may take a moment)..."
    if timeout 30 docker pull hello-world >/dev/null 2>&1; then
        log_success "Docker pull test ✓"
    else
        log_warning "Docker pull test ✗ (may need to wait for DNS propagation)"
    fi
    
    echo ""
}

print_usage_info() {
    echo ""
    log_success "=== Setup Complete ==="
    echo ""
    echo "Docker is now configured to use your Windows SOCKS5 proxy."
    echo ""
    echo "Proxy chain:"
    echo "  Docker → Privoxy (127.0.0.1:${PRIVOXY_PORT}) → SOCKS5 (${SOCKS5_HOST}:${SOCKS5_PORT}) → Internet"
    echo ""
    echo "Useful commands:"
    echo "  • Check Privoxy:  systemctl status privoxy"
    echo "  • Check Docker:   systemctl status docker"
    echo "  • View logs:      journalctl -u privoxy -f"
    echo "  • Test proxy:     http_proxy=http://127.0.0.1:${PRIVOXY_PORT} curl https://api.ipify.org"
    echo "  • Test Docker:    docker run --rm hello-world"
    echo ""
    echo "Configuration files:"
    echo "  • Privoxy:        /etc/privoxy/config"
    echo "  • Docker proxy:   /etc/systemd/system/docker.service.d/proxy.conf"
    echo "  • Docker daemon:  /etc/docker/daemon.json"
    echo "  • IPv6 disable:   /etc/sysctl.conf"
    echo ""
    echo "To use docker without sudo in current shell:"
    echo "  newgrp docker"
    echo ""
}

# Main execution
main() {
    echo ""
    log_info "Docker Proxy Setup for WSL2 Ubuntu"
    log_info "SOCKS5: ${SOCKS5_HOST}:${SOCKS5_PORT}"
    echo ""
    
    check_root
    check_wsl
    test_socks5
    
    install_privoxy
    configure_privoxy
    start_privoxy
    
    configure_docker_proxy
    configure_docker_daemon
    disable_ipv6
    configure_ipv4_preference
    restart_docker
    
    verify_setup
    print_usage_info
}

# Run main function
main "$@"
