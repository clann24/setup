# Convert Shadowsocks URL to Subscription

## Shadowsocks URL Format

```
ss://[base64-encoded-config]@[server]:[port]#[name]
```

**Example:**
```
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@example.com:8388#MyServer
```

Where `YWVzLTI1Ni1nY206cGFzc3dvcmQ=` is base64 of `method:password`

## Method 1: Create Subscription File (Recommended)

### Step 1: Create a text file with your ss:// URLs

```bash
# Create subscription file
cat > ~/shadowsocks-subscription.txt << 'EOF'
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@example.com:8388#Server1
ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpteXBhc3N3b3Jk@example2.com:443#Server2
EOF
```

### Step 2: Base64 encode the entire file

```bash
# For macOS
base64 -i ~/shadowsocks-subscription.txt -o ~/shadowsocks-subscription-encoded.txt

# View the result
cat ~/shadowsocks-subscription-encoded.txt
```

### Step 3: Host the subscription (optional)

**Option A: Use a local file**
- Just use the file path in your client

**Option B: Host on GitHub Gist**
1. Go to https://gist.github.com
2. Create a new gist with the base64 content
3. Click "Raw" to get the URL
4. Use this URL as subscription link

**Option C: Host on your own server**
```bash
# Upload to server
scp ~/shadowsocks-subscription-encoded.txt user@yourserver:/var/www/html/subscription.txt

# Subscription URL
https://yourserver.com/subscription.txt
```

## Method 2: Use Online Converter

### SSD to Subscription Converter
```
https://bianyuan.xyz/
```

1. Paste your ss:// URLs
2. Click "Convert to Subscription"
3. Copy the generated subscription URL

## Method 3: Manual Subscription Format

Create a file with this structure:

```json
{
  "servers": [
    {
      "server": "example.com",
      "server_port": 8388,
      "password": "password",
      "method": "aes-256-gcm",
      "remarks": "Server1"
    },
    {
      "server": "example2.com",
      "server_port": 443,
      "password": "mypassword",
      "method": "chacha20-ietf-poly1305",
      "remarks": "Server2"
    }
  ]
}
```

Then base64 encode it:
```bash
base64 -i config.json -o subscription.txt
```

## Method 4: Quick Script

```bash
#!/bin/bash

# Convert ss:// URLs to subscription

# Input: ss:// URLs (one per line)
SS_URLS="ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@example.com:8388#Server1
ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpteXBhc3N3b3Jk@example2.com:443#Server2"

# Create subscription
echo "$SS_URLS" | base64

# Or save to file
echo "$SS_URLS" | base64 > subscription.txt
echo "Subscription saved to subscription.txt"
```

## Using Subscription in Clients

### ShadowsocksX-NG
1. Click menu bar icon → "Servers"
2. Click "Edit Subscription"
3. Add subscription URL
4. Click "Update Subscription"

### ClashX
1. Click menu bar icon → "Config"
2. Click "Remote Config" → "Manage"
3. Add subscription URL
4. Click "Update"

### Clash Verge
1. Open Clash Verge
2. Click "Profiles"
3. Click "+" → "Import from URL"
4. Paste subscription URL
5. Click "Import"

## Decode Subscription (for verification)

```bash
# Decode base64 subscription
base64 -d -i subscription.txt

# Or from URL
curl -s https://yourserver.com/subscription.txt | base64 -d
```

## Notes

- Subscription format is just base64-encoded list of ss:// URLs
- One URL per line
- Can include multiple servers
- Clients auto-parse and update server list
- Keep subscription URL private (contains server credentials)
