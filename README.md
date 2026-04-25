# 🌐 IPv6 VPS + WARP IPv4 出口配置说明

本项目用于在 **纯 IPv6 VPS** 上部署 **Cloudflare WARP（wgcf）**，实现：

- ✅ 保留原生 IPv6（用于 SSH / 入站）
- ✅ 获得 IPv4 出口（用于 GitHub / apt / curl）
- ✅ 不影响服务器访问
- ✅ 稳定运行（基于 WireGuard）

---

# 📌 架构说明

```text
客户端 → 原生 IPv6（2001:xxxx） → 服务器（入站）
服务器 → WARP（IPv4） → 外网（出站）
