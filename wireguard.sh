#!/bin/bash

# WireGuard VPN Server Setup Script for Ubuntu
# This script installs and configures WireGuard VPN server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_PORT=51820
DEFAULT_SERVER_IP="10.0.0.1/24"
DEFAULT_DNS="1.1.1.1, 8.8.8.8"
DEFAULT_CLIENT_COUNT=1

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
    read -p "Do you want to continue anyway? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        exit 1
    fi
fi

print_info "Starting WireGuard VPN server installation..."

# Get configuration from user
echo ""
echo "===== Configuration ====="
read -p "Enter WireGuard port (default: ${DEFAULT_PORT}): " WG_PORT
WG_PORT=${WG_PORT:-$DEFAULT_PORT}

read -p "Enter VPN subnet (default: ${DEFAULT_SERVER_IP}): " SERVER_IP
SERVER_IP=${SERVER_IP:-$DEFAULT_SERVER_IP}

read -p "Enter DNS servers (default: ${DEFAULT_DNS}): " DNS_SERVERS
DNS_SERVERS=${DNS_SERVERS:-$DEFAULT_DNS}

read -p "Number of clients to generate (default: ${DEFAULT_CLIENT_COUNT}): " CLIENT_COUNT
CLIENT_COUNT=${CLIENT_COUNT:-$DEFAULT_CLIENT_COUNT}

# Extract network info
VPN_SUBNET=$(echo ${SERVER_IP} | cut -d'/' -f1 | cut -d'.' -f1-3)
SERVER_IP_ONLY=$(echo ${SERVER_IP} | cut -d'/' -f1)

echo ""
echo "===== Configuration Summary ====="
echo "WireGuard Port: ${WG_PORT}"
echo "VPN Subnet:     ${SERVER_IP}"
echo "DNS Servers:    ${DNS_SERVERS}"
echo "Client Count:   ${CLIENT_COUNT}"
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
    wireguard \
    wireguard-tools \
    qrencode \
    iptables \
    net-tools

# Enable IP forwarding
print_info "Enabling IP forwarding..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
fi
sysctl -p > /dev/null 2>&1

# Create WireGuard directory
WG_DIR="/etc/wireguard"
mkdir -p ${WG_DIR}
chmod 700 ${WG_DIR}

# Generate server keys
print_info "Generating server keys..."
SERVER_PRIVATE_KEY=$(wg genkey)
SERVER_PUBLIC_KEY=$(echo ${SERVER_PRIVATE_KEY} | wg pubkey)

# Get server's public IP
print_info "Detecting server public IP..."
SERVER_PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "YOUR_SERVER_IP")

# Get default network interface
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Create server configuration
print_info "Creating server configuration..."
cat > ${WG_DIR}/wg0.conf <<EOF
[Interface]
Address = ${SERVER_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
SaveConfig = false

# NAT and forwarding rules
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${DEFAULT_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${DEFAULT_INTERFACE} -j MASQUERADE

EOF

# Generate client configurations
print_info "Generating client configurations..."
mkdir -p ${WG_DIR}/clients

for ((i=1; i<=CLIENT_COUNT; i++)); do
    CLIENT_NAME="client${i}"
    CLIENT_IP="${VPN_SUBNET}.$((i+1))/32"
    CLIENT_PRIVATE_KEY=$(wg genkey)
    CLIENT_PUBLIC_KEY=$(echo ${CLIENT_PRIVATE_KEY} | wg pubkey)
    CLIENT_PRESHARED_KEY=$(wg genpsk)

    # Add peer to server config
    cat >> ${WG_DIR}/wg0.conf <<EOF
# Client: ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_IP}

EOF

    # Create client config file
    cat > ${WG_DIR}/clients/${CLIENT_NAME}.conf <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}
DNS = ${DNS_SERVERS}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
Endpoint = ${SERVER_PUBLIC_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    print_info "Created configuration for ${CLIENT_NAME}"
done

# Set proper permissions
chmod 600 ${WG_DIR}/wg0.conf
chmod 600 ${WG_DIR}/clients/*.conf

# Enable and start WireGuard
print_info "Starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet wg-quick@wg0; then
    print_info "WireGuard server is running successfully!"
else
    print_error "Failed to start WireGuard server. Check logs with: journalctl -u wg-quick@wg0 -n 50"
    systemctl status wg-quick@wg0 --no-pager || true
    exit 1
fi

# Configure firewall if ufw is installed
if command -v ufw &> /dev/null; then
    print_info "Configuring firewall..."
    ufw allow ${WG_PORT}/udp
    print_info "Firewall rules added for port ${WG_PORT}/udp"
fi

# Generate QR codes for clients
print_info "Generating QR codes for clients..."

# Print success message and connection details
echo ""
echo "=========================================="
print_info "WireGuard VPN server installation complete!"
echo "=========================================="
echo ""
echo "Server Information:"
echo "  Public IP:     ${SERVER_PUBLIC_IP}"
echo "  Listen Port:   ${WG_PORT}"
echo "  VPN Subnet:    ${SERVER_IP}"
echo "  Interface:     wg0"
echo ""
echo "Server Keys:"
echo "  Public Key:    ${SERVER_PUBLIC_KEY}"
echo ""

# Display client configurations and QR codes
for ((i=1; i<=CLIENT_COUNT; i++)); do
    CLIENT_NAME="client${i}"
    CLIENT_CONFIG="${WG_DIR}/clients/${CLIENT_NAME}.conf"

    echo "=========================================="
    print_info "Client ${i}: ${CLIENT_NAME}"
    echo "=========================================="
    echo ""
    echo "Configuration file: ${CLIENT_CONFIG}"
    echo ""
    echo "QR Code (scan with WireGuard mobile app):"
    qrencode -t ANSIUTF8 < ${CLIENT_CONFIG}
    echo ""
    echo "Or use this configuration:"
    cat ${CLIENT_CONFIG}
    echo ""
done

echo "=========================================="
echo "Service Management Commands:"
echo "  Start:   sudo systemctl start wg-quick@wg0"
echo "  Stop:    sudo systemctl stop wg-quick@wg0"
echo "  Restart: sudo systemctl restart wg-quick@wg0"
echo "  Status:  sudo systemctl status wg-quick@wg0"
echo "  Check:   sudo wg show"
echo ""
echo "Configuration files:"
echo "  Server:  ${WG_DIR}/wg0.conf"
echo "  Clients: ${WG_DIR}/clients/"
echo ""
print_info "To add more clients later, edit ${WG_DIR}/wg0.conf and restart the service"
echo ""
print_warning "IMPORTANT: Keep your private keys secure!"
echo "=========================================="
