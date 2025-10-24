#!/bin/bash

# Shadowsocks Server Setup Script for Ubuntu
# This script installs and configures shadowsocks-libev server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_PORT=443
DEFAULT_PASSWORD=$(openssl rand -base64 16)
DEFAULT_METHOD="aes-256-gcm"

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if running on Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    print_warning "This script is designed for Ubuntu. It may not work on other distributions."
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

print_info "Starting Shadowsocks server installation..."

# Get configuration from user
echo ""
echo "===== Configuration ====="
read -p "Enter server port (default: ${DEFAULT_PORT}): " PORT
PORT=${PORT:-$DEFAULT_PORT}

read -p "Enter password (default: auto-generated): " PASSWORD
PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}

echo ""
echo "Available encryption methods:"
echo "  1) aes-256-gcm (recommended)"
echo "  2) aes-128-gcm"
echo "  3) chacha20-ietf-poly1305"
read -p "Select encryption method (1-3, default: 1): " METHOD_CHOICE
METHOD_CHOICE=${METHOD_CHOICE:-1}

case $METHOD_CHOICE in
    1) METHOD="aes-256-gcm" ;;
    2) METHOD="aes-128-gcm" ;;
    3) METHOD="chacha20-ietf-poly1305" ;;
    *) METHOD="aes-256-gcm" ;;
esac

echo ""
echo "===== Configuration Summary ====="
echo "Port: $PORT"
echo "Password: $PASSWORD"
echo "Encryption: $METHOD"
echo ""
read -p "Continue with this configuration? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    print_info "Installation cancelled."
    exit 0
fi

# Update system
print_info "Updating system packages..."
apt-get update -qq

# Install dependencies
print_info "Installing dependencies..."
apt-get install -y -qq \
    software-properties-common \
    wget \
    curl \
    gnupg2 \
    ca-certificates \
    lsb-release \
    qrencode

# Install shadowsocks-libev
print_info "Installing shadowsocks-libev..."
apt-get install -y -qq shadowsocks-libev

# Stop the service first if it's running
systemctl stop shadowsocks-libev.service 2>/dev/null || true
systemctl stop shadowsocks-libev-server@.service 2>/dev/null || true

# Create configuration directory if it doesn't exist
CONFIG_DIR="/etc/shadowsocks-libev"
CONFIG_FILE="${CONFIG_DIR}/config.json"

mkdir -p ${CONFIG_DIR}

# Backup existing config if present
if [ -f "${CONFIG_FILE}" ]; then
    print_warning "Backing up existing configuration..."
    cp ${CONFIG_FILE} ${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)
fi

# Create configuration file
print_info "Creating configuration file..."
cat > ${CONFIG_FILE} <<EOF
{
    "server": ["::0", "0.0.0.0"],
    "mode": "tcp_and_udp",
    "server_port": ${PORT},
    "password": "${PASSWORD}",
    "timeout": 300,
    "method": "${METHOD}",
    "fast_open": true,
    "nameserver": "8.8.8.8",
    "no_delay": true,
    "reuse_port": true
}
EOF

# Set proper permissions
chmod 644 ${CONFIG_FILE}

# Create a custom systemd service file
print_info "Creating systemd service file..."
SERVICE_FILE="/etc/systemd/system/shadowsocks-server.service"

cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Shadowsocks-libev Server
Documentation=man:ss-server(1)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ss-server -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
User=nobody
Group=nogroup
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon
systemctl daemon-reload

# Configure systemd service
print_info "Configuring systemd service..."
systemctl enable shadowsocks-server.service

# Restart service
print_info "Starting Shadowsocks server..."
systemctl restart shadowsocks-server.service

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet shadowsocks-server.service; then
    print_info "Shadowsocks server is running successfully!"
else
    print_error "Failed to start Shadowsocks server. Check logs with: journalctl -u shadowsocks-server -n 50"
    systemctl status shadowsocks-server.service --no-pager || true
    exit 1
fi

# Configure firewall if ufw is installed
if command -v ufw &> /dev/null; then
    print_info "Configuring firewall..."
    ufw allow ${PORT}/tcp
    ufw allow ${PORT}/udp
    print_info "Firewall rules added for port ${PORT}"
fi

# Enable BBR (TCP congestion control) for better performance
print_info "Enabling BBR for better performance..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi
sysctl -p > /dev/null 2>&1

# Get server IP
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "YOUR_SERVER_IP")

# Generate SS URI and QR code
print_info "Generating QR code for client import..."

# Create SS URI: ss://base64(method:password@server:port)
SS_CONTENT="${METHOD}:${PASSWORD}@${SERVER_IP}:${PORT}"
SS_BASE64=$(echo -n "${SS_CONTENT}" | base64 -w 0 2>/dev/null || echo -n "${SS_CONTENT}" | base64)
SS_URI="ss://${SS_BASE64}"

# Generate Clash profile
echo ""
echo "=========================================="
print_info "Clash Profile:"
echo "=========================================="
cat <<CLASHEOF
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
proxies:
  - name: ${SERVER_IP}:${PORT}
    server: ${SERVER_IP}
    port: ${PORT}
    type: ss
    cipher: ${METHOD}
    password: ${PASSWORD}
    udp: true
CLASHEOF
echo ""

# Generate QR code
echo ""
echo "=========================================="
print_info "QR Code for Client Import:"
echo "=========================================="
qrencode -t ANSIUTF8 "${SS_URI}"
echo ""
echo "Or scan this link with your Shadowsocks client:"
echo "${SS_URI}"
echo ""
echo "SS URI: ${SS_URI}"
echo ""
echo "=========================================="
