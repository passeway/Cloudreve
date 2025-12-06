#!/bin/bash

# 定义颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# 定义 Cloudreve 安装目录
INSTALL_DIR="/opt/Cloudreve"
SERVICE_FILE="/etc/systemd/system/cloudreve.service"

# 检查root权限
check_root() {
    [ "$EUID" -ne 0 ] && { echo -e "${RED}请使用 root 权限运行${RESET}"; exit 1; }
}

# 依赖安装
install_dependencies() {
    MISSING_DEPS=()
    for cmd in curl jq wget tar systemctl; do
        command -v $cmd &>/dev/null || MISSING_DEPS+=($cmd)
    done
    [ ${#MISSING_DEPS[@]} -eq 0 ] && return

    if command -v apt &>/dev/null; then
        apt update -y && apt install -y "${MISSING_DEPS[@]}"
    elif command -v yum &>/dev/null; then
        yum makecache -y && yum install -y "${MISSING_DEPS[@]}"
    elif command -v dnf &>/dev/null; then
        dnf makecache -y && dnf install -y "${MISSING_DEPS[@]}"
    else
        echo -e "${RED}不支持的包管理器${RESET}"; exit 1
    fi
    echo -e "${GREEN}依赖安装完成${RESET}"
}

# 架构检测
detect_architecture() {
    case $(uname -m) in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) echo -e "${RED}不支持的架构${RESET}"; exit 1 ;;
    esac
}

# 获取版本
get_latest_version() {
    LATEST_VERSION=$(curl -s https://api.github.com/repos/cloudreve/Cloudreve/releases/latest | jq -r .tag_name) || { echo -e "${RED}获取版本失败${RESET}"; exit 1; }
    echo -e "${GREEN}最新版本：$LATEST_VERSION${RESET}"
}

# 极简安装
install_cloudreve() {
    echo -e "${GREEN}开始安装 Cloudreve${RESET}"
    
    mkdir -p "$INSTALL_DIR"/{data,temp}
    install_dependencies
    detect_architecture
    get_latest_version
    
    cd "$INSTALL_DIR" || return
    wget -O cloudreve.tar.gz "https://github.com/cloudreve/Cloudreve/releases/download/${LATEST_VERSION}/cloudreve_${LATEST_VERSION#v}_linux_${ARCH}.tar.gz" || return
    tar -xzvf cloudreve.tar.gz && rm cloudreve.tar.gz
    chmod +x cloudreve
    
    # systemd 服务（无日志输出）
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Cloudreve Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/cloudreve
Restart=on-failure
RestartSec=3
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable cloudreve
    systemctl start cloudreve
    
    if systemctl is-active --quiet cloudreve; then
        echo -e "${GREEN}✅ 安装完成！${RESET}"
        echo -e "${YELLOW}访问：http://$(curl -s ifconfig.me):5212${RESET}"
    else
        echo -e "${RED}❌ 启动失败${RESET}"
    fi
}

# 完整管理菜单（去掉日志选项）
show_menu() {
    clear
    echo -e "${YELLOW}================================${RESET}"
    echo -e "${GREEN}       Cloudreve 一键管理${RESET}"
    echo -e "${YELLOW}================================${RESET}"
    echo "1) 安装 Cloudreve 服务"
    echo "2) 启动 Cloudreve 服务"
    echo "3) 停止 Cloudreve 服务"
    echo "4) 重启 Cloudreve 服务"
    echo "5) 查看 Cloudreve 状态"
    echo "7) 卸载 Cloudreve 服务"
    echo "0) 退出"
    echo -n -e "${YELLOW}请输入选项编号：${RESET} "
}

# 服务管理（无日志）
manage_service() {
    case $1 in
        start)
            systemctl start cloudreve
            echo -e "$(systemctl is-active --quiet cloudreve && echo "${GREEN}启动成功${RESET}" || echo "${RED}启动失败${RESET}")"
            ;;
        stop)
            systemctl stop cloudreve
            echo -e "$(systemctl is-stopped --quiet cloudreve && echo "${GREEN}停止成功${RESET}" || echo "${RED}停止失败${RESET}")"
            ;;
        restart)
            systemctl restart cloudreve
            echo -e "$(systemctl is-active --quiet cloudreve && echo "${GREEN}重启成功${RESET}" || echo "${RED}重启失败${RESET}")"
            ;;
        status)
            systemctl status cloudreve --no-pager
            ;;
    esac
}

# 卸载
uninstall_cloudreve() {
    systemctl stop cloudreve 2>/dev/null || true
    systemctl disable cloudreve 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    read -rp "删除目录 $INSTALL_DIR？(y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] && rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}卸载完成${RESET}"
}

# 按键提示
press_enter() {
    echo; read -rp "按回车键继续..."
}

# 主程序
main() {
    check_root
    while true; do
        show_menu
        read -r choice
        case $choice in
            1) install_cloudreve ;;
            2) manage_service start ;;
            3) manage_service stop ;;
            4) manage_service restart ;;
            5) manage_service status ;;
            7) uninstall_cloudreve ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项${RESET}"; sleep 1 ;;
        esac
        press_enter
    done
}

main "$@"
