# Docker Proxy Setup with Clash Verge (Simplified)

Complete guide for configuring Docker in WSL2 Ubuntu to use Clash Verge HTTP proxy from Windows host.

## Table of Contents

- [Overview](#overview)
- [Why Clash Verge?](#why-clash-verge)
- [Architecture](#architecture)
- [Part 1: Windows - Clash Verge Setup](#part-1-windows---clash-verge-setup)
- [Part 2: WSL2 - Docker Configuration](#part-2-wsl2---docker-configuration)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [Comparison with Privoxy Setup](#comparison-with-privoxy-setup)

---

## Overview

This guide uses **Clash Verge** on Windows to provide HTTP proxy directly to Docker in WSL2, eliminating the need for Privoxy.

### Key Benefits

✓ **Simpler** - No Privoxy bridge needed  
✓ **Fewer services** - One less daemon in WSL2  
✓ **Native HTTP** - Clash provides HTTP proxy directly  
✓ **Better performance** - One less hop in the proxy chain  
✓ **Easier maintenance** - Manage proxy only on Windows  

---

## Why Clash Verge?

### Advantages over Shadowsocks-Windows

| Feature | Shadowsocks-Windows | Clash Verge |
|---------|---------------------|-------------|
| SOCKS5 | ✓ Yes | ✓ Yes |
| HTTP Proxy | ✗ No | ✓ Yes (port 7890) |
| Mixed Port | ✗ No | ✓ Yes |
| GUI | Basic | Modern |
| Rule-based routing | ✗ No | ✓ Yes |
| Multiple protocols | SS only | SS, VMess, Trojan, etc. |
| Active development | Limited | ✓ Active |

### Clash Verge Features

- **Mixed port**: Single port (7890) handles both HTTP and SOCKS5
- **Native HTTP**: No need for Privoxy bridge
- **Modern UI**: Easy configuration
- **Import ss:// URLs**: Supports Shadowsocks servers
- **Rule-based routing**: Advanced traffic control
- **Cross-platform**: Windows, macOS, Linux

---

## Architecture

### Simplified Setup (with Clash Verge)

```
┌─────────────────────────────────────────────────────────────┐
│ Windows Host                                                 │
│  ┌────────────────────────────────────────────────────┐     │
│  │ Clash Verge                                        │     │
│  │ HTTP:   0.0.0.0:7890 (Allow LAN enabled)          │     │
│  │ SOCKS5: 0.0.0.0:1080                              │     │
│  │ Mixed:  0.0.0.0:7890 (handles both)               │     │
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
│  │ HTTP_PROXY=http://[WIN_IP]:7890                  │       │
│  │ HTTPS_PROXY=http://[WIN_IP]:7890                │       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
│  No Privoxy needed! ✓                                       │
└─────────────────────────────────────────────────────────────┘
```

### Old Setup (with Privoxy)

```
Windows → SOCKS5 → WSL2 Privoxy → HTTP → Docker
         (1080)      (bridge)    (8118)
```

### New Setup (with Clash Verge)

```
Windows Clash Verge → HTTP → Docker
                     (7890)
```

**One less hop = simpler + faster!**

---

## Part 1: Windows - Clash Verge Setup

### Step 1: Download and Install Clash Verge

**Download from**:
```
https://github.com/clash-verge-rev/clash-verge-rev/releases/latest
```

**Choose**:
- `Clash.Verge_x.x.x_x64-setup.exe` for Windows installer
- Or portable version if preferred

**Install**:
1. Run the installer
2. Follow installation wizard
3. Launch Clash Verge

### Step 2: Import Your Shadowsocks Server

#### Option A: From ss:// URL

If you have a Shadowsocks URL like:
```
ss://YWVzLTI1Ni1nY206OUIzUmZZV2pQTHdyL3lVV1RBY2Y2Zz09@43.165.179.209:443
```

**You need to create a config file** (Clash doesn't accept raw ss:// URLs):

1. Click **Profiles** → **New** → **Create Empty**
2. Name it: `My SS Server`
3. Click **Edit**
4. Paste this config (replace with your decoded values):

```yaml
mixed-port: 7890
allow-lan: true
bind-address: '0.0.0.0'
mode: rule
log-level: info

proxies:
  - name: "SS-Server"
    type: ss
    server: 43.165.179.209      # Your server IP
    port: 443                    # Your port
    cipher: aes-256-gcm          # Your cipher
    password: "9B3RfYWjPLwr/yUWTAcf6g=="  # Your password
    udp: true

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - "SS-Server"
      - DIRECT

rules:
  - MATCH,Proxy
```

5. Click **Save**
6. **Activate** the profile (toggle switch)

#### Option B: From Subscription URL

If you have a subscription URL:

1. Click **Profiles** → **New** → **Import from URL**
2. Paste your subscription URL
3. Click **Import**
4. Activate the profile

#### Option C: Manual Config Template

For multiple servers or advanced config:

```yaml
mixed-port: 7890
allow-lan: true
bind-address: '0.0.0.0'
mode: rule
log-level: info
ipv6: false

proxies:
  # Shadowsocks server
  - name: "SS-HK"
    type: ss
    server: hk.example.com
    port: 443
    cipher: aes-256-gcm
    password: "your-password"
    udp: true

  - name: "SS-US"
    type: ss
    server: us.example.com
    port: 8388
    cipher: chacha20-ietf-poly1305
    password: "your-password"
    udp: true

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - "SS-HK"
      - "SS-US"
      - DIRECT

  - name: "Auto"
    type: url-test
    proxies:
      - "SS-HK"
      - "SS-US"
    url: 'http://www.gstatic.com/generate_204'
    interval: 300

rules:
  - DOMAIN-SUFFIX,google.com,Proxy
  - DOMAIN-SUFFIX,github.com,Proxy
  - DOMAIN-KEYWORD,docker,Proxy
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
```

### Step 3: Configure Clash Verge Settings

1. **Open Settings** (gear icon)

2. **System Proxy** (optional):
   - Enable if you want Windows apps to use proxy
   - Or leave disabled and only use for WSL2

3. **Clash Core Settings**:
   - **Allow LAN**: ✓ Enable (critical!)
   - **Mixed Port**: `7890`
   - **HTTP Port**: `7890` (or separate if needed)
   - **SOCKS Port**: `1080`
   - **Bind Address**: `0.0.0.0` or `*`

4. **Click Apply/Save**

### Step 4: Configure Windows Firewall

Allow WSL2 to access Clash ports:

#### PowerShell (Run as Administrator)

```powershell
# Allow HTTP/Mixed port 7890
New-NetFirewallRule -DisplayName "Clash Verge HTTP" -Direction Inbound -LocalPort 7890 -Protocol TCP -Action Allow -Profile Private

# Allow SOCKS5 port 1080 (optional)
New-NetFirewallRule -DisplayName "Clash Verge SOCKS5" -Direction Inbound -LocalPort 1080 -Protocol TCP -Action Allow -Profile Private
```

### Step 5: Verify Clash is Running

In PowerShell:

```powershell
# Check if Clash is listening
netstat -an | findstr "7890"

# Should show:
# TCP    0.0.0.0:7890           0.0.0.0:0              LISTENING
```

---

## Part 2: WSL2 - Docker Configuration

### Step 1: Get Windows Host IP

```bash
# Get Windows host IP from WSL2
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
echo "Windows host IP: $HOST_IP"

# Example output: 10.255.255.254 or 172.x.x.x
```

### Step 2: Test Clash Connectivity from WSL2

```bash
# Test HTTP proxy
nc -vz $HOST_IP 7890
# Expected: Connection to [IP] 7890 port [tcp/*] succeeded!

# Test with curl
http_proxy=http://$HOST_IP:7890 curl -sS https://api.ipify.org
# Should return your proxy's public IP
```

If connection fails, check:
- Clash Verge "Allow LAN" is enabled
- Windows Firewall rules are set
- Clash is running

### Step 3: Configure Docker Daemon Proxy

```bash
# Create systemd drop-in directory
sudo mkdir -p /etc/systemd/system/docker.service.d

# Get Windows host IP
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)

# Create proxy configuration
sudo tee /etc/systemd/system/docker.service.d/proxy.conf >/dev/null <<EOF
[Service]
Environment="HTTP_PROXY=http://${HOST_IP}:7890"
Environment="HTTPS_PROXY=http://${HOST_IP}:7890"
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

### Step 6: Configure IPv4 Preference

```bash
# Backup gai.conf
sudo cp /etc/gai.conf /etc/gai.conf.bak 2>/dev/null || true

# Add IPv4 preference
echo 'precedence ::ffff:0:0/96  100' | sudo tee -a /etc/gai.conf
```

### Step 7: Restart Docker

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

### 2. Check Clash Connectivity

```bash
# Test HTTP port
nc -vz $HOST_IP 7890

# Test with curl
http_proxy=http://$HOST_IP:7890 curl -sS https://api.ipify.org
# Should return your proxy's public IP
```

### 3. Check Docker Proxy Configuration

```bash
# View Docker daemon environment
systemctl show docker --property=Environment

# Should show:
# Environment=HTTP_PROXY=http://[IP]:7890 HTTPS_PROXY=http://[IP]:7890 NO_PROXY=localhost,127.0.0.1
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

**Cause**: Clash not accessible from WSL2

**Solutions**:

1. **Verify Clash "Allow LAN" is enabled**:
   - Open Clash Verge → Settings → Clash Core
   - Ensure "Allow LAN" is checked
   - Bind Address should be `0.0.0.0` or `*`

2. **Check Windows Firewall**:
   ```powershell
   # In PowerShell (Admin)
   Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*Clash*"}
   
   # If missing, add rule:
   New-NetFirewallRule -DisplayName "Clash Verge HTTP" -Direction Inbound -LocalPort 7890 -Protocol TCP -Action Allow -Profile Private
   ```

3. **Verify Clash is running**:
   ```powershell
   netstat -an | findstr "7890"
   ```

4. **Test from WSL2**:
   ```bash
   HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
   nc -vz $HOST_IP 7890
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
   http_proxy=http://$HOST_IP:7890 curl -v https://registry-1.docker.io/v2/
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
Environment="HTTP_PROXY=http://${HOST_IP}:7890"
Environment="HTTPS_PROXY=http://${HOST_IP}:7890"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

echo "Docker proxy updated to use $HOST_IP:7890"
```

Make it executable and run after WSL restart:
```bash
chmod +x ~/update-docker-proxy.sh
sudo ~/update-docker-proxy.sh
```

### Issue: Clash Verge not starting on Windows boot

**Solution**:

1. Open Clash Verge settings
2. Enable "Start on system boot"
3. Or add to Windows Startup:
   - Press `Win+R`
   - Type `shell:startup`
   - Create shortcut to Clash Verge

### Issue: Slow Docker pulls

**Cause**: Proxy server performance or DNS issues

**Solutions**:

1. **Test proxy speed**:
   ```bash
   HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
   http_proxy=http://$HOST_IP:7890 curl -w "@-" -o /dev/null -s https://speed.cloudflare.com/__down?bytes=10000000 <<'EOF'
   time_total: %{time_total}s
   speed_download: %{speed_download} bytes/sec
   EOF
   ```

2. **Try different DNS** in `/etc/docker/daemon.json`:
   ```json
   {
     "ipv6": false,
     "dns": ["1.1.1.1", "1.0.0.1"]
   }
   ```

3. **Check Clash routing rules** - ensure Docker traffic goes through proxy

---

## Maintenance

### Update Windows Host IP After WSL Restart

```bash
# Quick update script
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
sudo sed -i "s|HTTP_PROXY=http://[0-9.]*:7890|HTTP_PROXY=http://${HOST_IP}:7890|g" /etc/systemd/system/docker.service.d/proxy.conf
sudo sed -i "s|HTTPS_PROXY=http://[0-9.]*:7890|HTTPS_PROXY=http://${HOST_IP}:7890|g" /etc/systemd/system/docker.service.d/proxy.conf
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

# Restart Clash Verge (Windows)
# Right-click tray icon → Restart
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

## Comparison with Privoxy Setup

### Privoxy Setup (Old Method)

**Pros**:
- Self-contained in WSL2
- Works with any SOCKS5 proxy
- Independent of Windows proxy client

**Cons**:
- Extra service to manage
- Additional hop in proxy chain
- More complex configuration
- Requires Privoxy maintenance

**Architecture**:
```
Windows SOCKS5 → WSL2 Privoxy → Docker
     (1080)         (8118)
```

### Clash Verge Setup (New Method)

**Pros**:
- ✓ Simpler - no Privoxy needed
- ✓ Fewer services in WSL2
- ✓ Direct HTTP connection
- ✓ Better performance
- ✓ Modern GUI for proxy management
- ✓ Rule-based routing
- ✓ Multiple protocol support

**Cons**:
- Requires Clash Verge on Windows
- Dependent on Windows service
- Need to update IP if it changes

**Architecture**:
```
Windows Clash Verge → Docker
        (7890)
```

### When to Use Each

| Use Case | Recommended Setup |
|----------|-------------------|
| **Have Clash/v2rayN with HTTP** | Clash Verge (this guide) |
| **Only have SOCKS5** | Privoxy setup |
| **Want simplicity** | Clash Verge |
| **Want independence** | Privoxy setup |
| **Multiple protocols** | Clash Verge |
| **Shadowsocks only** | Either works |

---

## Quick Setup Script

Save this as `setup-docker-clash.sh`:

```bash
#!/bin/bash
# Quick setup for Docker with Clash Verge proxy

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Docker + Clash Verge Setup${NC}"
echo ""

# Get Windows host IP
HOST_IP=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
echo "Windows host IP: $HOST_IP"

# Test Clash connectivity
echo -n "Testing Clash HTTP proxy... "
if nc -zv $HOST_IP 7890 2>&1 | grep -q succeeded; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}FAILED${NC}"
    echo "Please ensure:"
    echo "  1. Clash Verge is running"
    echo "  2. 'Allow LAN' is enabled"
    echo "  3. Windows Firewall allows port 7890"
    exit 1
fi

# Configure Docker proxy
echo "Configuring Docker proxy..."
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/proxy.conf >/dev/null <<EOF
[Service]
Environment="HTTP_PROXY=http://${HOST_IP}:7890"
Environment="HTTPS_PROXY=http://${HOST_IP}:7890"
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
echo "Proxy chain: Docker → Clash Verge ($HOST_IP:7890) → Internet"
```

Make it executable and run:
```bash
chmod +x setup-docker-clash.sh
sudo ./setup-docker-clash.sh
```

---

## Files Modified

| File | Purpose |
|------|---------|
| `/etc/systemd/system/docker.service.d/proxy.conf` | Docker daemon proxy |
| `/etc/docker/daemon.json` | Docker daemon settings |
| `/etc/sysctl.conf` | IPv6 disable (persistent) |
| `/etc/gai.conf` | IPv4 DNS preference |

**No Privoxy files needed!**

---

## Summary

### Setup Steps

1. **Windows**: Install Clash Verge, import SS config, enable "Allow LAN"
2. **Windows**: Configure firewall to allow port 7890
3. **WSL2**: Get Windows host IP
4. **WSL2**: Configure Docker to use Clash HTTP proxy
5. **WSL2**: Disable IPv6
6. **WSL2**: Restart Docker and test

### Key Differences from Privoxy Setup

- ✓ **No Privoxy** installation or configuration
- ✓ **Direct HTTP** connection to Clash
- ✓ **Simpler** architecture
- ✓ **Fewer** services to manage
- ✓ **Better** performance

### Proxy Chain

```
Docker → Clash Verge HTTP (7890) → Internet
```

**Simple and efficient!**

---

**Last Updated**: October 2025
