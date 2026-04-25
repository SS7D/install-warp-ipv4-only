#!/usr/bin/env bash
set -e

echo "=== IPv6 VPS 安装 WARP（仅IPv4走WARP）==="

# 颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# =========================
# 可选加速（warp-cli）
# =========================
echo -e "${YELLOW}是否启用 WARP 全局加速下载依赖？${RESET}"
echo -e "${YELLOW}⚠️ 说明：${RESET}"
echo " - 可加快 apt / wget / curl 速度"
echo " - 可能导致 SSH 断开"
echo " - 建议有 VNC / 控制台再开启"
echo
read -p "是否启用？[y/N]: " use_warp

if [[ "$use_warp" == "y" || "$use_warp" == "Y" ]]; then
    echo -e "${GREEN}启用 warp-cli 全局加速...${RESET}"

    apt update
    apt install -y curl gnupg lsb-release

    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp.gpg

    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/cloudflare-client.list

    apt update
    apt install -y cloudflare-warp || true

    warp-cli registration new || true
    warp-cli mode warp || true
    warp-cli connect || true

    echo -e "${GREEN}WARP 加速已开启${RESET}"
else
    echo -e "${YELLOW}跳过 WARP 加速${RESET}"
fi

# =========================
# 正常安装依赖
# =========================
echo -e "${GREEN}[1/7] 安装依赖...${RESET}"
apt update
apt install -y wireguard wireguard-tools curl wget resolvconf || apt install -y wireguard curl wget

# =========================
# 关闭 warp-cli（如果启用过）
# =========================
if command -v warp-cli >/dev/null 2>&1; then
    echo -e "${GREEN}关闭 warp-cli 全局代理...${RESET}"
    warp-cli disconnect || true
fi

# =========================
echo -e "${GREEN}[2/7] 配置 IPv6 DNS...${RESET}"
cat > /etc/resolv.conf <<EOF
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
EOF

# =========================
echo -e "${GREEN}[3/7] 下载 wgcf...${RESET}"

if ! command -v wgcf >/dev/null 2>&1; then
    wget -O wgcf https://hub.glowp.xyz/github.com/ViRb3/wgcf/releases/latest/download/wgcf_$(uname -s | tr '[:upper:]' '[:lower:]')_amd64 \
    || wget -O wgcf https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_$(uname -s | tr '[:upper:]' '[:lower:]')_amd64
    
    chmod +x wgcf
    mv wgcf /usr/local/bin/
fi

# =========================
echo -e "${GREEN}[4/7] 注册 WARP...${RESET}"
if [ ! -f wgcf-account.toml ]; then
    yes | wgcf register
fi

# =========================
echo -e "${GREEN}[5/7] 生成配置...${RESET}"
wgcf generate

# =========================
echo -e "${GREEN}[6/7] 配置 WireGuard（仅IPv4走WARP）...${RESET}"
mkdir -p /etc/wireguard
cp wgcf-profile.conf /etc/wireguard/wgcf.conf

# 关键：只让 IPv4 走 WARP
sed -i 's#AllowedIPs = .*#AllowedIPs = 0.0.0.0/0#g' /etc/wireguard/wgcf.conf

# 强制 IPv6 Endpoint
sed -i 's#Endpoint = .*#Endpoint = [2606:4700:d0::a29f:c001]:2408#g' /etc/wireguard/wgcf.conf

# 设置 MTU
grep -q '^MTU' /etc/wireguard/wgcf.conf || sed -i '/^\[Interface\]/a MTU = 1280' /etc/wireguard/wgcf.conf

# =========================
echo -e "${GREEN}[7/7] 启动 WARP...${RESET}"
wg-quick down wgcf 2>/dev/null || true
wg-quick up wgcf

systemctl enable wg-quick@wgcf

# =========================
echo
echo -e "${GREEN}=== 测试结果 ===${RESET}"

echo -e "${YELLOW}IPv4 出口（应该是 WARP）:${RESET}"
curl -4 ip.sb || echo -e "${RED}IPv4 测试失败${RESET}"

echo
echo -e "${YELLOW}IPv6 出口（应该是原生）:${RESET}"
curl -6 ip.sb || echo -e "${RED}IPv6 测试失败${RESET}"

echo
echo -e "${GREEN}完成！现在：${RESET}"
echo -e "✔ SSH / 入站：走原生 IPv6"
echo -e "✔ 出口 IPv4：走 WARP"
echo -e "✔ IPv6 保持原生"
