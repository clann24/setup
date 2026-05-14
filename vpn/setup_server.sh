#!/usr/bin/env bash
#
# 一键部署：sing-box (Shadowsocks + Hysteria2 入口) + Cloudflare WARP (AI 流量出口)
#
# 适用：全新 Ubuntu / Debian VPS
# 客户端可走 Shadowsocks (TCP) 或 Hysteria2 (UDP/QUIC over TLS)；服务端按域名分流：
#   - OpenAI / Anthropic (含 Claude / Claude Code) / Google Gemini  → 经 WARP SOCKS5 出口
#   - 其它一切                          → VPS 直连
#
# 用法：sudo bash server_singbox_setup.sh
# 可通过环境变量覆盖：SS_PORT、SS_METHOD、SS_PASSWORD、HY2_PORT、HY2_PASSWORD、HY2_SNI
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*" >&2; }

# ===================== 可调参数 =====================
SS_PORT="${SS_PORT:-443}"
SS_METHOD="${SS_METHOD:-aes-256-gcm}"
SS_PASSWORD="${SS_PASSWORD:-$(openssl rand -base64 16)}"
HY2_PORT="${HY2_PORT:-8443}"
HY2_PASSWORD="${HY2_PASSWORD:-$(openssl rand -base64 16)}"
HY2_SNI="${HY2_SNI:-www.bing.com}"
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
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${SS_PORT},
      "method": "${SS_METHOD}",
      "password": "${SS_PASSWORD}"
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
    info "为 ufw 放行端口 ${SS_PORT} (TCP/UDP) 与 ${HY2_PORT} (UDP)..."
    ufw allow "${SS_PORT}/tcp" >/dev/null
    ufw allow "${SS_PORT}/udp" >/dev/null
    ufw allow "${HY2_PORT}/udp" >/dev/null
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

SS_URI="ss://$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w0)@${SERVER_IP}:${SS_PORT}#warp-vps"
HY2_URI="hysteria2://${HY2_PASSWORD}@${SERVER_IP}:${HY2_PORT}/?sni=${HY2_SNI}&insecure=1&alpn=h3#warp-vps-hy2"

# 输出目录：脚本运行时的当前工作目录
OUT_DIR="$(pwd)"
if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
    OUT_OWNER="${SUDO_USER}:${SUDO_USER}"
else
    OUT_OWNER="$(id -un):$(id -gn)"
fi
info "客户端配置文件输出目录：${OUT_DIR}"

# 生成 sing-box 客户端 profile（供 sing-box 官方客户端导入）
cat > "${OUT_DIR}/singbox.json" <<EOF
{
  "log": { "level": "info" },
  "dns": {
    "servers": [
      { "type": "https", "tag": "remote", "server": "1.1.1.1", "detour": "hy2-out" },
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
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rule_set": [
      { "type": "remote", "tag": "geosite-category-ads-all", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs",
        "download_detour": "hy2-out" },
      { "type": "remote", "tag": "geosite-cn", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "download_detour": "hy2-out" },
      { "type": "remote", "tag": "geoip-cn", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "download_detour": "hy2-out" }
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
    "final": "hy2-out",
    "auto_detect_interface": true,
    "default_domain_resolver": "local"
  }
}
EOF
chmod 600 "${OUT_DIR}/singbox.json"

# 生成 Clash Verge / Mihomo 配置（Hysteria2，保持与 vpn/clash.example.yaml rules 同步）
cat > "${OUT_DIR}/clash.yaml" <<EOF
proxies:
  - name: "warp-vps"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${HY2_PORT}
    password: "${HY2_PASSWORD}"
    sni: ${HY2_SNI}
    skip-cert-verify: true
    alpn:
      - h3

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - warp-vps

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

# 生成 SS URI + 二维码文件（供 Shadowrocket / NekoBox / v2rayN / Outline 等普通 SS 客户端使用，作为 fallback）
{
    printf '%s\n\n' "${SS_URI}"
    qrencode -t ANSIUTF8 "${SS_URI}"
} > "${OUT_DIR}/shadow.txt"
chmod 600 "${OUT_DIR}/shadow.txt"

# 生成 Hysteria2 URI + 二维码文件
{
    printf '%s\n\n' "${HY2_URI}"
    qrencode -t ANSIUTF8 "${HY2_URI}"
} > "${OUT_DIR}/hy2.txt"
chmod 600 "${OUT_DIR}/hy2.txt"

tee "${OUT_DIR}/info.txt" >/dev/null <<EOF
========== Shadowsocks 连接信息 ==========
Server   : ${SERVER_IP}
Port     : ${SS_PORT}
Method   : ${SS_METHOD}
Password : ${SS_PASSWORD}
SS URI   : ${SS_URI}
==========================================
========== Hysteria2 连接信息 ==========
Server   : ${SERVER_IP}
Port     : ${HY2_PORT} (UDP)
Password : ${HY2_PASSWORD}
SNI      : ${HY2_SNI}     (self-signed, insecure=1)
HY2 URI  : ${HY2_URI}
==========================================
WARP 出口 IP : ${WARP_IP}
AI 流量 (OpenAI / Anthropic / Claude / Claude Code / Google Gemini)
        由 sing-box 自动从 Cloudflare WARP 出口；其它流量直连 VPS 原 IP。

客户端导入（任选其一，推荐 Hysteria2）：
  - 普通 SS 客户端 (fallback):              ${OUT_DIR}/shadow.txt
  - Hysteria2 客户端 (NekoBox / v2rayN 等): ${OUT_DIR}/hy2.txt
  - Clash Verge / Mihomo / ClashX:          ${OUT_DIR}/clash.yaml     (Hysteria2)
  - sing-box 官方客户端:                    ${OUT_DIR}/singbox.json   (Hysteria2)
    (New Profile → Type: Local → Import from file)

服务管理：
  systemctl status sing-box
  systemctl status warp-svc
  journalctl -u sing-box -f

回滚 / 卸载：
  systemctl disable --now sing-box warp-svc
  apt-get purge -y sing-box cloudflare-warp
  rm -f /etc/apt/sources.list.d/{cloudflare-client,sagernet}.list
  rm -rf /etc/sing-box ${OUT_DIR}/info.txt ${OUT_DIR}/singbox.json ${OUT_DIR}/clash.yaml ${OUT_DIR}/shadow.txt ${OUT_DIR}/hy2.txt
EOF

# 修正属主，确保 sudo 调用者可读
chown "${OUT_OWNER}" \
    "${OUT_DIR}/singbox.json" "${OUT_DIR}/clash.yaml" "${OUT_DIR}/shadow.txt" "${OUT_DIR}/hy2.txt" "${OUT_DIR}/info.txt" 2>/dev/null || true

echo ""
cat "${OUT_DIR}/info.txt"
echo ""
echo "扫描以下二维码导入 SS 客户端 (fallback)："
qrencode -t ANSIUTF8 "${SS_URI}"
echo ""
echo "扫描以下二维码导入 Hysteria2 客户端："
qrencode -t ANSIUTF8 "${HY2_URI}"
echo ""
echo "================================================================"
echo " Clash Verge 配置 (已保存到 ${OUT_DIR}/clash.yaml)："
echo "================================================================"
cat "${OUT_DIR}/clash.yaml"
echo ""
info "全部完成。"
info "  - SS URI 文件 (fallback): ${OUT_DIR}/shadow.txt"
info "  - Hysteria2 URI 文件:     ${OUT_DIR}/hy2.txt"
info "  - Clash 配置 (HY2):       ${OUT_DIR}/clash.yaml"
info "  - sing-box 配置 (HY2):    ${OUT_DIR}/singbox.json"
info "  - 汇总信息:               ${OUT_DIR}/info.txt"
