# Docker Desktop Proxy Configuration (macOS)

1. **Open Docker Desktop**
   - Click the Docker icon in the menu bar
   - Select "Settings" or "Preferences"

2. **Navigate to Resources → Proxies**
   - Click "Resources" in the left sidebar
   - Click "Proxies"

3. **Configure Proxy Settings**
   - Enable "Manual proxy configuration"
   - Set the following:
     - **Web Server (HTTP)**: `http://127.0.0.1:1087`
     - **Secure Web Server (HTTPS)**: `http://127.0.0.1:1087`
     - **Bypass for these hosts & domains**: `localhost,127.0.0.1`

4. **Apply & Restart**
   - Click "Apply & Restart"
   - Docker Desktop will restart automatically with the new proxy settings

5. **Test**
   ```bash
   docker pull python:3.12
   ```