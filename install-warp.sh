#!/usr/bin/env bash
set -e

echo "=== IPv6 VPS 安装 WARP（仅 IPv4 走 WARP）==="

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

USE_WARP_CLI="n"

echo -e "${YELLOW}是否临时启用 warp-cli 全局加速安装依赖？${RESET}"
echo "说明："
echo " - 可加快 apt / wget / curl"
echo " - 可能导致 SSH 断开"
echo " - 建议有 VNC / 控制台的用户使用"
echo " - 默认不启用"
echo
read -r -p "是否启用？[y/N]: " USE_WARP_CLI
USE_WARP_CLI=${USE_WARP_CLI:-n}

if [[ "${USE_WARP_CLI}" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}[临时加速] 安装 warp-cli...${RESET}"

    apt update
    apt install -y curl wget gnupg lsb-release ca-certificates

    mkdir -p /usr/share/keyrings

    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp.gpg || true

    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/cloudflare-client.list

    apt update || true
    apt install -y cloudflare-warp || true

    if command -v warp-cli >/dev/null 2>&1; then
        echo -e "${GREEN}[临时加速] 自动同意协议并连接 warp-cli...${RESET}"

        echo "y" | warp-cli registration new >/dev/null 2>&1 || true
        warp-cli mode warp >/dev/null 2>&1 || true
        warp-cli connect >/dev/null 2>&1 || true

        sleep 3
        echo -e "${YELLOW}[临时加速] 当前出口:${RESET}"
        curl -s ip.sb || true
        echo
    else
        echo -e "${RED}[临时加速] warp-cli 安装失败，跳过加速。${RESET}"
    fi
else
    echo -e "${YELLOW}已跳过 warp-cli 临时加速。${RESET}"
fi

echo -e "${GREEN}[1/7] 安装依赖...${RESET}"
apt update
apt install -y wireguard wireguard-tools curl wget resolvconf openresolv \
    || apt install -y wireguard wireguard-tools curl wget

if command -v warp-cli >/dev/null 2>&1; then
    echo -e "${GREEN}关闭 warp-cli 全局代理，避免影响最终路由...${RESET}"
    echo "y" | warp-cli disconnect >/dev/null 2>&1 || true
fi

echo -e "${GREEN}[2/7] 配置 IPv6 DNS...${RESET}"
cat > /etc/resolv.conf <<EOF
nameserver 2606:4700:4700::1111
nameserver 2001:4860:4860::8888
EOF

echo -e "${GREEN}[3/7] 下载 wgcf...${RESET}"
if ! command -v wgcf >/dev/null 2>&1; then
    OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH_NAME="amd64"

    wget -O wgcf "https://hub.glowp.xyz/github.com/ViRb3/wgcf/releases/latest/download/wgcf_${OS_NAME}_${ARCH_NAME}" \
        || wget -O wgcf "https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_${OS_NAME}_${ARCH_NAME}"

    chmod +x wgcf
    mv wgcf /usr/local/bin/wgcf
fi

echo -e "${GREEN}[4/7] 注册 WARP...${RESET}"
if [ ! -f wgcf-account.toml ]; then
    yes | wgcf register
fi

echo -e "${GREEN}[5/7] 生成配置...${RESET}"
wgcf generate

echo -e "${GREEN}[6/7] 配置 WireGuard（仅 IPv4 走 WARP）...${RESET}"
mkdir -p /etc/wireguard
cp wgcf-profile.conf /etc/wireguard/wgcf.conf

sed -i 's#AllowedIPs = .*#AllowedIPs = 0.0.0.0/0#g' /etc/wireguard/wgcf.conf
sed -i 's#Endpoint = .*#Endpoint = [2606:4700:d0::a29f:c001]:2408#g' /etc/wireguard/wgcf.conf

grep -q '^MTU' /etc/wireguard/wgcf.conf \
    || sed -i '/^\[Interface\]/a MTU = 1280' /etc/wireguard/wgcf.conf

echo -e "${GREEN}[7/7] 启动 WARP WireGuard...${RESET}"
wg-quick down wgcf 2>/dev/null || true
wg-quick up wgcf

systemctl enable wg-quick@wgcf

echo
echo -e "${GREEN}=== 测试结果 ===${RESET}"

echo -e "${YELLOW}IPv4 出口（应该是 WARP）:${RESET}"
curl -4 ip.sb || echo -e "${RED}IPv4 测试失败${RESET}"

echo
echo -e "${YELLOW}IPv6 出口（应该是原生）:${RESET}"
curl -6 ip.sb || echo -e "${RED}IPv6 测试失败${RESET}"

echo
echo -e "${GREEN}完成！现在：${RESET}"
echo "✔ SSH / 入站：走原生 IPv6"
echo "✔ 出口 IPv4：走 WARP"
echo "✔ IPv6 保持原生"
