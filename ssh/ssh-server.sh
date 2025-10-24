#!/bin/bash

set -e

echo "=== SSH Server Setup for Ubuntu ==="

# Update package list
echo "Updating package list..."
sudo apt update

# Install OpenSSH server if not already installed
if ! command -v sshd &> /dev/null; then
    echo "Installing OpenSSH server..."
    sudo apt install -y openssh-server
else
    echo "OpenSSH server is already installed"
fi

# Backup original sshd_config
if [ ! -f /etc/ssh/sshd_config.backup ]; then
    echo "Backing up original sshd_config..."
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
fi

# Configure SSH daemon for security
echo "Configuring SSH daemon..."

# Create a temporary config file
TEMP_CONFIG=$(mktemp)

cat > "$TEMP_CONFIG" << 'EOF'
# SSH Server Configuration - Security Hardened

# Port and Protocol
Port 22
Protocol 2

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Key-based authentication
AuthorizedKeysFile .ssh/authorized_keys

# Disable unused authentication methods
KerberosAuthentication no
GSSAPIAuthentication no

# Security settings
X11Forwarding no
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 60

# Client alive settings (keep connection alive)
ClientAliveInterval 300
ClientAliveCountMax 2

# Logging
SyslogFacility AUTH
LogLevel INFO

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server

# Accept locale environment
AcceptEnv LANG LC_*

# Override for specific users (if needed)
# Match User username
#     PasswordAuthentication yes
EOF

# Apply the configuration
sudo cp "$TEMP_CONFIG" /etc/ssh/sshd_config
rm "$TEMP_CONFIG"

# Set proper permissions
sudo chmod 644 /etc/ssh/sshd_config

# Validate SSH configuration
echo "Validating SSH configuration..."
if sudo sshd -t; then
    echo "SSH configuration is valid"
else
    echo "ERROR: SSH configuration is invalid. Restoring backup..."
    sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
    exit 1
fi

# Enable and start SSH service
echo "Enabling SSH service..."
sudo systemctl enable ssh

echo "Restarting SSH service..."
sudo systemctl restart ssh

# Check SSH service status
echo "Checking SSH service status..."
sudo systemctl status ssh --no-pager

# Configure firewall if UFW is installed
if command -v ufw &> /dev/null; then
    echo "Configuring UFW firewall..."
    sudo ufw allow 22/tcp
    echo "SSH port 22 allowed in UFW"
fi

# Create .ssh directory for current user if it doesn't exist
if [ ! -d "$HOME/.ssh" ]; then
    echo "Creating .ssh directory..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
fi

# Create authorized_keys file if it doesn't exist
if [ ! -f "$HOME/.ssh/authorized_keys" ]; then
    echo "Creating authorized_keys file..."
    touch "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
fi

echo ""
echo "=== SSH Setup Complete ==="
echo ""
echo "IMPORTANT NOTES:"
echo "1. Root login is DISABLED"
echo "2. Password authentication is DISABLED"
echo "3. Only key-based authentication is allowed"
echo ""
echo "NEXT STEPS:"
echo "1. Add your public key to ~/.ssh/authorized_keys"
echo "   Example: echo 'your-public-key' >> ~/.ssh/authorized_keys"
echo "2. Test SSH connection from another terminal BEFORE closing this session"
echo "3. If you need password auth for specific users, edit /etc/ssh/sshd_config"
echo ""
echo "Configuration backup saved at: /etc/ssh/sshd_config.backup"
echo ""
