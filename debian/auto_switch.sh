#!/bin/bash

#################################################
# 描述: Sing-box 自动节点切换脚本
# 版本: 1.0.0
# 功能: 自动切换节点、监控连接质量、故障转移
#################################################

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 配置文件路径
CONFIG_FILE="/etc/sing-box/config.json"
SCRIPT_DIR="/etc/sing-box/scripts"
LOG_FILE="/var/log/sing-box-auto-switch.log"

# 默认配置
DEFAULT_TEST_URL="http://www.gstatic.com/generate_204"


# 日志函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# 检查sing-box状态
check_singbox_status() {
    if systemctl is-active --quiet sing-box; then
        return 0
    else
        return 1
    fi
}

# 获取当前选中的节点
get_current_node() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_message "ERROR" "配置文件不存在: $CONFIG_FILE"
        return 1
    fi
    
    # 尝试从sing-box API获取当前节点信息
    local api_url="http://192.168.31.59:9095"
    if curl -s "$api_url/proxies" >/dev/null 2>&1; then
        local current_node=$(curl -s "$api_url/proxies/手动切换" 2>/dev/null | grep -oP '"now":\s*"\K[^"]+' | cut -d'"' -f4)
        if [ -n "$current_node" ]; then
            echo "$current_node"
            return 0
        fi
    fi
    
    # 如果API不可用，从配置文件解析
    local current_node=$(grep -oP '"now":\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'"' -f4)
    echo "$current_node"
}

# 获取可用节点列表
get_available_nodes() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_message "ERROR" "配置文件不存在: $CONFIG_FILE"
        return 1
    fi
    
    local api_url="http://192.168.31.59:9095"
    # 从配置文件中提取节点名称
    local nodes=$(curl -s "$api_url/proxies" | jq -r '.proxies.GLOBAL.all[]')
    echo "$nodes"
}

# 切换到指定节点
switch_to_node() {
    local target_node="$1"
    local api_url="http://192.168.31.59:9095"
    
    log_message "INFO" "正在切换到节点: $target_node"
    
    # 通过API切换节点
    if curl -s -X PUT "$api_url/proxies/手动切换" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$target_node\"}" >/dev/null 2>&1; then
        log_message "INFO" "节点切换成功: $target_node"
        return 0
    else
        log_message "ERROR" "节点切换失败: $target_node"
        return 1
    fi
}

# 自动选择最佳节点（优化版）
auto_select_best_node() {
    local test_url="$1"
    local timeout="$2"
    local api_url="http://192.168.31.59:9095"

    log_message "INFO" "开始批量测试节点延迟..."

    # 获取所有节点名称
    mapfile -t available_nodes < <(curl -s "${api_url}/proxies" | jq -r '.proxies.GLOBAL.all[] | select(test("Pro-香港|Pro-美国"))')

    local best_node=""
    local best_latency=999999

    for node in "${available_nodes[@]}"; do
        log_message "INFO" "测试节点: $node"
        local encoded_node=$(echo -n "$node" | jq -sRr @uri)
        local delay=$(curl -s -G --data-urlencode "url=${test_url}" --data-urlencode "timeout=${timeout}" \
            "${api_url}/proxies/${encoded_node}/delay" | jq -r '.delay // empty')
        log_message "INFO" "测试节点: $node 延迟: $delay"
        if [[ "$delay" =~ ^[0-9]+$ ]] && [ "$delay" -lt "$best_latency" ]; then
            best_latency=$delay
            best_node="$node"
        fi
    done

    if [ -n "$best_node" ]; then
        log_message "INFO" "最佳节点: $best_node (延迟: ${best_latency}ms)"
        switch_to_node "$best_node"
        return 0
    else
        log_message "ERROR" "没有找到可用节点"
        return 1
    fi
}


# 显示当前状态
show_status() {
    echo -e "${CYAN}=========== Sing-box 自动切换状态 ===========${NC}"
    
    if check_singbox_status; then
        echo -e "${GREEN}✓ Sing-box 服务运行中${NC}"
    else
        echo -e "${RED}✗ Sing-box 服务未运行${NC}"
    fi
    
    local current_node=$(get_current_node)
    if [ -n "$current_node" ]; then
        echo -e "${GREEN}当前节点: $current_node${NC}"
    else
        echo -e "${RED}无法获取当前节点信息${NC}"
    fi
    
    echo -e "${CYAN}可用节点:${NC}"
    local available_nodes=$(get_available_nodes)

    # 使用 mapfile 将 available_nodes 转换为数组
    mapfile -t available_nodes_array < <(echo "$available_nodes")

    # 遍历数组并输出节点名称
    for node in "${available_nodes_array[@]}"; do
        echo "  - $node"
    done
    
    echo -e "${CYAN}=============================================${NC}"
}


# 主菜单
show_menu() {
    echo -e "${CYAN}=========== Sing-box 自动切换管理 ===========${NC}"
    echo -e "${GREEN}1. 显示当前状态${NC}"
    echo -e "${GREEN}2. 自动选择最佳节点${NC}"
    echo -e "${GREEN}3. 查看日志${NC}"
    echo -e "${GREEN}0. 退出${NC}"
    echo -e "${CYAN}=============================================${NC}"
}

# 处理用户选择
handle_choice() {
    read -rp "请选择操作: " choice
    case $choice in
        1)
            show_status
            ;;
        2)
            auto_select_best_node "$DEFAULT_TEST_URL" 3000
            ;;
        3)
            if [ -f "$LOG_FILE" ]; then
                tail -f "$LOG_FILE"
            else
                echo -e "${RED}日志文件不存在${NC}"
            fi
            ;;
        0)
            echo -e "${CYAN}退出${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项${NC}"
            ;;
    esac
}

# 主函数
main() {
    # 检查sing-box是否安装
    if ! command -v sing-box &> /dev/null; then
        echo -e "${RED}Sing-box 未安装，请先安装 Sing-box${NC}"
        exit 1
    fi
    
    # 检查配置文件是否存在
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Sing-box 配置文件不存在: $CONFIG_FILE${NC}"
        exit 1
    fi
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 交互式菜单
    while true; do
        show_menu
        handle_choice
        echo
        read -rp "按回车键继续..."
    done
}

# 脚本入口 只在脚本被直接执行时才调用main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
