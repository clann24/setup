# Docker Proxy Setup Guide for WSL2

Complete guide for configuring Docker in WSL2 Ubuntu to use a Windows host SOCKS5 proxy.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Part 1: Windows Configuration](#part-1-windows-configuration)
- [Part 2: WSL2 Configuration](#part-2-wsl2-configuration)
- [Automated Setup](#automated-setup)
- [Manual Setup](#manual-setup)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [Uninstall](#uninstall)

---

## Overview

This guide configures Docker in WSL2 to route all traffic through a Windows SOCKS5 proxy. Since Docker doesn't support SOCKS5 directly, we use **Privoxy** as an HTTP-to-SOCKS5 bridge.

### Why This Setup?

- **Docker limitation**: Docker daemon only supports HTTP/HTTPS proxies
- **Your proxy**: Provides SOCKS5 (common in Clash, v2rayN, etc.)
- **Solution**: Privoxy bridges HTTP requests to SOCKS5

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Windows Host                                                 │
│  ┌────────────────────────────────────────────────────┐     │
│  │ Proxy Client (Clash/v2rayN/NekoRay/etc.)          │     │
│  │ SOCKS5: 0.0.0.0:1080 (Allow LAN enabled)          │     │
│  │ HTTP:   0.0.0.0:7890 (optional)                   │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │ SOCKS5
                            │
┌─────────────────────────────────────────────────────────────┐
│ WSL2 Ubuntu                                                  │
│                                                              │
│  ┌──────────────────────────────────────────────────┐       │
│  │ Privoxy (HTTP→SOCKS5 bridge)                     │       │
│  │ Listen: 127.0.0.1:8118                           │       │
│  │ Forward to: 127.0.0.1:1080                       │       │
│  └──────────────────────────────────────────────────┘       │
│                    ▲                                         │
│                    │ HTTP                                    │
│  ┌──────────────────────────────────────────────────┐       │
│  │ Docker Daemon                                     │       │
│  │ HTTP_PROXY=http://127.0.0.1:8118                │       │
│  │ HTTPS_PROXY=http://127.0.0.1:8118               │       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
│  Shell/Git: SOCKS5 127.0.0.1:1080 (direct)                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Windows
- Proxy client installed (Clash, v2rayN, NekoRay, etc.)
- SOCKS5 proxy configured and running

### WSL2 Ubuntu
- WSL2 with Ubuntu 20.04+ installed
- Docker installed
- Root/sudo access
- Basic networking tools (nc, curl)

---

## Part 1: Windows Configuration

### Step 1: Enable "Allow LAN" in Your Proxy Client

Your proxy must listen on `0.0.0.0` (all interfaces) to be accessible from WSL2.

#### Clash / Clash for Windows / Clash Verge

1. Open Clash client
2. Go to **Settings** → **General** (or **Proxy**)
3. Enable **"Allow LAN"**
4. Set **Bind Address** to `0.0.0.0`
5. Note the ports:
   - **SOCKS5**: Usually `1080`
   - **HTTP**: Usually `7890` (optional but recommended)
6. Click **Apply** or **Save**

#### v2rayN

1. Right-click tray icon → **HTTP/Socks Settings**
2. Check **Enable** for SOCKS5
3. Set **Listen IP**: `0.0.0.0`
4. Set **Port**: `1080`
5. Click **OK**

#### NekoRay / NekoBox

1. Open **Settings** → **Inbound/Proxy**
2. Add/enable **SOCKS5 inbound**
3. Set **Listen**: `0.0.0.0`
4. Set **Port**: `1080`
5. Apply changes

#### Mihomo (Clash Meta)

1. Edit config file or use GUI
2. Set in `mixed-port` or separate ports:
   ```yaml
   mixed-port: 7890
   socks-port: 1080
   allow-lan: true
   bind-address: '0.0.0.0'
   ```
3. Restart Mihomo

### Step 2: Configure Windows Firewall

Allow WSL2 to access the proxy port:

#### Method 1: Windows Defender Firewall GUI

1. Open **Windows Defender Firewall with Advanced Security**
2. Click **Inbound Rules** → **New Rule**
3. Select **Port** → **Next**
4. Select **TCP**, enter port `1080` → **Next**
5. Select **Allow the connection** → **Next**
6. Check **Private** (and **Domain** if needed) → **Next**
7. Name it: `WSL2 SOCKS5 Proxy` → **Finish**

#### Method 2: PowerShell (Run as Administrator)

```powershell
# Allow SOCKS5 port 1080
New-NetFirewallRule -DisplayName "WSL2 SOCKS5 Proxy" -Direction Inbound -LocalPort 1080 -Protocol TCP -Action Allow -Profile Private

# If using HTTP port 7890
New-NetFirewallRule -DisplayName "WSL2 HTTP Proxy" -Direction Inbound -LocalPort 7890 -Protocol TCP -Action Allow -Profile Private
```

### Step 3: Verify Proxy is Running

In PowerShell:

```powershell
# Check if proxy is listening
netstat -an | findstr "1080"

# Should show something like:
# TCP    0.0.0.0:1080           0.0.0.0:0              LISTENING
```

---

## Part 2: WSL2 Configuration

### Automated Setup (Recommended)

Use the provided script for one-command setup:

```bash
# Download or use the script
cd ~/code
sudo ./docker_proxy_wsl.sh

# Or with custom SOCKS5 port
sudo ./docker_proxy_wsl.sh 1080
```

The script will:
- Test SOCKS5 connectivity
- Install and configure Privoxy
- Configure Docker daemon proxy
- Disable IPv6 (prevents proxy bypass)
- Verify the entire setup

**Skip to [Verification](#verification) section after running the script.**

---

### Manual Setup

If you prefer manual configuration or need to understand each step:

#### Step 1: Test SOCKS5 Connectivity from WSL2

```bash
# Test connection to Windows SOCKS5
nc -vz 127.0.0.1 1080

# Expected output:
# Connection to 127.0.0.1 1080 port [tcp/socks] succeeded!
```

If this fails:
- Ensure "Allow LAN" is enabled in Windows proxy client
- Check Windows Firewall rules
- Verify proxy is running on Windows

#### Step 2: Install Privoxy

```bash
sudo apt-get update
sudo apt-get install -y privoxy
```

#### Step 3: Configure Privoxy

```bash
# Backup original config
sudo cp /etc/privoxy/config /etc/privoxy/config.bak

# Remove any existing forward rules
sudo sed -i '/^forward-socks5/d' /etc/privoxy/config

# Add SOCKS5 forwarding to Windows proxy
echo 'forward-socks5t / 127.0.0.1:1080 .' | sudo tee -a /etc/privoxy/config

# Verify listen address (should be 127.0.0.1:8118 by default)
grep "^listen-address" /etc/privoxy/config || echo "listen-address 127.0.0.1:8118" | sudo tee -a /etc/privoxy/config
```

**Configuration explained:**
- `forward-socks5t` - Forward using SOCKS5 with DNS through proxy (the "t" = target resolves DNS)
- `/` - For all requests
- `127.0.0.1:1080` - Your Windows SOCKS5 endpoint
- `.` - No parent HTTP proxy

#### Step 4: Start Privoxy

```bash
# Enable and start Privoxy
sudo systemctl enable privoxy
sudo systemctl restart privoxy

# Check status
systemctl status privoxy

# Verify it's listening
ss -ltnp | grep ':8118'
```

#### Step 5: Configure Docker Daemon Proxy

```bash
# Create systemd drop-in directory
sudo mkdir -p /etc/systemd/system/docker.service.d

# Create proxy configuration
sudo tee /etc/systemd/system/docker.service.d/proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:8118"
Environment="HTTPS_PROXY=http://127.0.0.1:8118"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
```

#### Step 6: Configure Docker Daemon Settings

```bash
# Backup existing daemon.json if it exists
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null || true

# Create daemon.json with IPv6 disabled and DNS servers
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "ipv6": false,
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
```

#### Step 7: Disable IPv6 (Critical!)

IPv6 must be disabled to prevent Docker from bypassing the proxy.

```bash
# Apply immediately
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# Make persistent across reboots
sudo tee -a /etc/sysctl.conf >/dev/null <<'EOF'

# Disable IPv6 for Docker proxy compatibility
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
```

#### Step 8: Configure IPv4 Preference

```bash
# Backup gai.conf
sudo cp /etc/gai.conf /etc/gai.conf.bak 2>/dev/null || true

# Add IPv4 preference
echo 'precedence ::ffff:0:0/96  100' | sudo tee -a /etc/gai.conf
```

#### Step 9: Restart Docker

```bash
# Reload systemd and restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# Check Docker status
systemctl status docker
```

---

## Verification

### 1. Check SOCKS5 Connectivity

```bash
nc -vz 127.0.0.1 1080
# Expected: Connection to 127.0.0.1 1080 port [tcp/socks] succeeded!
```

### 2. Check Privoxy

```bash
# Status
systemctl status privoxy

# Listening port
ss -ltnp | grep ':8118'

# Test with curl
http_proxy=http://127.0.0.1:8118 https_proxy=http://127.0.0.1:8118 curl -sS https://api.ipify.org
# Should return your proxy's public IP
```

### 3. Check Docker Proxy Configuration

```bash
# View Docker daemon environment
systemctl show docker --property=Environment

# Expected output includes:
# Environment=HTTP_PROXY=http://127.0.0.1:8118 HTTPS_PROXY=http://127.0.0.1:8118 NO_PROXY=localhost,127.0.0.1
```

### 4. Check IPv6 Status

```bash
sysctl net.ipv6.conf.all.disable_ipv6
# Expected: net.ipv6.conf.all.disable_ipv6 = 1
```

### 5. Test Docker Pull

```bash
# Simple test
docker pull hello-world
docker run --rm hello-world

# More comprehensive test
docker pull python:3.11-slim
```

### 6. Test Docker Compose Build

```bash
# In a project with Dockerfile
docker compose build
docker compose up
```

---

## Troubleshooting

### Issue: "Connection refused" to 127.0.0.1:1080

**Cause**: Windows proxy not accessible from WSL2

**Solutions**:
1. Verify "Allow LAN" is enabled in Windows proxy client
2. Check Windows Firewall allows port 1080
3. Restart Windows proxy client
4. Test from Windows PowerShell: `netstat -an | findstr "1080"`

### Issue: Docker pull times out with IPv6 address

**Cause**: IPv6 not fully disabled

**Solution**:
```bash
# Verify IPv6 is disabled
ip -6 addr show

# Should show minimal output. If not:
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sudo systemctl restart docker
```

### Issue: Privoxy returns "503 Forwarding failure"

**Cause**: Privoxy can't connect to SOCKS5

**Solution**:
```bash
# Test SOCKS5 directly
nc -vz 127.0.0.1 1080

# Check Privoxy config
grep "forward-socks5" /etc/privoxy/config

# Should show: forward-socks5t / 127.0.0.1:1080 .

# Restart Privoxy
sudo systemctl restart privoxy
```

### Issue: Docker works with `sudo` but not without

**Cause**: User not in docker group or group not applied

**Solution**:
```bash
# Add user to docker group (if not already)
sudo usermod -aG docker $USER

# Apply group in current shell
newgrp docker

# Or logout and login again
```

### Issue: "buildx isn't installed" warning

**Cause**: Docker Compose trying to use Bake with buildx

**Solution**: This is just a warning. Builds will work with classic builder. To suppress:
```bash
# Unset COMPOSE_EXPERIMENTAL_GIT_REMOTE if set
unset COMPOSE_EXPERIMENTAL_GIT_REMOTE

# Or install buildx (optional)
sudo apt-get install docker-buildx-plugin
```

### Issue: Proxy works but very slow

**Cause**: DNS resolution delays or proxy server issues

**Solutions**:
1. Check Windows proxy server performance
2. Try different DNS servers in `/etc/docker/daemon.json`:
   ```json
   {
     "ipv6": false,
     "dns": ["1.1.1.1", "1.0.0.1"]
   }
   ```
3. Restart Docker: `sudo systemctl restart docker`

### Issue: Works after setup but fails after WSL restart

**Cause**: Windows proxy not started or IPv6 re-enabled

**Solutions**:
1. Ensure Windows proxy client starts with Windows
2. Verify IPv6 settings persisted:
   ```bash
   sysctl net.ipv6.conf.all.disable_ipv6
   ```
3. Check Privoxy is running:
   ```bash
   systemctl status privoxy
   ```

---

## Maintenance

### View Logs

```bash
# Privoxy logs
sudo journalctl -u privoxy -f

# Docker logs
sudo journalctl -u docker -f

# Combined
sudo journalctl -u privoxy -u docker -f
```

### Restart Services

```bash
# Restart Privoxy
sudo systemctl restart privoxy

# Restart Docker
sudo systemctl restart docker

# Restart both
sudo systemctl restart privoxy docker
```

### Update Privoxy Configuration

```bash
# Edit config
sudo nano /etc/privoxy/config

# Change SOCKS5 port (example: 7891)
sudo sed -i 's/forward-socks5t \/ 127.0.0.1:[0-9]* \./forward-socks5t \/ 127.0.0.1:7891 ./' /etc/privoxy/config

# Restart
sudo systemctl restart privoxy
```

### Temporarily Disable Proxy

```bash
# Disable Docker proxy
sudo mv /etc/systemd/system/docker.service.d/proxy.conf \
        /etc/systemd/system/docker.service.d/proxy.conf.disabled
sudo systemctl daemon-reload
sudo systemctl restart docker

# Re-enable
sudo mv /etc/systemd/system/docker.service.d/proxy.conf.disabled \
        /etc/systemd/system/docker.service.d/proxy.conf
sudo systemctl daemon-reload
sudo systemctl restart docker
```

---

## Uninstall

### Remove Docker Proxy Configuration

```bash
# Remove Docker proxy config
sudo rm /etc/systemd/system/docker.service.d/proxy.conf
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### Remove Privoxy

```bash
# Stop and disable Privoxy
sudo systemctl stop privoxy
sudo systemctl disable privoxy

# Uninstall
sudo apt-get remove --purge privoxy

# Remove config
sudo rm -rf /etc/privoxy
```

### Re-enable IPv6 (Optional)

```bash
# Remove from sysctl.conf
sudo sed -i '/net.ipv6.conf.*disable_ipv6/d' /etc/sysctl.conf

# Enable immediately
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=0

# Restart Docker
sudo systemctl restart docker
```

### Restore Original Configs

```bash
# Restore Privoxy config (if you reinstall)
sudo cp /etc/privoxy/config.bak /etc/privoxy/config 2>/dev/null || true

# Restore Docker daemon.json
sudo cp /etc/docker/daemon.json.bak /etc/docker/daemon.json 2>/dev/null || true
sudo systemctl restart docker

# Restore gai.conf
sudo cp /etc/gai.conf.bak /etc/gai.conf 2>/dev/null || true
```

---

## Optional: Shell and Git Proxy

For non-Docker tools (curl, wget, git, etc.), you can use SOCKS5 directly:

### Shell Proxy (Temporary)

```bash
export ALL_PROXY="socks5h://127.0.0.1:1080"
export all_proxy="$ALL_PROXY"
```

### Shell Proxy (Persistent)

```bash
# Add to ~/.bashrc or ~/.zshrc
echo 'export ALL_PROXY="socks5h://127.0.0.1:1080"' >> ~/.bashrc
echo 'export all_proxy="$ALL_PROXY"' >> ~/.bashrc
source ~/.bashrc
```

### Git Proxy

```bash
# Configure git to use SOCKS5
git config --global http.proxy "socks5h://127.0.0.1:1080"
git config --global https.proxy "socks5h://127.0.0.1:1080"

# Verify
git config --global --get http.proxy

# Remove
git config --global --unset http.proxy
git config --global --unset https.proxy
```

---

## Files Modified

| File | Purpose | Backup Location |
|------|---------|----------------|
| `/etc/privoxy/config` | Privoxy SOCKS5 forwarding | `/etc/privoxy/config.bak` |
| `/etc/systemd/system/docker.service.d/proxy.conf` | Docker daemon proxy | N/A (new file) |
| `/etc/docker/daemon.json` | Docker daemon settings | `/etc/docker/daemon.json.bak` |
| `/etc/sysctl.conf` | IPv6 disable (persistent) | N/A (appended) |
| `/etc/gai.conf` | IPv4 DNS preference | `/etc/gai.conf.bak` |

---

## Quick Reference

### Check Status
```bash
# All services
systemctl status privoxy docker

# SOCKS5 connectivity
nc -vz 127.0.0.1 1080

# Privoxy listening
ss -ltnp | grep ':8118'

# Docker proxy env
systemctl show docker --property=Environment

# IPv6 status
sysctl net.ipv6.conf.all.disable_ipv6
```

### Test Proxy Chain
```bash
# Via Privoxy
http_proxy=http://127.0.0.1:8118 curl https://api.ipify.org

# Docker pull
docker pull hello-world

# Docker compose
docker compose build
```

### Restart Everything
```bash
sudo systemctl restart privoxy docker
```

---

## Common Proxy Ports

| Client | SOCKS5 | HTTP | Mixed |
|--------|--------|------|-------|
| Clash for Windows | 1080 | 7890 | - |
| v2rayN | 1080 | - | - |
| Mihomo (Meta) | 1080 | 7890 | 7890 |
| NekoRay | 1080 | - | - |
| Qv2ray | 1080 | 8080 | - |

---

## Additional Resources

- [Privoxy Documentation](https://www.privoxy.org/user-manual/)
- [Docker Daemon Proxy Configuration](https://docs.docker.com/config/daemon/systemd/#httphttps-proxy)
- [WSL2 Networking](https://docs.microsoft.com/en-us/windows/wsl/networking)

---

## License

This guide is provided as-is for educational purposes.

---

**Last Updated**: October 2025
