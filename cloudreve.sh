#!/bin/bash

# 定义颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# 定义 Cloudreve 安装目录
INSTALL_DIR="/opt/Cloudreve"
SERVICE_FILE="/etc/systemd/system/cloudreve.service"
LOG_FILE="$INSTALL_DIR/cloudreve.log"

# 检查是否具有超级用户权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用超级用户权限（sudo）运行此脚本${RESET}"
        exit 1
    fi
}

# 自动安装缺失的依赖工具
install_dependencies() {
    MISSING_DEPS=()
    for cmd in curl jq wget tar systemctl; do
        if ! command -v $cmd &> /dev/null; then
            MISSING_DEPS+=($cmd)
        fi
    done

    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        # 检测包管理器
        if command -v apt &> /dev/null; then
            PKG_MANAGER="apt"
            UPDATE_CMD="apt update -y"
            INSTALL_CMD="apt install -y"
        elif command -v yum &> /dev/null; then
            PKG_MANAGER="yum"
            UPDATE_CMD="yum makecache -y"
            INSTALL_CMD="yum install -y"
        elif command -v dnf &> /dev/null; then
            PKG_MANAGER="dnf"
            UPDATE_CMD="dnf makecache -y"
            INSTALL_CMD="dnf install -y"
        elif command -v pacman &> /dev/null; then
            PKG_MANAGER="pacman"
            UPDATE_CMD="pacman -Sy"
            INSTALL_CMD="pacman -S --noconfirm"
        else
            echo -e "${RED}未检测到支持的包管理器（apt, yum, dnf, pacman），请手动安装以下工具： ${MISSING_DEPS[@]}${RESET}"
            exit 1
        fi

        # 更新包列表
        if ! $UPDATE_CMD; then
            echo -e "${RED}无法更新包列表，请检查网络连接或包管理器配置${RESET}"
            exit 1
        fi

        # 安装缺失的依赖
        for pkg in "${MISSING_DEPS[@]}"; do
            if ! $INSTALL_CMD "$pkg"; then
                echo -e "${RED}无法安装 $pkg，请手动安装并重试${RESET}"
                exit 1
            fi
        done
        echo -e "${GREEN}依赖工具安装完成${RESET}"
    fi
}

# 检测系统架构并设置 ARCH 变量
detect_architecture() {
    MACHINE_ARCH=$(uname -m)
    case "$MACHINE_ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64 | arm64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${RED}当前系统架构 ($MACHINE_ARCH) 不受支持${RESET}"
            exit 1
            ;;
    esac
    echo "检测到系统架构：$MACHINE_ARCH -> $ARCH"
}

# 获取 Cloudreve 最新版本号
get_latest_version() {
    LATEST_VERSION=$(curl -s https://api.github.com/repos/cloudreve/Cloudreve/releases/latest | jq -r '.tag_name')
    if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
        echo -e "${RED}无法获取 Cloudreve 最新版本号${RESET}"
        exit 1
    fi
    echo -e "${GREEN}最新版本 Cloudreve：$LATEST_VERSION${RESET}"
}

# 获取适用于当前架构的下载链接
get_download_url() {
    DOWNLOAD_URL="https://github.com/cloudreve/Cloudreve/releases/download/${LATEST_VERSION}/cloudreve_${LATEST_VERSION#v}_linux_${ARCH}.tar.gz"
}

# 提示用户按回车键继续
press_enter() {
    echo ""
    read -rp "按回车键返回主菜单..." key
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${YELLOW}================================${RESET}"
    echo -e "${GREEN}       Cloudreve 一键管理${RESET}"
    echo -e "${YELLOW}================================${RESET}"
    echo "1) 安装 Cloudreve"
    echo "2) 启动 Cloudreve"
    echo "3) 停止 Cloudreve"
    echo "4) 重启 Cloudreve"
    echo "5) 查看 Cloudreve 状态"
    echo "6) 查看 Cloudreve 日志"
    echo "7) 卸载 Cloudreve"
    echo "0) 退出"
    echo -n -e "${YELLOW}请输入选项编号：${RESET} "
}

# 安装 Cloudreve（修复版）
install_cloudreve() {
    echo -e "${GREEN}开始安装 Cloudreve${RESET}"
    
    # 创建安装目录
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "创建目录 $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR" || { echo -e "${RED}无法创建目录 $INSTALL_DIR${RESET}"; press_enter; return; }
    else
        echo "Cloudreve 目录已存在：$INSTALL_DIR"
    fi
    
    # 创建 temp 目录
    mkdir -p "$INSTALL_DIR/temp"
    
    # 安装依赖
    install_dependencies
    
    # 检测架构
    detect_architecture
    
    # 获取最新版本
    get_latest_version
    
    # 构建下载链接
    get_download_url
    
    # 切换到安装目录
    if ! cd "$INSTALL_DIR"; then
        echo -e "${RED}无法切换到安装目录：$INSTALL_DIR${RESET}"
        press_enter
        return
    fi
    
    # 下载最新版本
    TAR_FILE="cloudreve_${LATEST_VERSION#v}_linux_${ARCH}.tar.gz"
    if [ -f "cloudreve" ]; then
        echo "检测到已有 cloudreve 二进制，跳过下载"
    else
        echo "下载 Cloudreve $LATEST_VERSION..."
        if ! wget -O "$TAR_FILE" "$DOWNLOAD_URL"; then
            echo -e "${RED}下载 $DOWNLOAD_URL 失败，请检查网络连接或下载链接${RESET}"
            press_enter
            return
        fi
        
        # 解压下载的文件
        if ! tar -xzvf "$TAR_FILE"; then
            echo -e "${RED}解压 $TAR_FILE 失败，请手动检查文件${RESET}"
            press_enter
            return
        fi
        
        # 删除下载的压缩包以节省空间
        rm -f "$TAR_FILE"
    fi
    
    # 赋予可执行权限
    chmod +x cloudreve
    
    # 创建 systemd 服务文件（即使首次配置没生成也先创建）
    echo "创建 systemd 服务文件..."
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
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    # 尝试首次运行生成配置（修复版：用 PID 管理 + 容错）
    echo "首次运行 Cloudreve 生成配置文件..."
    CLOUDREVE_PID=""
    
    if nohup ./cloudreve > "$LOG_FILE" 2>&1 & then
        CLOUDREVE_PID=$!
        echo "Cloudreve PID: $CLOUDREVE_PID"
        
        sleep 3
        
        # 检查进程是否还在
        if kill -0 $CLOUDREVE_PID 2>/dev/null; then
            echo "Cloudreve 正在运行，尝试优雅停止..."
            kill $CLOUDREVE_PID 2>/dev/null
            wait $CLOUDREVE_PID 2>/dev/null || true
        fi
    fi
    
    # 检查配置文件是否生成
    if [ -f "conf/conf.ini" ]; then
        echo -e "${GREEN}配置文件已生成${RESET}"
    else
        echo -e "${YELLOW}警告：未检测到配置文件，可能需要手动启动一次${RESET}"
    fi
    
    # 启用并启动服务
    systemctl enable cloudreve
    systemctl start cloudreve
    
    if systemctl is-active --quiet cloudreve; then
        echo -e "${GREEN}Cloudreve 安装完成！${RESET}"
        echo -e "${YELLOW}访问地址：http://$(curl -s ifconfig.me):5212${RESET}"
        echo -e "${YELLOW}首次访问请注册账号，注册后即为管理员${RESET}"
    else
        echo -e "${RED}服务启动失败，请检查状态：systemctl status cloudreve${RESET}"
    fi
    
    press_enter
}

# 服务管理函数
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
        logs)
            journalctl -u cloudreve -f
            ;;
    esac
    press_enter
}

# 卸载 Cloudreve
uninstall_cloudreve() {
    echo -e "${YELLOW}开始卸载 Cloudreve${RESET}"
    systemctl stop cloudreve 2>/dev/null || true
    systemctl disable cloudreve 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    read -rp "是否删除安装目录 $INSTALL_DIR？(y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}Cloudreve 已完全卸载${RESET}"
    else
        echo -e "${GREEN}服务已卸载，安装目录保留${RESET}"
    fi
    press_enter
}

# 主程序
main() {
    check_root
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                install_cloudreve
                ;;
            2)
                manage_service "start"
                ;;
            3)
                manage_service "stop"
                ;;
            4)
                manage_service "restart"
                ;;
            5)
                manage_service "status"
                ;;
            6)
                manage_service "logs"
                ;;
            7)
                uninstall_cloudreve
                ;;
            0)
                echo -e "${GREEN}再见！${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新输入${RESET}"
                sleep 1
                ;;
        esac
    done
}

main "$@"
