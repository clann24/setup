#!/usr/bin/env bash
#
# 一键部署：sing-box (VLESS+REALITY+Vision + Hysteria2 + Shadowsocks 入口) + Cloudflare WARP
#
# 适用：全新 Ubuntu / Debian VPS
# 入口：
#   - 443  TCP : VLESS + REALITY + Vision    (主)
#   - 8443 UDP : Hysteria2 (QUIC, 自签 TLS)
#   - 444  TCP : Shadowsocks                 (备用)
# 服务端按域名分流：
#   - OpenAI / Anthropic (含 Claude / Claude Code) / Google Gemini  → 经 WARP SOCKS5 出口
#   - 其它一切                          → VPS 直连
#
# 用法：sudo bash setup_server.sh
# 可通过环境变量覆盖：
#   VLESS_PORT、VLESS_UUID、REALITY_SNI、REALITY_DEST、REALITY_DEST_PORT、REALITY_SHORT_ID
#   HY2_PORT、HY2_PASSWORD、HY2_SNI
#   SS_PORT、SS_METHOD、SS_PASSWORD
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*" >&2; }

# ===================== 可调参数 =====================
# VLESS + REALITY + Vision (主，TCP)
VLESS_PORT="${VLESS_PORT:-443}"
REALITY_SNI="${REALITY_SNI:-www.microsoft.com}"
REALITY_DEST="${REALITY_DEST:-${REALITY_SNI}}"
REALITY_DEST_PORT="${REALITY_DEST_PORT:-443}"
# VLESS_UUID / REALITY_SHORT_ID / REALITY_PRIVATE_KEY 留空时自动生成并持久化到 /etc/sing-box/
VLESS_UUID="${VLESS_UUID:-}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"

# Hysteria2 (UDP)
HY2_PORT="${HY2_PORT:-8443}"
HY2_PASSWORD="${HY2_PASSWORD:-$(openssl rand -base64 16)}"
HY2_SNI="${HY2_SNI:-www.bing.com}"

# Shadowsocks (备用，TCP)
SS_PORT="${SS_PORT:-444}"
SS_METHOD="${SS_METHOD:-aes-256-gcm}"
SS_PASSWORD="${SS_PASSWORD:-$(openssl rand -base64 16)}"

WARP_SOCKS_PORT=40000
# ====================================================

# ---------- 前置检查 ----------
[[ $EUID -eq 0 ]] || { error "请用 root 运行 (sudo bash $0)"; exit 1; }

if ! grep -qiE "ubuntu|debian" /etc/os-release; then
    warn "本脚本仅在 Ubuntu / Debian 测试过，其它发行版可能失败。"
    read -rp "继续？(y/N) " ans
    [[ "${ans,,}" == "y" ]] || exit 1
fi

info "安装依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl gnupg lsb-release ca-certificates jq qrencode openssl iproute2

CODENAME="$(lsb_release -cs)"

# ---------- 1. Cloudflare WARP ----------
info "添加 Cloudflare WARP 仓库..."
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
    | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${CODENAME} main" \
    > /etc/apt/sources.list.d/cloudflare-client.list

apt-get update
apt-get install -y cloudflare-warp

info "启动 warp-svc 并切换为 proxy 模式..."
systemctl enable --now warp-svc
sleep 3
warp-cli --accept-tos registration new 2>/dev/null || true
# 先断开再设置 mode/port，避免某些版本上切换 mode 不生效
warp-cli --accept-tos disconnect 2>/dev/null || true
warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port "${WARP_SOCKS_PORT}"
warp-cli --accept-tos connect

info "等待 WARP 连接就绪..."
for i in $(seq 1 30); do
    status=$(warp-cli --accept-tos status 2>/dev/null || true)
    if echo "$status" | grep -qi "Connected"; then
        info "WARP 状态：Connected ($i s)"
        break
    fi
    sleep 1
    [[ $i -eq 30 ]] && { error "WARP 30s 内未进入 Connected：$status"; exit 1; }
done

info "等待 SOCKS5 端口 ${WARP_SOCKS_PORT} 监听..."
for i in $(seq 1 30); do
    if ss -lnt "sport = :${WARP_SOCKS_PORT}" | grep -q ":${WARP_SOCKS_PORT}"; then
        info "SOCKS5 已监听 ($i s)"
        break
    fi
    sleep 1
    if [[ $i -eq 30 ]]; then
        error "SOCKS5 端口 ${WARP_SOCKS_PORT} 30s 内未监听"
        warp-cli --accept-tos status || true
        warp-cli --accept-tos settings 2>/dev/null | grep -iE "proxy|mode" || true
        journalctl -u warp-svc -n 50 --no-pager || true
        exit 1
    fi
done

info "验证 WARP 出口..."
if ! curl -fsSx "socks5h://127.0.0.1:${WARP_SOCKS_PORT}" --max-time 15 \
        https://www.cloudflare.com/cdn-cgi/trace | tee /tmp/warp-trace | grep -q "warp=on"; then
    error "WARP 未生效，trace 输出："
    cat /tmp/warp-trace || true
    exit 1
fi
WARP_IP=$(grep -oP 'ip=\K[^[:space:]]+' /tmp/warp-trace || echo "?")
info "WARP 工作正常，出口 IP: ${WARP_IP}"

# ---------- 2. sing-box ----------
info "添加 sing-box 仓库..."
curl -fsSL https://sing-box.app/gpg.key \
    | gpg --yes --dearmor -o /usr/share/keyrings/sagernet.gpg
echo "deb [signed-by=/usr/share/keyrings/sagernet.gpg] https://deb.sagernet.org/ * *" \
    > /etc/apt/sources.list.d/sagernet.list

apt-get update
apt-get install -y sing-box

# ---------- 3. 写配置 ----------
info "生成 /etc/sing-box/config.json ..."
mkdir -p /etc/sing-box
[[ -f /etc/sing-box/config.json ]] && \
    cp /etc/sing-box/config.json "/etc/sing-box/config.json.bak.$(date +%s)"

# Hysteria2 自签证书（仅首次生成，幂等）
if [[ ! -f /etc/sing-box/hy2.crt ]]; then
    info "生成 Hysteria2 自签证书 (CN=${HY2_SNI})..."
    openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/hy2.key
    openssl req -new -x509 -days 3650 -key /etc/sing-box/hy2.key \
        -out /etc/sing-box/hy2.crt -subj "/CN=${HY2_SNI}" \
        -addext "subjectAltName=DNS:${HY2_SNI}"
    chmod 600 /etc/sing-box/hy2.key
fi

# VLESS UUID / REALITY 密钥对 / short_id（仅首次生成并持久化）
if [[ ! -f /etc/sing-box/reality.private.key ]]; then
    info "生成 REALITY X25519 密钥对..."
    sing-box generate reality-keypair > /etc/sing-box/reality.keypair.txt
    awk '/PrivateKey:/ {print $2}' /etc/sing-box/reality.keypair.txt > /etc/sing-box/reality.private.key
    awk '/PublicKey:/  {print $2}' /etc/sing-box/reality.keypair.txt > /etc/sing-box/reality.public.key
    chmod 600 /etc/sing-box/reality.private.key /etc/sing-box/reality.keypair.txt
fi
if [[ ! -f /etc/sing-box/vless.uuid ]]; then
    if [[ -n "${VLESS_UUID}" ]]; then
        echo "${VLESS_UUID}" > /etc/sing-box/vless.uuid
    else
        sing-box generate uuid > /etc/sing-box/vless.uuid
    fi
    chmod 600 /etc/sing-box/vless.uuid
fi
if [[ ! -f /etc/sing-box/reality.short_id ]]; then
    if [[ -n "${REALITY_SHORT_ID}" ]]; then
        echo "${REALITY_SHORT_ID}" > /etc/sing-box/reality.short_id
    else
        openssl rand -hex 8 > /etc/sing-box/reality.short_id
    fi
    chmod 600 /etc/sing-box/reality.short_id
fi

VLESS_UUID="$(cat /etc/sing-box/vless.uuid)"
REALITY_PRIVATE_KEY="$(cat /etc/sing-box/reality.private.key)"
REALITY_PUBLIC_KEY="$(cat /etc/sing-box/reality.public.key)"
REALITY_SHORT_ID="$(cat /etc/sing-box/reality.short_id)"

cat > /etc/sing-box/config.json <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [
      { "type": "https", "tag": "cf-warp", "server": "1.1.1.1", "detour": "warp-out" },
      { "type": "https", "tag": "direct",  "server": "1.1.1.1" }
    ],
    "rules": [
      {
        "rule_set": ["geosite-openai", "geosite-anthropic", "geosite-google-gemini"],
        "server": "cf-warp"
      }
    ],
    "final": "direct",
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${VLESS_PORT},
      "users": [
        { "uuid": "${VLESS_UUID}", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_DEST}",
            "server_port": ${REALITY_DEST_PORT}
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": ["${REALITY_SHORT_ID}"]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [
        { "password": "${HY2_PASSWORD}" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${HY2_SNI}",
        "alpn": ["h3"],
        "certificate_path": "/etc/sing-box/hy2.crt",
        "key_path": "/etc/sing-box/hy2.key"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${SS_PORT},
      "method": "${SS_METHOD}",
      "password": "${SS_PASSWORD}"
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    {
      "type": "socks",
      "tag": "warp-out",
      "server": "127.0.0.1",
      "server_port": ${WARP_SOCKS_PORT},
      "version": "5"
    },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rule_set": [
      {
        "type": "remote", "tag": "geosite-openai", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-openai.srs",
        "download_detour": "direct"
      },
      {
        "type": "remote", "tag": "geosite-anthropic", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-anthropic.srs",
        "download_detour": "direct"
      },
      {
        "type": "remote", "tag": "geosite-google-gemini", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-google-gemini.srs",
        "download_detour": "direct"
      }
    ],
    "rules": [
      { "action": "sniff" },
      { "protocol": "dns", "action": "hijack-dns" },
      {
        "rule_set": ["geosite-openai", "geosite-anthropic", "geosite-google-gemini"],
        "outbound": "warp-out"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true,
    "default_domain_resolver": "direct"
  }
}
EOF

info "校验 sing-box 配置..."
sing-box check -c /etc/sing-box/config.json

# ---------- 4. 启动 ----------
info "启动 sing-box..."
systemctl enable sing-box >/dev/null 2>&1 || true
systemctl restart sing-box
sleep 2
if ! systemctl is-active --quiet sing-box; then
    error "sing-box 启动失败，最近日志："
    journalctl -u sing-box -n 50 --no-pager
    exit 1
fi

# ---------- 5. 防火墙 ----------
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    info "为 ufw 放行端口 ${VLESS_PORT}/tcp、${HY2_PORT}/udp、${SS_PORT}/tcp..."
    ufw allow "${VLESS_PORT}/tcp" >/dev/null
    ufw allow "${HY2_PORT}/udp" >/dev/null
    ufw allow "${SS_PORT}/tcp" >/dev/null
fi

# ---------- 6. BBR ----------
info "启用 BBR..."
grep -q "net.core.default_qdisc=fq"           /etc/sysctl.conf || echo "net.core.default_qdisc=fq"           >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null

# ---------- 7. 输出 ----------
SERVER_IP=$(curl -fs4 --max-time 5 ifconfig.me \
        || curl -fs4 --max-time 5 icanhazip.com \
        || curl -fs4 --max-time 5 api.ipify.org \
        || echo "YOUR_SERVER_IP")

VLESS_URI="vless://${VLESS_UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&flow=xtls-rprx-vision#warp-vps-vless"
HY2_URI="hysteria2://${HY2_PASSWORD}@${SERVER_IP}:${HY2_PORT}/?sni=${HY2_SNI}&insecure=1&alpn=h3#warp-vps-hy2"
SS_URI="ss://$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w0)@${SERVER_IP}:${SS_PORT}#warp-vps-ss"

# 输出目录：脚本运行时的当前工作目录
OUT_DIR="$(pwd)"
if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
    OUT_OWNER="${SUDO_USER}:${SUDO_USER}"
else
    OUT_OWNER="$(id -un):$(id -gn)"
fi
info "客户端配置文件输出目录：${OUT_DIR}"

# 生成 sing-box 客户端 profile（同时含 Hysteria2 与 Shadowsocks 出站，默认 Hysteria2）
cat > "${OUT_DIR}/singbox.json" <<EOF
{
  "log": { "level": "info" },
  "dns": {
    "servers": [
      { "type": "https", "tag": "remote", "server": "1.1.1.1", "detour": "proxy" },
      { "type": "local", "tag": "local" }
    ],
    "rules": [
      { "rule_set": ["geosite-cn"], "server": "local" }
    ],
    "final": "remote"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
      "auto_route": true,
      "strict_route": true,
      "stack": "system"
    }
  ],
  "outbounds": [
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": ["vless-out", "hy2-out", "ss-out"],
      "default": "vless-out"
    },
    {
      "type": "vless",
      "tag": "vless-out",
      "server": "${SERVER_IP}",
      "server_port": ${VLESS_PORT},
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "packet_encoding": "xudp",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": {
          "enabled": true,
          "public_key": "${REALITY_PUBLIC_KEY}",
          "short_id": "${REALITY_SHORT_ID}"
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-out",
      "server": "${SERVER_IP}",
      "server_port": ${HY2_PORT},
      "password": "${HY2_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${HY2_SNI}",
        "alpn": ["h3"],
        "insecure": true
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-out",
      "server": "${SERVER_IP}",
      "server_port": ${SS_PORT},
      "method": "${SS_METHOD}",
      "password": "${SS_PASSWORD}"
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rule_set": [
      { "type": "remote", "tag": "geosite-category-ads-all", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs",
        "download_detour": "proxy" },
      { "type": "remote", "tag": "geosite-cn", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "download_detour": "proxy" },
      { "type": "remote", "tag": "geoip-cn", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "download_detour": "proxy" }
    ],
    "rules": [
      { "action": "sniff" },
      { "protocol": "dns", "action": "hijack-dns" },
      { "rule_set": ["geosite-category-ads-all"], "action": "reject" },
      { "ip_is_private": true, "outbound": "direct" },
      {
        "domain_suffix": [
          "steamcontent.com",
          "steamserver.net",
          "steamcdn-a.akamaihd.net",
          "steamstatic.com"
        ],
        "outbound": "direct"
      },
      {
        "domain": [
          "client-update.akamai.steamstatic.com",
          "media.steampowered.com"
        ],
        "outbound": "direct"
      },
      { "rule_set": ["geosite-cn", "geoip-cn"], "outbound": "direct" }
    ],
    "final": "proxy",
    "auto_detect_interface": true,
    "default_domain_resolver": "local"
  }
}
EOF
chmod 600 "${OUT_DIR}/singbox.json"

# 生成 Clash Verge / Mihomo 配置（同时含 Hysteria2 与 Shadowsocks，默认 Hysteria2）
cat > "${OUT_DIR}/clash.yaml" <<EOF
proxies:
  - name: "warp-vps-hy2"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${HY2_PORT}
    password: "${HY2_PASSWORD}"
    sni: ${HY2_SNI}
    skip-cert-verify: true
    alpn:
      - h3
  - name: "warp-vps-vless"
    type: vless
    server: ${SERVER_IP}
    port: ${VLESS_PORT}
    uuid: ${VLESS_UUID}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${REALITY_SNI}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${REALITY_PUBLIC_KEY}
      short-id: ${REALITY_SHORT_ID}
  - name: "warp-vps-ss"
    type: ss
    server: ${SERVER_IP}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - warp-vps-vless
      - warp-vps-hy2
      - warp-vps-ss

rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Providers/Ruleset/BanAD.yaml"
    path: ./ruleset/reject.yaml
    interval: 86400

  direct:
    type: http
    behavior: domain
    url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Providers/Ruleset/Direct.yaml"
    path: ./ruleset/direct.yaml
    interval: 86400

  cncidr:
    type: http
    behavior: ipcidr
    url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Providers/Ruleset/ChinaIp.yaml"
    path: ./ruleset/cncidr.yaml
    interval: 86400

  lancidr:
    type: http
    behavior: ipcidr
    url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Providers/Ruleset/LocalAreaNetwork.yaml"
    path: ./ruleset/lancidr.yaml
    interval: 86400

rules:
  - RULE-SET,reject,REJECT
  - RULE-SET,direct,DIRECT
  - RULE-SET,lancidr,DIRECT
  - DOMAIN-SUFFIX,steamcontent.com,DIRECT
  - DOMAIN-SUFFIX,steamserver.net,DIRECT
  - DOMAIN-SUFFIX,steamcdn-a.akamaihd.net,DIRECT
  - DOMAIN-SUFFIX,steamstatic.com,DIRECT
  - DOMAIN,client-update.akamai.steamstatic.com,DIRECT
  - DOMAIN,media.steampowered.com,DIRECT
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOIP,CN,DIRECT,no-resolve
  - RULE-SET,cncidr,DIRECT,no-resolve
  - MATCH,PROXY
EOF
chmod 600 "${OUT_DIR}/clash.yaml"

# 生成 VLESS URI + 二维码文件（供 NekoBox / v2rayN / v2rayNG / Shadowrocket 等导入）
{
    printf '%s\n\n' "${VLESS_URI}"
    qrencode -t ANSIUTF8 "${VLESS_URI}"
} > "${OUT_DIR}/shadow.txt"
chmod 600 "${OUT_DIR}/shadow.txt"

# 生成 SS URI + 二维码文件（备用）
{
    printf '%s\n\n' "${SS_URI}"
    qrencode -t ANSIUTF8 "${SS_URI}"
} > "${OUT_DIR}/ss.txt"
chmod 600 "${OUT_DIR}/ss.txt"

tee "${OUT_DIR}/info.txt" >/dev/null <<EOF
========== VLESS + REALITY + Vision (主，TCP) ==========
Server      : ${SERVER_IP}
Port        : ${VLESS_PORT} (TCP)
UUID        : ${VLESS_UUID}
Flow        : xtls-rprx-vision
SNI         : ${REALITY_SNI}
Dest        : ${REALITY_DEST}:${REALITY_DEST_PORT}
Public Key  : ${REALITY_PUBLIC_KEY}
Short ID    : ${REALITY_SHORT_ID}
VLESS URI   : ${VLESS_URI}
========================================================
========== Hysteria2 (UDP) ==========
Server   : ${SERVER_IP}
Port     : ${HY2_PORT} (UDP)
Password : ${HY2_PASSWORD}
SNI      : ${HY2_SNI}     (self-signed, insecure=1)
HY2 URI  : ${HY2_URI}
=====================================
========== Shadowsocks (备用，TCP) ==========
Server   : ${SERVER_IP}
Port     : ${SS_PORT} (TCP)
Method   : ${SS_METHOD}
Password : ${SS_PASSWORD}
SS URI   : ${SS_URI}
=============================================
WARP 出口 IP : ${WARP_IP}
AI 流量 (OpenAI / Anthropic / Claude / Claude Code / Google Gemini)
        由 sing-box 自动从 Cloudflare WARP 出口；其它流量直连 VPS 原 IP。

客户端导入（默认走 VLESS+REALITY，可在客户端切换到 Hysteria2 / SS）：
  - sing-box 官方客户端:           ${OUT_DIR}/singbox.json
    (New Profile → Type: Local → Import from file)
  - Clash Verge / Mihomo / ClashX: ${OUT_DIR}/clash.yaml
    (PROXY 组可选 warp-vps-vless / warp-vps-hy2 / warp-vps-ss)
  - VLESS URI (NekoBox / v2rayN / v2rayNG / Shadowrocket): ${OUT_DIR}/shadow.txt
  - SS URI (备用):                                          ${OUT_DIR}/ss.txt

服务管理：
  systemctl status sing-box
  systemctl status warp-svc
  journalctl -u sing-box -f

回滚 / 卸载：
  systemctl disable --now sing-box warp-svc
  apt-get purge -y sing-box cloudflare-warp
  rm -f /etc/apt/sources.list.d/{cloudflare-client,sagernet}.list
  rm -rf /etc/sing-box ${OUT_DIR}/info.txt ${OUT_DIR}/singbox.json ${OUT_DIR}/clash.yaml ${OUT_DIR}/shadow.txt ${OUT_DIR}/ss.txt
EOF

# 修正属主，确保 sudo 调用者可读
chown "${OUT_OWNER}" \
    "${OUT_DIR}/singbox.json" "${OUT_DIR}/clash.yaml" "${OUT_DIR}/shadow.txt" "${OUT_DIR}/ss.txt" "${OUT_DIR}/info.txt" 2>/dev/null || true

echo ""
cat "${OUT_DIR}/info.txt"
echo ""
echo "扫描以下二维码导入 Hysteria2 客户端："
qrencode -t ANSIUTF8 "${HY2_URI}"
echo ""
echo "扫描以下二维码导入 VLESS+REALITY+Vision 客户端："
qrencode -t ANSIUTF8 "${VLESS_URI}"
echo ""
echo "扫描以下二维码导入 SS 客户端 (备用)："
qrencode -t ANSIUTF8 "${SS_URI}"
echo ""
echo "================================================================"
echo " Clash Verge 配置 (HY2 + VLESS-REALITY + SS，已保存到 ${OUT_DIR}/clash.yaml)："
echo "================================================================"
cat "${OUT_DIR}/clash.yaml"
echo ""
info "全部完成。"
info "  - sing-box 配置 (VLESS 默认 / HY2 / SS): ${OUT_DIR}/singbox.json"
info "  - Clash 配置 (VLESS 默认 / HY2 / SS):    ${OUT_DIR}/clash.yaml"
info "  - VLESS URI 文件:                        ${OUT_DIR}/shadow.txt"
info "  - SS URI 文件 (备用):                    ${OUT_DIR}/ss.txt"
info "  - 汇总信息:                              ${OUT_DIR}/info.txt"
