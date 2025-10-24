#!/bin/bash

set -e

echo "=== Configuring Docker to Use HTTP Proxy ==="

HTTP_PROXY="http://127.0.0.1:1087"
HTTPS_PROXY="http://127.0.0.1:1087"
NO_PROXY="localhost,127.0.0.1"

# Create systemd directory for Docker service
echo "Creating Docker systemd service directory..."
sudo mkdir -p /etc/systemd/system/docker.service.d

# Create HTTP proxy configuration
echo "Creating proxy configuration..."
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF

echo "Proxy configuration created"

# Also update daemon.json for client-side proxy
echo "Updating Docker daemon.json..."
sudo mkdir -p /etc/docker

# Backup existing config if present
if [ -f /etc/docker/daemon.json ]; then
    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
    echo "Backed up existing daemon.json"
fi

# Create daemon.json with proxy settings
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "proxies": {
    "http-proxy": "${HTTP_PROXY}",
    "https-proxy": "${HTTPS_PROXY}",
    "no-proxy": "${NO_PROXY}"
  },
  "dns": ["8.8.8.8", "8.8.4.4"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

echo "daemon.json updated"

# Reload systemd and restart Docker
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Restarting Docker service..."
sudo systemctl restart docker

# Verify configuration
echo ""
echo "=== Configuration Complete ==="
echo ""
echo "Docker proxy settings:"
echo "  HTTP_PROXY: ${HTTP_PROXY}"
echo "  HTTPS_PROXY: ${HTTPS_PROXY}"
echo "  NO_PROXY: ${NO_PROXY}"
echo ""
echo "Verifying Docker service..."
sudo systemctl status docker --no-pager | head -n 10
echo ""
echo "Test with: docker pull python:3.12"
echo ""
