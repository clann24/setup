# Reverse SSH Tunnel Setup Guide

Complete guide for setting up a persistent reverse SSH tunnel from your WSL2 machine to remote server `ubuntu@43.165.184.25`.

## What is Reverse SSH Tunneling?

Reverse SSH tunneling allows a remote server to access your local machine through an SSH connection initiated **from your local machine**. This is useful when:
- Your local machine is behind NAT/firewall
- You want remote access without exposing ports publicly
- You need to access your WSL2 from a remote server

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Your WSL2 Machine (Local)                                    │
│  - SSH Server on port 22                                     │
│  - Initiates reverse tunnel connection                       │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ Reverse Tunnel (initiated from WSL2)
                         │ ssh -R 2222:localhost:22
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ Remote Server: ubuntu@43.165.184.25                          │
│  - Port 2222 forwards to your WSL2:22                        │
│  - Connect back: ssh -p 2222 <user>@localhost                │
└─────────────────────────────────────────────────────────────┘
```

## Quick Setup

### Automated Setup

```bash
# Make script executable
chmod +x ~/code/reverse_tunnel_setup.sh

# Run the setup
./reverse_tunnel_setup.sh
```

The script will:
1. ✓ Check/generate SSH keys
2. ✓ Copy SSH key to remote server
3. ✓ Test connection
4. ✓ Configure remote server (GatewayPorts)
5. ✓ Create systemd service for persistent tunnel
6. ✓ Create manual tunnel script
7. ✓ Start the tunnel

## Manual Setup

### Step 1: Generate SSH Key (if needed)

```bash
# Generate ED25519 key (recommended)
ssh-keygen -t ed25519 -C "wsl2-reverse-tunnel" -f ~/.ssh/id_ed25519

# Or RSA key
ssh-keygen -t rsa -b 4096 -C "wsl2-reverse-tunnel" -f ~/.ssh/id_rsa
```

### Step 2: Copy SSH Key to Remote Server

```bash
# Copy public key to remote server
ssh-copy-id ubuntu@43.165.184.25

# Or manually
cat ~/.ssh/id_ed25519.pub | ssh ubuntu@43.165.184.25 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

### Step 3: Test Connection

```bash
# Test SSH connection
ssh ubuntu@43.165.184.25 "echo 'Connection successful'"
```

### Step 4: Configure Remote Server

On the remote server, enable `GatewayPorts` to allow port forwarding:

```bash
# SSH to remote server
ssh ubuntu@43.165.184.25

# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Add or uncomment this line:
GatewayPorts yes

# Restart SSH service
sudo systemctl restart sshd
# or
sudo service ssh restart

# Exit remote server
exit
```

### Step 5: Create Systemd Service (Persistent Tunnel)

Create `/etc/systemd/system/reverse-ssh-tunnel.service`:

```bash
sudo nano /etc/systemd/system/reverse-ssh-tunnel.service
```

Add this content:

```ini
[Unit]
Description=Reverse SSH Tunnel to 43.165.184.25
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
ExecStart=/usr/bin/ssh -N -T -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=no -R 2222:localhost:22 ubuntu@43.165.184.25
Restart=always
RestartSec=10
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
```

Replace `YOUR_USERNAME` with your WSL2 username.

### Step 6: Enable and Start Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service (start on boot)
sudo systemctl enable reverse-ssh-tunnel.service

# Start service
sudo systemctl start reverse-ssh-tunnel.service

# Check status
sudo systemctl status reverse-ssh-tunnel.service
```

## Usage

### From Remote Server

Once the tunnel is established, SSH to the remote server and connect back:

```bash
# SSH to remote server
ssh ubuntu@43.165.184.25

# From remote server, connect to your WSL2
ssh -p 2222 YOUR_USERNAME@localhost
```

### Manual Tunnel (Without Systemd)

If you prefer to run the tunnel manually:

```bash
# Run manual script
~/start-reverse-tunnel.sh

# Or directly
ssh -N -T -o ServerAliveInterval=60 -R 2222:localhost:22 ubuntu@43.165.184.25
```

**Explanation of SSH options:**
- `-N` - No command execution (just forwarding)
- `-T` - Disable pseudo-terminal allocation
- `-R 2222:localhost:22` - Remote port 2222 forwards to local port 22
- `-o ServerAliveInterval=60` - Keep connection alive
- `-o ExitOnForwardFailure=yes` - Exit if port forwarding fails
- `-o StrictHostKeyChecking=no` - Auto-accept host key (optional)

## Verification

### Check Tunnel Status (Local)

```bash
# Check systemd service
sudo systemctl status reverse-ssh-tunnel

# View logs
sudo journalctl -u reverse-ssh-tunnel -f

# Check SSH processes
ps aux | grep "ssh.*43.165.184.25"
```

### Check Tunnel Status (Remote)

```bash
# SSH to remote server
ssh ubuntu@43.165.184.25

# Check if port 2222 is listening
ss -tlnp | grep 2222
# or
netstat -tlnp | grep 2222

# Should show:
# tcp   LISTEN   0   128   127.0.0.1:2222   0.0.0.0:*
```

### Test Connection

```bash
# From remote server
ssh -p 2222 YOUR_USERNAME@localhost

# Should connect to your WSL2 machine
```

## Management Commands

### Service Control

```bash
# Start tunnel
sudo systemctl start reverse-ssh-tunnel

# Stop tunnel
sudo systemctl stop reverse-ssh-tunnel

# Restart tunnel
sudo systemctl restart reverse-ssh-tunnel

# Check status
sudo systemctl status reverse-ssh-tunnel

# Enable auto-start on boot
sudo systemctl enable reverse-ssh-tunnel

# Disable auto-start
sudo systemctl disable reverse-ssh-tunnel
```

### View Logs

```bash
# Follow logs in real-time
sudo journalctl -u reverse-ssh-tunnel -f

# View last 50 lines
sudo journalctl -u reverse-ssh-tunnel -n 50

# View logs since today
sudo journalctl -u reverse-ssh-tunnel --since today
```

## Troubleshooting

### Issue: Connection Refused

**Symptoms:** Cannot establish tunnel

**Solutions:**

1. **Check SSH key authentication:**
   ```bash
   ssh ubuntu@43.165.184.25 "echo test"
   ```

2. **Check remote server is accessible:**
   ```bash
   ping 43.165.184.25
   nc -zv 43.165.184.25 22
   ```

3. **Check firewall on remote server:**
   ```bash
   ssh ubuntu@43.165.184.25 "sudo ufw status"
   ```

### Issue: Port Already in Use

**Symptoms:** `bind: Address already in use`

**Solutions:**

1. **Check what's using port 2222 on remote server:**
   ```bash
   ssh ubuntu@43.165.184.25 "ss -tlnp | grep 2222"
   ```

2. **Kill existing SSH tunnel:**
   ```bash
   ssh ubuntu@43.165.184.25 "pkill -f 'ssh.*2222'"
   ```

3. **Use a different port:**
   Edit the service file and change `2222` to another port (e.g., `2223`)

### Issue: Tunnel Keeps Disconnecting

**Symptoms:** Service restarts frequently

**Solutions:**

1. **Check logs:**
   ```bash
   sudo journalctl -u reverse-ssh-tunnel -n 100
   ```

2. **Increase ServerAliveInterval:**
   Edit service file and add:
   ```
   -o ServerAliveInterval=30 -o ServerAliveCountMax=3
   ```

3. **Check network stability:**
   ```bash
   ping -c 100 43.165.184.25
   ```

### Issue: Cannot Connect from Remote Server

**Symptoms:** `ssh -p 2222 user@localhost` fails on remote server

**Solutions:**

1. **Verify GatewayPorts is enabled:**
   ```bash
   ssh ubuntu@43.165.184.25 "grep GatewayPorts /etc/ssh/sshd_config"
   # Should show: GatewayPorts yes
   ```

2. **Check tunnel is active:**
   ```bash
   ssh ubuntu@43.165.184.25 "ss -tlnp | grep 2222"
   ```

3. **Check local SSH server is running:**
   ```bash
   sudo service ssh status
   ```

### Issue: Permission Denied (publickey)

**Symptoms:** SSH key authentication fails

**Solutions:**

1. **Verify SSH key is copied:**
   ```bash
   ssh ubuntu@43.165.184.25 "cat ~/.ssh/authorized_keys"
   ```

2. **Check key permissions:**
   ```bash
   chmod 600 ~/.ssh/id_ed25519
   chmod 644 ~/.ssh/id_ed25519.pub
   chmod 700 ~/.ssh
   ```

3. **Re-copy SSH key:**
   ```bash
   ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@43.165.184.25
   ```

## Security Considerations

### Best Practices

1. **Use SSH keys only** (disable password authentication)
2. **Use strong SSH key:** ED25519 or RSA 4096-bit
3. **Limit port forwarding** on remote server
4. **Use firewall rules** to restrict access
5. **Monitor tunnel logs** regularly

### Disable Password Authentication

On your WSL2 machine:

```bash
sudo nano /etc/ssh/sshd_config

# Set:
PasswordAuthentication no
PubkeyAuthentication yes

# Restart SSH
sudo service ssh restart
```

### Restrict Remote Access

On remote server, limit who can use the forwarded port:

```bash
# In /etc/ssh/sshd_config
GatewayPorts clientspecified

# Then use:
ssh -R 127.0.0.1:2222:localhost:22 ubuntu@43.165.184.25
```

This binds the forwarded port only to localhost on the remote server.

## Advanced Configuration

### Multiple Tunnels

Forward multiple ports:

```bash
ssh -N -T \
  -R 2222:localhost:22 \
  -R 8080:localhost:80 \
  -R 3306:localhost:3306 \
  ubuntu@43.165.184.25
```

### Dynamic Port Forwarding

Create a SOCKS proxy:

```bash
ssh -N -T -D 1080 ubuntu@43.165.184.25
```

### SSH Config File

Add to `~/.ssh/config`:

```
Host remote-tunnel
    HostName 43.165.184.25
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3
    RemoteForward 2222 localhost:22
```

Then simply run:
```bash
ssh -N -T remote-tunnel
```

## Files and Locations

| File | Purpose |
|------|---------|
| `/etc/systemd/system/reverse-ssh-tunnel.service` | Systemd service definition |
| `~/start-reverse-tunnel.sh` | Manual tunnel script |
| `~/connect-from-remote.txt` | Connection instructions |
| `~/.ssh/id_ed25519` | Private SSH key |
| `~/.ssh/id_ed25519.pub` | Public SSH key |
| `/etc/ssh/sshd_config` | SSH server configuration |

## Summary

### Setup Steps
1. Generate SSH key
2. Copy key to remote server
3. Configure remote server (GatewayPorts)
4. Create systemd service
5. Start tunnel service

### Connection Flow
```
WSL2 → Reverse Tunnel → Remote Server (port 2222) → Back to WSL2 (port 22)
```

### Key Commands
```bash
# Start tunnel
sudo systemctl start reverse-ssh-tunnel

# Connect from remote
ssh -p 2222 YOUR_USERNAME@localhost

# Check status
sudo systemctl status reverse-ssh-tunnel
```

---

**Remote Server:** ubuntu@43.165.184.25  
**Tunnel Port:** 2222  
**Local SSH Port:** 22  

**Last Updated:** October 2025
