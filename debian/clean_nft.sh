#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 配置参数（与 configure_tproxy.sh 保持一致）
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')

# 清理 sing-box 相关防火墙规则
echo -e "${CYAN}清理 sing-box 相关防火墙规则...${NC}"

# 1. 清理 nftables 规则
if nft list table inet sing-box &>/dev/null; then
    echo -e "${CYAN}删除 sing-box 防火墙表...${NC}"
    nft delete table inet sing-box
    echo -e "${GREEN}sing-box 防火墙表已删除${NC}"
else
    echo -e "${CYAN}未发现 sing-box 防火墙表${NC}"
fi

# 2. 清理 IP 规则
echo -e "${CYAN}清理 IP 路由规则...${NC}"
if ip rule show | grep -q "fwmark 0x$PROXY_FWMARK lookup $PROXY_ROUTE_TABLE"; then
    ip rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null
    echo -e "${GREEN}IP 路由规则已删除${NC}"
else
    echo -e "${CYAN}未发现 IP 路由规则${NC}"
fi

# 3. 清理路由表
echo -e "${CYAN}清理路由表...${NC}"
if ip route show table $PROXY_ROUTE_TABLE 2>/dev/null | grep -q "local default"; then
    ip route del local default dev "${INTERFACE}" table $PROXY_ROUTE_TABLE 2>/dev/null
    echo -e "${GREEN}路由表已清理${NC}"
else
    echo -e "${CYAN}未发现需要清理的路由表${NC}"
fi

# 4. 检查并删除可能的其他 sing-box 相关链
if nft list chains 2>/dev/null | grep -q "sing-box"; then
    echo -e "${CYAN}发现其他 sing-box 相关链，正在清理...${NC}"
    # 删除所有包含 sing-box 的链
    nft list chains 2>/dev/null | grep "sing-box" | while read -r line; do
        table=$(echo "$line" | awk '{print $3}')
        chain=$(echo "$line" | awk '{print $4}')
        if [ -n "$table" ] && [ -n "$chain" ]; then
            nft delete chain "$table" "$chain" 2>/dev/null
        fi
    done
    echo -e "${GREEN}其他 sing-box 相关链已清理${NC}"
fi

# 5. 清理配置文件（可选，保留配置文件以备后用）
# if [ -f "/etc/sing-box/nft/nftables.conf" ]; then
#     echo -e "${CYAN}删除 sing-box nftables 配置文件...${NC}"
#     rm -f "/etc/sing-box/nft/nftables.conf"
#     echo -e "${GREEN}配置文件已删除${NC}"
# fi

echo -e "${GREEN}sing-box 所有防火墙和路由规则清理完毕${NC}"
