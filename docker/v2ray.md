# Docker Proxy Setup with v2rayN (Windows)

Complete guide for configuring Docker in WSL2 Ubuntu to use v2rayN HTTP proxy from Windows host.

## Table of Contents

- [Overview](#overview)
- [Why v2rayN?](#why-v2rayn)
- [Architecture](#architecture)
- [Part 1: Windows - v2rayN Setup](#part-1-windows---v2rayn-setup)
- [Part 2: WSL2 - Docker Configuration](#part-2-wsl2---docker-configuration)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

---

## Overview

This guide uses **v2rayN** on Windows to provide HTTP proxy directly to Docker in WSL2.

### Key Benefits

✓ **Simple setup** - Easy GUI configuration  
✓ **HTTP proxy built-in** - No additional tools needed  
✓ **Multiple protocols** - VMess, VLESS, Shadowsocks, Trojan, etc.  
✓ **Active development** - Regular updates and improvements  
✓ **Lightweight** - Low resource usage  

---

## Why v2rayN?

### Advantages

| Feature | v2rayN | Clash Verge | Shadowsocks |
|---------|--------|-------------|-------------|
| HTTP Proxy | ✓ Yes (10809) | ✓ Yes (7890) | ✗ No |
| SOCKS5 Proxy | ✓ Yes (10808) | ✓ Yes (1080) | ✓ Yes |
| VMess/VLESS | ✓ Yes | ✓ Yes | ✗ No |
| Shadowsocks | ✓ Yes | ✓ Yes | ✓ Yes |
| Trojan | ✓ Yes | ✓ Yes | ✗ No |
| GUI | Simple & Clean | Modern | Basic |
| Config Import | ✓ URL/QR/JSON | ✓ URL/YAML | ✓ URL |
| Rule-based routing | ✓ Yes | ✓ Yes | ✗ No |

### v2rayN Features

- **Built-in HTTP proxy**: Port 10809 by default
- **Built-in SOCKS5 proxy**: Port 10808 by default
- **Multiple protocol support**: VMess, VLESS, Shadowsocks, Trojan, etc.
- **Easy import**: Support vmess://, vless://, ss://, trojan:// URLs
- **Subscription support**: Auto-update server lists
- **Routing rules**: PAC, global, direct modes
- **Lightweight**: Based on v2ray-core/Xray-core

---

## Architecture

### v2rayN Setup

```
┌─────────────────────────────────────────────────────────────┐
│ Windows Host                                                 │
│  ┌────────────────────────────────────────────────────┐     │
│  │ v2rayN                                             │     │
│  │ HTTP:   127.0.0.1:10809 (default)                 │     │
│  │ SOCKS5: 127.0.0.1:10808 (default)                 │     │
│  │                                                     │     │
│  │ Settings → Allow LAN → 0.0.0.0:10809             │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTP (Direct!)
                            │
┌─────────────────────────────────────────────────────────────┐
│ WSL2 Ubuntu                                                  │
│                                                              │
│  ┌──────────────────────────────────────────────────┐       │
│  │ Docker Daemon                                     │       │
│  │ HTTP_PROXY=http://[WIN_IP]:10809                 │       │
│  │ HTTPS_PROXY=http://[WIN_IP]:10809               │       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Simple and efficient!**

---

## Part 1: Windows - v2rayN Setup

### Step 1: Download and Install v2rayN

**Download from**:
```
https://github.com/2dust/v2rayN/releases/latest
```

**Choose**:
- `v2rayN-windows-64.zip` - Portable version (recommended)
- Or `v2rayN-With-Core.zip` - Includes v2ray-core

**Install**:
1. Extract the ZIP file to a folder (e.g., `C:\Program Files\v2rayN`)
2. Run `v2rayN.exe`
3. The app will appear in system tray

### Step 2: Import Your Server Configuration

#### Option A: From vmess:// URL

If you have a VMess URL like:
```
vmess://eyJhZGQiOiIxMjMuNDU2Ljc4OS4xMjMiLCJhaWQiOiIwIiwiaG9zdCI6IiIsImlkIjoiYWJjZGVmZ2gtMTIzNC01Njc4LTkwYWItY2RlZjEyMzQ1Njc4IiwibmV0Ijoid3MiLCJwYXRoIjoiLyIsInBvcnQiOiI0NDMiLCJwcyI6Ik15IFNlcnZlciIsInNjeSI6ImF1dG8iLCJzbmkiOiIiLCJ0bHMiOiJ0bHMiLCJ0eXBlIjoiIiwidiI6IjIifQ==
```

**Steps**:
1. Right-click v2rayN tray icon → **Servers** → **Import URL from clipboard**
2. Or: Click **Servers** menu → **Add [VMess] server** → Paste URL
3. The server will appear in the server list

#### Option B: From Subscription URL

If you have a subscription URL:

1. Click **Subscriptions** → **Subscription settings**
2. Click **Add**
3. Enter:
   - **Remarks**: Name for this subscription (e.g., "My VPN")
   - **URL**: Your subscription URL
4. Click **OK**
5. Click **Subscriptions** → **Update subscription**
6. Servers will be imported automatically

#### Option C: Manual Configuration (VMess)

1. Click **Servers** → **Add [VMess] server**
2. Fill in the details:
   - **Remarks**: Server name
   - **Address**: Server IP/domain
   - **Port**: Server port (e.g., 443)
   - **User ID**: Your UUID
   - **Alter ID**: Usually 0
   - **Security**: auto or aes-128-gcm
   - **Network**: tcp, ws, h2, etc.
   - **TLS**: none or tls
3. Click **OK**

#### Option D: Shadowsocks Server

1. Click **Servers** → **Add [Shadowsocks] server**
2. Fill in:
   - **Remarks**: Server name
   - **Address**: Server IP
   - **Port**: Server port
   - **Password**: Your password
   - **Encryption**: aes-256-gcm, chacha20-ietf-poly1305, etc.
3. Click **OK**

### Step 3: Configure v2rayN Settings

1. **Right-click v2rayN tray icon** → **Settings**

2. **Core: Basic Settings**:
   - **Local SOCKS5 Port**: `10808` (default)
   - **Local HTTP Port**: `10809` (default)
   - **Allow LAN connections**: ✓ **Enable** (critical!)
   - **UDP**: Enable if needed

3. **Core: v2rayN Settings**:
   - **System Proxy**: Choose mode:
     - **Clear system proxy**: No Windows proxy
     - **Set system proxy (PAC)**: Rule-based
     - **Set system proxy (Global)**: All traffic through proxy
   - For WSL2 only: Choose "Clear system proxy"

4. **Click OK** to save

### Step 4: Enable "Allow LAN Connections"

**This is critical for WSL2 access!**

1. Right-click v2rayN tray icon → **Settings**
2. Go to **Core: Basic Settings**
3. Check **"Allow LAN connections"** ✓
4. This changes the listen address from `127.0.0.1` to `0.0.0.0`
5. Click **OK**
6. **Restart v2rayN** (right-click tray icon → Exit, then start again)

### Step 5: Configure Windows Firewall

Allow WSL2 to access v2rayN ports:

#### PowerShell (Run as Administrator)

```powershell
# Allow HTTP port 10809
New-NetFirewallRule -DisplayName "v2rayN HTTP" -Direction Inbound -LocalPort 10809 -Protocol TCP -Action Allow -Profile Private

# Allow SOCKS5 port 10808 (optional)
New-NetFirewallRule -DisplayName "v2rayN SOCKS5" -Direction Inbound -LocalPort 10808 -Protocol TCP -Action Allow -Profile Private
```

### Step 6: Verify v2rayN is Running

In PowerShell:

```powershell
# Check if v2rayN is listening
netstat -an | findstr "10809"

# Should show:
# TCP    0.0.0.0:10809          0.0.0.0:0              LISTENING
```

**Important**: If you see `127.0.0.1:10809` instead of `0.0.0.0:10809`, "Allow LAN" is not enabled!

### Step 7: Start the Proxy

1. **Select a server** from the list (double-click or right-click → Set as active server)
2. The active server will be highlighted
3. Right-click tray icon → **System Proxy** → Choose mode (or "Clear" for WSL2 only)
4. The tray icon will show connection status

---

## Part 2: WSL2 - Docker Configuration

### Step 1: Get Windows Host IP

```bash
# Get Windows host IP from WSL2
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
echo "Windows host IP: $HOST_IP"

# Example output: 10.255.255.254 or 172.x.x.x
```

### Step 2: Test v2rayN Connectivity from WSL2

```bash
# Test HTTP proxy port
nc -vz $HOST_IP 10809
# Expected: Connection to [IP] 10809 port [tcp/*] succeeded!

# Test with curl
http_proxy=http://$HOST_IP:10809 curl -sS https://api.ipify.org
# Should return your proxy's public IP
```

If connection fails, check:
- v2rayN "Allow LAN connections" is enabled
- Windows Firewall rules are set
- v2rayN is running and server is active

### Step 3: Configure Docker Daemon Proxy

```bash
# Create systemd drop-in directory
sudo mkdir -p /etc/systemd/system/docker.service.d

# Get Windows host IP
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)

# Create proxy configuration
sudo tee /etc/systemd/system/docker.service.d/proxy.conf >/dev/null <<EOF
[Service]
Environment="HTTP_PROXY=http://${HOST_IP}:10809"
Environment="HTTPS_PROXY=http://${HOST_IP}:10809"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

# Show created config
cat /etc/systemd/system/docker.service.d/proxy.conf
```

### Step 4: Configure Docker Daemon Settings

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

### Step 5: Disable IPv6 (Critical!)

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

### Step 6: Restart Docker

```bash
# Reload systemd and restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# Check Docker status
systemctl status docker
```

---

## Verification

### 1. Check Windows Host IP

```bash
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
echo "Windows host IP: $HOST_IP"
```

### 2. Check v2rayN Connectivity

```bash
# Test HTTP port
nc -vz $HOST_IP 10809

# Test with curl
http_proxy=http://$HOST_IP:10809 curl -sS https://api.ipify.org
# Should return your proxy's public IP
```

### 3. Check Docker Proxy Configuration

```bash
# View Docker daemon environment
systemctl show docker --property=Environment

# Should show:
# Environment=HTTP_PROXY=http://[IP]:10809 HTTPS_PROXY=http://[IP]:10809 NO_PROXY=localhost,127.0.0.1
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

### Issue: "Connection refused" to Windows host IP

**Cause**: v2rayN not accessible from WSL2

**Solutions**:

1. **Verify "Allow LAN connections" is enabled**:
   - Right-click v2rayN tray icon → **Settings**
   - **Core: Basic Settings** → Check "Allow LAN connections"
   - Click OK and **restart v2rayN**

2. **Check Windows Firewall**:
   ```powershell
   # In PowerShell (Admin)
   Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*v2ray*"}
   
   # If missing, add rule:
   New-NetFirewallRule -DisplayName "v2rayN HTTP" -Direction Inbound -LocalPort 10809 -Protocol TCP -Action Allow -Profile Private
   ```

3. **Verify v2rayN is listening on 0.0.0.0**:
   ```powershell
   netstat -an | findstr "10809"
   # Should show: TCP    0.0.0.0:10809
   # NOT:         TCP    127.0.0.1:10809
   ```

4. **Test from WSL2**:
   ```bash
   HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
   nc -vz $HOST_IP 10809
   ```

### Issue: v2rayN shows 0.0.0.0 but still connection refused

**Cause**: Windows Firewall or network isolation

**Solutions**:

1. **Temporarily disable firewall to test**:
   ```powershell
   # PowerShell (Admin)
   Set-NetFirewallProfile -Profile Private -Enabled False
   ```
   
   Test from WSL2, then re-enable:
   ```powershell
   Set-NetFirewallProfile -Profile Private -Enabled True
   ```

2. **Use port proxy workaround**:
   ```powershell
   # PowerShell (Admin)
   netsh interface portproxy add v4tov4 listenport=10809 listenaddress=10.255.255.254 connectport=10809 connectaddress=127.0.0.1
   
   # Verify
   netsh interface portproxy show all
   
   # Start IP Helper service if needed
   Start-Service iphlpsvc
   Set-Service iphlpsvc -StartupType Automatic
   ```

### Issue: Docker pull times out

**Cause**: IPv6 not disabled or proxy not working

**Solutions**:

1. **Verify IPv6 is disabled**:
   ```bash
   sysctl net.ipv6.conf.all.disable_ipv6
   # Should be 1
   
   # If not:
   sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
   sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
   sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1
   sudo systemctl restart docker
   ```

2. **Test proxy manually**:
   ```bash
   HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
   http_proxy=http://$HOST_IP:10809 curl -v https://registry-1.docker.io/v2/
   ```

3. **Check Docker proxy env**:
   ```bash
   systemctl show docker --property=Environment
   ```

### Issue: Windows host IP changes after reboot

**Cause**: WSL2 network resets, IP changes

**Solution**: Create a script to update Docker proxy config

```bash
#!/bin/bash
# ~/update-docker-proxy.sh

HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)

sudo tee /etc/systemd/system/docker.service.d/proxy.conf >/dev/null <<EOF
[Service]
Environment="HTTP_PROXY=http://${HOST_IP}:10809"
Environment="HTTPS_PROXY=http://${HOST_IP}:10809"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

echo "Docker proxy updated to use $HOST_IP:10809"
```

Make it executable and run after WSL restart:
```bash
chmod +x ~/update-docker-proxy.sh
sudo ~/update-docker-proxy.sh
```

### Issue: v2rayN not starting on Windows boot

**Solution**:

1. Right-click v2rayN tray icon → **Settings**
2. **v2rayN Settings** → Check "Auto run at startup"
3. Or add to Windows Startup:
   - Press `Win+R`
   - Type `shell:startup`
   - Create shortcut to `v2rayN.exe`

### Issue: Slow Docker pulls

**Cause**: Proxy server performance or routing issues

**Solutions**:

1. **Test proxy speed**:
   ```bash
   HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
   http_proxy=http://$HOST_IP:10809 curl -w "@-" -o /dev/null -s https://speed.cloudflare.com/__down?bytes=10000000 <<'EOF'
   time_total: %{time_total}s
   speed_download: %{speed_download} bytes/sec
   EOF
   ```

2. **Try different server** in v2rayN (if you have multiple)

3. **Check v2rayN routing mode**:
   - Right-click tray icon → **Routing settings**
   - Try different modes: PAC, Global, Direct

---

## Maintenance

### Update Windows Host IP After WSL Restart

```bash
# Quick update script
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
sudo sed -i "s|HTTP_PROXY=http://[0-9.]*:10809|HTTP_PROXY=http://${HOST_IP}:10809|g" /etc/systemd/system/docker.service.d/proxy.conf
sudo sed -i "s|HTTPS_PROXY=http://[0-9.]*:10809|HTTPS_PROXY=http://${HOST_IP}:10809|g" /etc/systemd/system/docker.service.d/proxy.conf
sudo systemctl daemon-reload
sudo systemctl restart docker
echo "Updated to $HOST_IP"
```

### View Logs

```bash
# Docker logs
sudo journalctl -u docker -f

# Check Docker proxy environment
systemctl show docker --property=Environment
```

### Restart Services

```bash
# Restart Docker only
sudo systemctl restart docker

# Restart v2rayN (Windows)
# Right-click tray icon → Exit → Start v2rayN.exe again
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

## Quick Setup Script

Save this as `setup-docker-v2ray.sh`:

```bash
#!/bin/bash
# Quick setup for Docker with v2rayN proxy

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Docker + v2rayN Setup${NC}"
echo ""

# Get Windows host IP
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
echo "Windows host IP: $HOST_IP"

# Test v2rayN connectivity
echo -n "Testing v2rayN HTTP proxy... "
if nc -zv $HOST_IP 10809 2>&1 | grep -q succeeded; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}FAILED${NC}"
    echo "Please ensure:"
    echo "  1. v2rayN is running"
    echo "  2. 'Allow LAN connections' is enabled"
    echo "  3. Windows Firewall allows port 10809"
    exit 1
fi

# Configure Docker proxy
echo "Configuring Docker proxy..."
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/proxy.conf >/dev/null <<EOF
[Service]
Environment="HTTP_PROXY=http://${HOST_IP}:10809"
Environment="HTTPS_PROXY=http://${HOST_IP}:10809"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

# Configure Docker daemon
echo "Configuring Docker daemon..."
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "ipv6": false,
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF

# Disable IPv6
echo "Disabling IPv6..."
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null

if ! grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf 2>/dev/null; then
    sudo tee -a /etc/sysctl.conf >/dev/null <<'EOF'

# Disable IPv6 for Docker proxy
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
fi

# Restart Docker
echo "Restarting Docker..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# Verify
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Testing Docker pull..."
if timeout 30 docker pull hello-world >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker pull works!${NC}"
else
    echo -e "${YELLOW}✗ Docker pull failed${NC}"
fi

echo ""
echo "Proxy chain: Docker → v2rayN ($HOST_IP:10809) → Internet"
```

Make it executable and run:
```bash
chmod +x setup-docker-v2ray.sh
sudo ./setup-docker-v2ray.sh
```

---

## Files Modified

| File | Purpose |
|------|---------|
| `/etc/systemd/system/docker.service.d/proxy.conf` | Docker daemon proxy |
| `/etc/docker/daemon.json` | Docker daemon settings |
| `/etc/sysctl.conf` | IPv6 disable (persistent) |

---

## Summary

### Setup Steps

1. **Windows**: Install v2rayN, import server config, enable "Allow LAN connections"
2. **Windows**: Configure firewall to allow port 10809
3. **WSL2**: Get Windows host IP
4. **WSL2**: Configure Docker to use v2rayN HTTP proxy
5. **WSL2**: Disable IPv6
6. **WSL2**: Restart Docker and test

### Key Configuration

- **v2rayN HTTP Port**: `10809`
- **v2rayN SOCKS5 Port**: `10808`
- **Allow LAN**: Must be enabled
- **Listen Address**: `0.0.0.0` (not `127.0.0.1`)

### Proxy Chain

```
Docker → v2rayN HTTP (10809) → Internet
```

**Simple and efficient!**

---

## Comparison: v2rayN vs Clash Verge

| Feature | v2rayN | Clash Verge |
|---------|--------|-------------|
| **HTTP Port** | 10809 | 7890 |
| **SOCKS5 Port** | 10808 | 1080 |
| **GUI** | Simple, functional | Modern, polished |
| **Protocols** | VMess, VLESS, SS, Trojan, etc. | VMess, VLESS, SS, Trojan, etc. |
| **Config Import** | URL, QR, JSON | URL, YAML |
| **Resource Usage** | Very light | Light |
| **Ease of Use** | Easy | Very easy |
| **Rule-based Routing** | Yes (PAC/routing) | Yes (advanced) |

**Both work well for Docker proxy!** Choose based on your preference.

---

**Last Updated**: October 2025
