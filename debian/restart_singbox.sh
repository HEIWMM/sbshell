#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 脚本下载目录
SCRIPT_DIR="/etc/sing-box/scripts"

# 带时间戳的日志函数
log_with_timestamp() {
    local color="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}[${timestamp}] ${message}${NC}"
}

# 检查当前模式
check_mode() {
    if nft list chain inet sing-box prerouting_tproxy &>/dev/null || nft list chain inet sing-box output_tproxy &>/dev/null; then
        echo "TProxy 模式"
    else
        echo "TUN 模式"
    fi
}

# 应用防火墙规则
apply_firewall() {
    MODE=$(grep -oP '(?<=^MODE=).*' /etc/sing-box/mode.conf)
    if [ "$MODE" = "TProxy" ]; then
        bash "$SCRIPT_DIR/configure_tproxy.sh"
    elif [ "$MODE" = "TUN" ]; then
        bash "$SCRIPT_DIR/configure_tun.sh"
    fi
}

# 停止 sing-box 服务
stop_singbox() {
    echo -e "${CYAN}正在停止 sing-box 服务...${NC}"
    sudo systemctl stop sing-box

    if ! systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}sing-box 已停止${NC}"
        
        # 自动清理防火墙规则
        echo -e "${CYAN}执行清理防火墙规则...${NC}"
        bash "$SCRIPT_DIR/clean_nft.sh"
        echo -e "${GREEN}防火墙规则清理完毕${NC}"
    else
        echo -e "${RED}停止 sing-box 失败，请检查日志${NC}"
        exit 1
    fi
}

# 启动 sing-box 服务
start_singbox() {
    echo -e "${CYAN}检测是否处于非代理环境...${NC}"
    STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://www.google.com")

    if [ "$STATUS_CODE" -eq 200 ]; then
        echo -e "${CYAN}当前网络处于代理环境，跳过网络检查，直接启动 sing-box。${NC}"
    else
        echo -e "${CYAN}当前网络环境非代理网络，可以启动 sing-box。${NC}"
    fi

    sudo systemctl restart sing-box &>/dev/null
    
    apply_firewall

    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}sing-box 启动成功${NC}"
        mode=$(check_mode)
        echo -e "${MAGENTA}当前启动模式: ${mode}${NC}"
    else
        echo -e "${RED}sing-box 启动失败，请检查日志${NC}"
        exit 1
    fi
}

# 检查sing-box当前节点延迟
log_with_timestamp "${CYAN}" "脚本开始执行 - 检查sing-box当前节点延迟..."
# 引入自动切换节点脚本以便调用 auto_select_best_node
source /etc/sing-box/scripts/auto_switch.sh

# 获取当前节点名称
api_url="http://192.168.31.59:9095"
current_node=$(curl -s "$api_url/proxies/手动切换" | jq -r '.now // empty')
encoded_node=$(echo -n "$current_node" | jq -sRr @uri)
if [ -n "$current_node" ]; then
    # 检查当前节点延迟
    delay=$(curl -s -G --data-urlencode "url=http://www.gstatic.com/generate_204" --data-urlencode "timeout=3000" \
        "$api_url/proxies/$encoded_node/delay" | jq -r '.delay // empty')
    log_with_timestamp "${CYAN}" "当前节点: $current_node，延迟: $delay ms"
    if [[ "$delay" =~ ^[0-9]+$ ]]; then
        log_with_timestamp "${GREEN}" "当前节点连通正常"
    else
        # 当前节点无延迟，尝试自动切换节点
        log_with_timestamp "${CYAN}" "当前节点异常，尝试自动切换最佳节点..."
        auto_select_best_node "http://www.gstatic.com/generate_204" 3000
        switch_result=$?
        if [ $switch_result -eq 0 ]; then
            log_with_timestamp "${GREEN}" "已成功切换到可用节点，无需重启 sing-box"
        fi
    fi
fi



# 执行重启前检查网络状态
log_with_timestamp "${CYAN}" "检查网络连通性..."
STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://www.google.com")
log_with_timestamp "${CYAN}" "当前网络连通状态: ${STATUS_CODE}"
if [ "$STATUS_CODE" -eq 200 ] || [ "$STATUS_CODE" -eq 302 ]; then
    log_with_timestamp "${GREEN}" "脚本结束 - 当前网络连通正常，无需重启 sing-box"
    exit 0
fi


echo -e "${CYAN}网络连通异常，开始重启 sing-box...${NC}"

# 先停止服务
stop_singbox

# 等待一秒确保服务完全停止
sleep 1

# 再启动服务
start_singbox

log_with_timestamp "${GREEN}" "脚本结束 - sing-box 重启完成" 
