#!/bin/bash

# WireGuard VPN Server Setup Script for Ubuntu
# This script automates the installation and configuration of WireGuard

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Configuration variables
SERVER_WG_IP="10.0.0.1/24"
SERVER_PORT="444"
SERVER_INTERFACE="wg0"
WG_CONFIG_DIR="/etc/wireguard"
CLIENT_COUNT=1

# Detect the main network interface
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
print_message "Detected main network interface: $MAIN_INTERFACE"

# Step 1: Update system and install WireGuard
print_message "Updating system packages..."
apt update

print_message "Installing WireGuard and QR code generator..."
apt install -y wireguard wireguard-tools qrencode

# Step 2: Enable IP forwarding
print_message "Enabling IP forwarding..."
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
sysctl -p

# Step 3: Generate server keys
print_message "Generating WireGuard server keys..."
cd $WG_CONFIG_DIR
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key
SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)

print_message "Server public key: $SERVER_PUBLIC_KEY"

# Step 4: Create server configuration
print_message "Creating WireGuard server configuration..."
cat > $WG_CONFIG_DIR/$SERVER_INTERFACE.conf << EOF
[Interface]
Address = $SERVER_WG_IP
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE

EOF

# Step 5: Generate client configurations
print_message "Generating client configuration(s)..."
mkdir -p $WG_CONFIG_DIR/clients

for i in $(seq 1 $CLIENT_COUNT); do
    CLIENT_NAME="client$i"
    CLIENT_IP="10.0.0.$((i+1))/32"
    
    # Generate client keys
    wg genkey | tee $WG_CONFIG_DIR/clients/${CLIENT_NAME}_private.key | wg pubkey > $WG_CONFIG_DIR/clients/${CLIENT_NAME}_public.key
    CLIENT_PRIVATE_KEY=$(cat $WG_CONFIG_DIR/clients/${CLIENT_NAME}_private.key)
    CLIENT_PUBLIC_KEY=$(cat $WG_CONFIG_DIR/clients/${CLIENT_NAME}_public.key)
    
    # Add peer to server config
    cat >> $WG_CONFIG_DIR/$SERVER_INTERFACE.conf << EOF
# Client: $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP

EOF
    
    # Create client configuration file
    cat > $WG_CONFIG_DIR/clients/${CLIENT_NAME}.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = ${CLIENT_IP%/*}/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $(curl -s ifconfig.me):$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    
    print_message "Client configuration created: $WG_CONFIG_DIR/clients/${CLIENT_NAME}.conf"
    
    # Generate QR code
    print_message "Generating QR code for ${CLIENT_NAME}..."
    qrencode -t ansiutf8 < $WG_CONFIG_DIR/clients/${CLIENT_NAME}.conf > $WG_CONFIG_DIR/clients/${CLIENT_NAME}_qr.txt
    qrencode -t PNG -o $WG_CONFIG_DIR/clients/${CLIENT_NAME}_qr.png < $WG_CONFIG_DIR/clients/${CLIENT_NAME}.conf
done

# Step 6: Set proper permissions
chmod 600 $WG_CONFIG_DIR/$SERVER_INTERFACE.conf
chmod 600 $WG_CONFIG_DIR/*.key
chmod 600 $WG_CONFIG_DIR/clients/*

# Step 7: Configure firewall (UFW if available)
if command -v ufw &> /dev/null; then
    print_message "Configuring UFW firewall..."
    ufw allow $SERVER_PORT/udp
    ufw default allow routed
    ufw --force enable
    ufw reload
else
    print_warning "UFW not found. Please configure your firewall manually to allow UDP port $SERVER_PORT"
fi

# Step 8: Enable and start WireGuard
print_message "Enabling and starting WireGuard service..."
systemctl enable wg-quick@$SERVER_INTERFACE
systemctl start wg-quick@$SERVER_INTERFACE

# Step 9: Display status
print_message "WireGuard setup completed successfully!"
echo ""
print_message "Server Status:"
wg show

echo ""
print_message "=== Setup Summary ==="
echo "Server Interface: $SERVER_INTERFACE"
echo "Server IP: $SERVER_WG_IP"
echo "Server Port: $SERVER_PORT"
echo "Server Public Key: $SERVER_PUBLIC_KEY"
echo ""
echo "Client configurations are located in: $WG_CONFIG_DIR/clients/"
echo ""
print_message "To view client configs, use: cat $WG_CONFIG_DIR/clients/client1.conf"
print_message "To view QR code in terminal: cat $WG_CONFIG_DIR/clients/client1_qr.txt"
print_message "QR code PNG file: $WG_CONFIG_DIR/clients/client1_qr.png"
echo ""
print_message "Displaying QR code for client1:"
cat $WG_CONFIG_DIR/clients/client1_qr.txt
echo ""
print_message "To add more clients later, run:"
echo "  sudo wg genkey | tee /etc/wireguard/clients/newclient_private.key | wg pubkey > /etc/wireguard/clients/newclient_public.key"
echo ""
print_message "To check WireGuard status: sudo wg show"
print_message "To restart WireGuard: sudo systemctl restart wg-quick@$SERVER_INTERFACE"
