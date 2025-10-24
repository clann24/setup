# WireGuard VPN Setup

One-script automated installation for Ubuntu.

---

## 🚀 Installation

### Prerequisites
- Ubuntu 20.04+
- Root/sudo access
- **Open UDP port 443 in your cloud security group**

### Run Setup
```bash
sudo ./wire.sh
```

The script automatically:
- Installs WireGuard and dependencies
- Generates server and client keys
- Configures firewall (UFW)
- Creates client config with QR code
- Starts VPN service

---

## 📱 Client Setup

### Mobile (iOS/Android)
```bash
# Display QR code
sudo cat /etc/wireguard/clients/client1_qr.txt
```

In WireGuard app: **+** → **Create from QR code** → Scan

### Desktop (Windows/Mac/Linux)
```bash
# Show config
sudo cat /etc/wireguard/clients/client1.conf
```

In WireGuard app: **Add Tunnel** → Paste config

---

## 🔧 Management

### Check Status
```bash
sudo wg show
```

### Restart VPN
```bash
sudo systemctl restart wg-quick@wg0
```

### View Logs
```bash
sudo journalctl -u wg-quick@wg0 -f
```

---

## 👥 Add More Clients

Edit `wire.sh` line 38:
```bash
CLIENT_COUNT=5  # Change from 1 to desired number
```

Then rerun:
```bash
sudo ./wire.sh
```

Or manually:
```bash
cd /etc/wireguard/clients
wg genkey | tee client2_private.key | wg pubkey > client2_public.key

# Add [Peer] section to /etc/wireguard/wg0.conf
# Create client2.conf similar to client1.conf with IP 10.0.0.3
# Restart: sudo systemctl restart wg-quick@wg0
```

---

## ⚠️ Troubleshooting

### Client Can't Connect
1. **Check cloud firewall**: UDP port 443 must be open
2. **Check UFW**: `sudo ufw status` should show `443/udp ALLOW IN`
3. **Verify service**: `sudo systemctl status wg-quick@wg0`

### No Data Received (0 B)
```bash
# Enable routing
sudo ufw default allow routed
sudo ufw reload
```

### View Active Connections
```bash
sudo wg show wg0
```

Should display:
- `endpoint`: Client IP and port
- `latest handshake`: Recent timestamp
- `transfer`: Data sent/received

---

## 📂 Files Location

```
/etc/wireguard/
├── wg0.conf              # Server config
├── server_private.key    # Server keys
├── server_public.key
└── clients/
    ├── client1.conf      # Client config
    ├── client1_qr.txt    # QR code (terminal)
    └── client1_qr.png    # QR code (image)
```

---

## 🔒 Configuration

**Server IP:** 10.0.0.1/24  
**Port:** 443 (UDP)  
**Client IP Range:** 10.0.0.2 - 10.0.0.254  
**DNS:** 1.1.1.1, 8.8.8.8

To change port, edit `wire.sh` line 35:
```bash
SERVER_PORT="51820"  # Change to desired port
```

---

## 📖 Resources

- [WireGuard Official Site](https://www.wireguard.com/)
- [Client Downloads](https://www.wireguard.com/install/)

---

**Last Updated:** October 24, 2025
