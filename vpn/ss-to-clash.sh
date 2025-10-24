#!/bin/bash

# Convert ss:// URL to Clash YAML format

if [ -z "$1" ]; then
    echo "Usage: $0 'ss://...'"
    echo "Example: $0 'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@example.com:8388#MyServer'"
    exit 1
fi

SS_URL="$1"

# Remove ss:// prefix
SS_DATA="${SS_URL#ss://}"

# Split by @ to get config and server info
IFS='@' read -r CONFIG SERVER_INFO <<< "$SS_DATA"

# Decode base64 config (method:password)
DECODED=$(echo "$CONFIG" | base64 -d 2>/dev/null)

if [ -z "$DECODED" ]; then
    echo "Error: Invalid ss:// URL format"
    exit 1
fi

# Extract method and password
IFS=':' read -r METHOD PASSWORD <<< "$DECODED"

# Extract server, port, and name
SERVER=$(echo "$SERVER_INFO" | cut -d':' -f1)
PORT_AND_NAME=$(echo "$SERVER_INFO" | cut -d':' -f2)
PORT=$(echo "$PORT_AND_NAME" | cut -d'#' -f1)
NAME=$(echo "$PORT_AND_NAME" | cut -d'#' -f2)

# Default name if not provided
if [ -z "$NAME" ]; then
    NAME="SS-Server"
else
    # URL decode name
    NAME=$(echo "$NAME" | sed 's/%20/ /g')
fi

# Generate Clash YAML
cat << EOF
proxies:
  - name: "$NAME"
    type: ss
    server: $SERVER
    port: $PORT
    cipher: $METHOD
    password: "$PASSWORD"
    udp: true

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - $NAME
      - DIRECT

rules:
  - MATCH,Proxy
EOF

echo ""
echo "# Save this as config.yaml and import to Clash Verge"
