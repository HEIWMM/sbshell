#!/bin/bash
# 网络测速脚本 - 测试国内和国外下载速度
# 需要提前安装：curl 和 speedtest-cli（国外测速）
# 镜像点配置（可自行增删）
MIRRORS=(
    "阿里云国内镜像|https://mirrors.aliyun.com/ubuntu-releases/22.04/ubuntu-22.04-live-server-amd64.iso"
    "腾讯云国内镜像|https://mirrors.tencent.com/ubuntu-releases/22.04/ubuntu-22.04-live-server-amd64.iso"
    "Linode东京节点|http://speedtest.tokyo.linode.com/100MB-tokyo.bin"
    "Linode新加坡节点|http://speedtest.singapore.linode.com/100MB-singapore.bin"
)
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
# 检查必要工具
check_dependencies() {
    local missing=0
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}错误：需要安装 curl 工具${NC}"
        missing=1
    fi
    if ! command -v bc &> /dev/null; then
        echo -e "${RED}错误：需要安装 bc 工具${NC}"
        missing=1
    fi
    if [ $missing -eq 1 ]; then
        exit 1
    fi

    if ! command -v speedtest-cli &> /dev/null; then
        echo -e "${YELLOW}警告：未安装 speedtest-cli，将跳过国际测速${NC}"
        return 1
    fi
    return 0
}
# 测试下载速度（参数：URL 描述）
test_download() {
    local url="$1"
    local desc="$2"

    echo -e "\n${GREEN}正在测试 ${desc} 下载速度...${NC}"
    echo -e "下载源: ${url}"

    # 使用curl测试下载速度（限时10秒）
    local start_time end_time elapsed_time downloaded_bytes download_speed
    start_time=$(date +%s.%N)
    downloaded_bytes=$(curl -s --max-time 10 -w '%{size_download}' -o /dev/null "$url")
    end_time=$(date +%s.%N)

    # 防止 bc 报错
    if [[ -z "$downloaded_bytes" || "$downloaded_bytes" -eq 0 ]]; then
        echo -e "${RED}测试失败：无法连接或超时${NC}"
        return
    fi

    elapsed_time=$(echo "$end_time - $start_time" | bc)
    # 防止除以0
    if [[ $(echo "$elapsed_time == 0" | bc) -eq 1 ]]; then
        echo -e "${RED}测试失败：测速时间为0${NC}"
        return
    fi
    download_speed=$(echo "scale=2; $downloaded_bytes / $elapsed_time / 1024" | bc)

    echo -e "下载速度: ${YELLOW}${download_speed} KB/s${NC}"
    echo -e "用时: ${elapsed_time} 秒"
}

# 国际测速（使用speedtest-cli）
test_international() {
    if ! command -v speedtest-cli &> /dev/null; then
        return
    fi

    echo -e "\n${GREEN}=== 正在使用 speedtest-cli 测试国际网络 ===${NC}"
    speedtest-cli --simple
}

main() {
    check_dependencies

    echo -e "\n${GREEN}=== 开始网络测速 ===${NC}"

    # 遍历所有镜像点
    for mirror in "${MIRRORS[@]}"; do
        desc="${mirror%%|*}"
        url="${mirror##*|}"
        test_download "$url" "$desc"
    done

    # 使用speedtest-cli测试
    test_international

    echo -e "\n${GREEN}=== 测速完成 ===${NC}"
}

main
