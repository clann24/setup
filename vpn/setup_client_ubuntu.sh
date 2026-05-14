#!/usr/bin/env bash
#
# Ubuntu 客户端一键安装 sing-box 并以 TUN 模式连接到 VPS。
# 前提：当前目录（或第一个参数指定的路径）存在 singbox.json 配置文件。
#       (setup_server.sh 生成的 singbox.json 默认走 VLESS+REALITY，
#        可在 outbounds[type=selector tag=proxy] 中切换到 hy2-out / ss-out。)
#
# 用法:
#   sudo bash setup_client_ubuntu.sh [path/to/singbox.json]
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*" >&2; }

CONF_SRC="${1:-./singbox.json}"

[[ $EUID -eq 0 ]] || { error "请用 root 运行 (sudo bash $0)"; exit 1; }
[[ -f "$CONF_SRC" ]] || { error "找不到配置文件: $CONF_SRC"; exit 1; }

# 简单校验：确认配置中含有 proxy 选择器或 vless 出站
if ! grep -qE '"tag"[[:space:]]*:[[:space:]]*"proxy"|"type"[[:space:]]*:[[:space:]]*"vless"' "$CONF_SRC"; then
    warn "未在 $CONF_SRC 中检测到 proxy/vless 出站；该脚本预期使用 setup_server.sh 生成的配置。"
    read -rp "仍然继续？(y/N) " ans
    [[ "${ans,,}" == "y" ]] || exit 1
fi

if ! grep -qiE "ubuntu|debian" /etc/os-release; then
    warn "本脚本仅在 Ubuntu / Debian 测试过，其它发行版可能失败。"
    read -rp "继续？(y/N) " ans
    [[ "${ans,,}" == "y" ]] || exit 1
fi

info "安装依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl gnupg ca-certificates

info "添加 sing-box 仓库..."
curl -fsSL https://sing-box.app/gpg.key \
    | gpg --yes --dearmor -o /usr/share/keyrings/sagernet.gpg
echo "deb [signed-by=/usr/share/keyrings/sagernet.gpg] https://deb.sagernet.org/ * *" \
    > /etc/apt/sources.list.d/sagernet.list

apt-get update
apt-get install -y sing-box

info "确保 tun 内核模块可用..."
modprobe tun 2>/dev/null || true
echo tun > /etc/modules-load.d/sing-box-tun.conf

info "部署配置到 /etc/sing-box/config.json ..."
mkdir -p /etc/sing-box
[[ -f /etc/sing-box/config.json ]] && \
    cp /etc/sing-box/config.json "/etc/sing-box/config.json.bak.$(date +%s)"
install -m 0644 "$CONF_SRC" /etc/sing-box/config.json

info "校验 sing-box 配置..."
sing-box check -c /etc/sing-box/config.json

info "启用并启动 sing-box (开机自启)..."
systemctl enable sing-box >/dev/null 2>&1 || true
systemctl restart sing-box
sleep 2
if ! systemctl is-active --quiet sing-box; then
    error "sing-box 启动失败，最近日志："
    journalctl -u sing-box -n 50 --no-pager
    exit 1
fi

systemctl --no-pager --full status sing-box | head -n 20 || true

cat <<EOF

================ 完成 ================
配置文件 : /etc/sing-box/config.json
开机自启 : 已启用 (systemd: sing-box.service)

常用命令：
  systemctl status sing-box
  systemctl restart sing-box
  systemctl stop sing-box
  journalctl -u sing-box -f

验证出口 (走 Hysteria2 → VPS → 直连)：
  curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E '^ip='
验证 AI 流量走 WARP 出口：
  curl -s https://chatgpt.com/cdn-cgi/trace | grep -E '^(ip|warp)='

更换配置：
  sudo install -m 0644 config.json /etc/sing-box/config.json
  sudo systemctl restart sing-box

卸载：
  sudo systemctl disable --now sing-box
  sudo apt-get purge -y sing-box
  sudo rm -f /etc/apt/sources.list.d/sagernet.list /etc/modules-load.d/sing-box-tun.conf
  sudo rm -rf /etc/sing-box
======================================
EOF
