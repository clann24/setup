#!/bin/bash
#
# Reverse SSH Tunnel Setup
# Creates a persistent reverse tunnel to remote server ubuntu@43.165.184.25
# This allows the remote server to access your local WSL2 SSH server
#
# Usage: ./reverse_tunnel_setup.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REMOTE_USER="ubuntu"
REMOTE_HOST="43.165.184.25"
REMOTE_PORT="2222"  # Port on remote server that will forward to your local SSH
LOCAL_SSH_PORT="22"  # Your local SSH port

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

# Check if SSH key exists
check_ssh_key() {
    log_info "Checking SSH key..."
    
    if [ -f ~/.ssh/id_rsa ] || [ -f ~/.ssh/id_ed25519 ]; then
        log_success "SSH key found"
        return 0
    else
        log_warning "No SSH key found. Generating one..."
        ssh-keygen -t ed25519 -C "wsl2-reverse-tunnel" -f ~/.ssh/id_ed25519 -N ""
        log_success "SSH key generated at ~/.ssh/id_ed25519"
    fi
}

# Copy SSH key to remote server
copy_ssh_key() {
    log_info "Copying SSH key to remote server..."
    log_info "You will be prompted for the remote server password"
    echo ""
    
    if [ -f ~/.ssh/id_ed25519.pub ]; then
        ssh-copy-id -i ~/.ssh/id_ed25519.pub ${REMOTE_USER}@${REMOTE_HOST}
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        ssh-copy-id -i ~/.ssh/id_rsa.pub ${REMOTE_USER}@${REMOTE_HOST}
    else
        log_error "No public key found"
        exit 1
    fi
    
    log_success "SSH key copied to remote server"
}

# Test connection to remote server
test_remote_connection() {
    log_info "Testing connection to remote server..."
    
    if ssh -o ConnectTimeout=5 -o BatchMode=yes ${REMOTE_USER}@${REMOTE_HOST} "echo 'Connection successful'" 2>/dev/null; then
        log_success "Successfully connected to ${REMOTE_USER}@${REMOTE_HOST}"
        return 0
    else
        log_error "Cannot connect to remote server"
        log_error "Please ensure:"
        log_error "  1. Remote server is accessible"
        log_error "  2. SSH key is copied (run: ssh-copy-id ${REMOTE_USER}@${REMOTE_HOST})"
        log_error "  3. Firewall allows SSH connections"
        exit 1
    fi
}

# Create systemd service for persistent tunnel
create_systemd_service() {
    log_info "Creating systemd service for persistent reverse tunnel..."
    
    SERVICE_FILE="/etc/systemd/system/reverse-ssh-tunnel.service"
    
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Reverse SSH Tunnel to ${REMOTE_HOST}
After=network.target

[Service]
Type=simple
User=${USER}
ExecStart=/usr/bin/ssh -N -T -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=no -R ${REMOTE_PORT}:localhost:${LOCAL_SSH_PORT} ${REMOTE_USER}@${REMOTE_HOST}
Restart=always
RestartSec=10
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF
    
    log_success "Systemd service created at $SERVICE_FILE"
}

# Create manual tunnel script
create_manual_script() {
    log_info "Creating manual tunnel script..."
    
    SCRIPT_FILE="$HOME/start-reverse-tunnel.sh"
    
    cat > "$SCRIPT_FILE" <<EOF
#!/bin/bash
#
# Manual Reverse SSH Tunnel Script
# Connects to ${REMOTE_USER}@${REMOTE_HOST}
#

echo "Starting reverse SSH tunnel..."
echo "Remote server: ${REMOTE_HOST}"
echo "Remote port: ${REMOTE_PORT} -> Local port: ${LOCAL_SSH_PORT}"
echo ""
echo "On the remote server, connect back with:"
echo "  ssh -p ${REMOTE_PORT} ${USER}@localhost"
echo ""
echo "Press Ctrl+C to stop the tunnel"
echo ""

ssh -v -N -T -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes -R ${REMOTE_PORT}:localhost:${LOCAL_SSH_PORT} ${REMOTE_USER}@${REMOTE_HOST}
EOF
    
    chmod +x "$SCRIPT_FILE"
    log_success "Manual tunnel script created at $SCRIPT_FILE"
}

# Create connection helper script for remote server
create_remote_helper() {
    log_info "Creating remote connection helper..."
    
    HELPER_FILE="$HOME/connect-from-remote.txt"
    
    cat > "$HELPER_FILE" <<EOF
# Reverse SSH Tunnel - Connection Instructions
# ============================================

## On Remote Server (${REMOTE_HOST})

Once the reverse tunnel is established, connect back to your WSL2 machine:

### Connect to WSL2 from remote server:
ssh -p ${REMOTE_PORT} ${USER}@localhost

### Check if tunnel is active:
ss -tlnp | grep ${REMOTE_PORT}
netstat -tlnp | grep ${REMOTE_PORT}

### Check SSH connections:
ps aux | grep ssh

## Architecture

┌─────────────────────────────────────────────────────────────┐
│ Your WSL2 Machine                                            │
│  - Initiates reverse tunnel                                  │
│  - SSH server on port ${LOCAL_SSH_PORT}                                     │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Reverse Tunnel
                         │ (initiated from WSL2)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ Remote Server (${REMOTE_HOST})                        │
│  - Listens on port ${REMOTE_PORT}                                    │
│  - Forwards to WSL2:${LOCAL_SSH_PORT}                                      │
│  - Connect with: ssh -p ${REMOTE_PORT} ${USER}@localhost              │
└─────────────────────────────────────────────────────────────┘

## Troubleshooting

### If tunnel disconnects:
sudo systemctl restart reverse-ssh-tunnel

### View tunnel logs:
sudo journalctl -u reverse-ssh-tunnel -f

### Test tunnel manually:
~/start-reverse-tunnel.sh

### Check tunnel status:
sudo systemctl status reverse-ssh-tunnel
EOF
    
    log_success "Remote helper created at $HELPER_FILE"
}

# Enable and start service
enable_service() {
    log_info "Enabling and starting reverse tunnel service..."
    
    sudo systemctl daemon-reload
    sudo systemctl enable reverse-ssh-tunnel.service
    sudo systemctl start reverse-ssh-tunnel.service
    
    sleep 2
    
    if sudo systemctl is-active --quiet reverse-ssh-tunnel.service; then
        log_success "Reverse tunnel service is running"
    else
        log_error "Failed to start service"
        sudo systemctl status reverse-ssh-tunnel.service
        exit 1
    fi
}

# Show status and instructions
show_status() {
    echo ""
    log_success "=== Reverse SSH Tunnel Setup Complete ==="
    echo ""
    
    log_info "Configuration:"
    echo "  • Remote server: ${REMOTE_USER}@${REMOTE_HOST}"
    echo "  • Remote port: ${REMOTE_PORT}"
    echo "  • Local SSH port: ${LOCAL_SSH_PORT}"
    echo ""
    
    log_info "Service Status:"
    sudo systemctl status reverse-ssh-tunnel.service --no-pager | head -10
    echo ""
    
    log_info "On the remote server (${REMOTE_HOST}), connect back with:"
    echo "  ${GREEN}ssh -p ${REMOTE_PORT} ${USER}@localhost${NC}"
    echo ""
    
    log_info "Useful commands:"
    echo "  • Check status:    sudo systemctl status reverse-ssh-tunnel"
    echo "  • View logs:       sudo journalctl -u reverse-ssh-tunnel -f"
    echo "  • Restart tunnel:  sudo systemctl restart reverse-ssh-tunnel"
    echo "  • Stop tunnel:     sudo systemctl stop reverse-ssh-tunnel"
    echo "  • Manual tunnel:   ~/start-reverse-tunnel.sh"
    echo ""
    
    log_info "Files created:"
    echo "  • Service:         /etc/systemd/system/reverse-ssh-tunnel.service"
    echo "  • Manual script:   ~/start-reverse-tunnel.sh"
    echo "  • Instructions:    ~/connect-from-remote.txt"
    echo ""
}

# Configure remote server
configure_remote_server() {
    log_info "Configuring remote server SSH settings..."
    
    log_info "Checking if GatewayPorts is enabled on remote server..."
    
    # Check and enable GatewayPorts on remote server
    ssh ${REMOTE_USER}@${REMOTE_HOST} "sudo bash -c '
        if ! grep -q \"^GatewayPorts\" /etc/ssh/sshd_config; then
            echo \"GatewayPorts yes\" | sudo tee -a /etc/ssh/sshd_config
            echo \"Added GatewayPorts yes to sshd_config\"
            sudo systemctl restart sshd || sudo service ssh restart
            echo \"SSH service restarted\"
        else
            echo \"GatewayPorts already configured\"
        fi
    '"
    
    log_success "Remote server configured"
}

# Main execution
main() {
    echo ""
    log_info "Reverse SSH Tunnel Setup"
    log_info "Remote: ${REMOTE_USER}@${REMOTE_HOST}"
    echo ""
    
    check_ssh_key
    
    echo ""
    log_info "Testing connection to remote server..."
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes ${REMOTE_USER}@${REMOTE_HOST} "echo 'test'" &>/dev/null; then
        log_warning "Cannot connect with SSH key. Need to copy SSH key first."
        copy_ssh_key
    else
        log_success "SSH key authentication working"
    fi
    
    test_remote_connection
    
    echo ""
    read -p "Configure remote server GatewayPorts? (recommended) (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        configure_remote_server
    fi
    
    echo ""
    create_systemd_service
    create_manual_script
    create_remote_helper
    
    echo ""
    read -p "Enable and start the tunnel service now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        enable_service
    else
        log_info "Service created but not started"
        log_info "Start manually with: sudo systemctl start reverse-ssh-tunnel"
    fi
    
    show_status
    
    echo ""
    log_info "Next steps:"
    echo "  1. SSH to remote server: ssh ${REMOTE_USER}@${REMOTE_HOST}"
    echo "  2. From remote server, connect back: ssh -p ${REMOTE_PORT} ${USER}@localhost"
    echo "  3. View instructions: cat ~/connect-from-remote.txt"
    echo ""
}

# Run main function
main "$@"
