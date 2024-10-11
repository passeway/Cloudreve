#!/bin/bash

# 定义 Cloudreve 安装目录
INSTALL_DIR="/opt/Cloudreve"
SERVICE_FILE="/etc/systemd/system/cloudreve.service"
LOG_FILE="$INSTALL_DIR/cloudreve.log"

# 检查是否具有超级用户权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "请使用超级用户权限（sudo）运行此脚本"
        exit 1
    fi
}

# 检查必要工具是否已安装
check_dependencies() {
    for cmd in curl jq wget tar systemctl uname; do
        if ! command -v $cmd &> /dev/null; then
            echo "需要安装 $cmd，请先安装它"
            exit 1
        fi
    done
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
            echo "当前系统架构 ($MACHINE_ARCH) 不受支持。"
            exit 1
            ;;
    esac
    echo "检测vps系统架构：$ARCH"
}

# 获取 Cloudreve 最新版本号
get_latest_version() {
    LATEST_VERSION=$(curl -s https://api.github.com/repos/cloudreve/Cloudreve/releases/latest | jq -r '.tag_name')
    if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
        echo "无法获取 Cloudreve 最新版本号"
        exit 1
    fi
    echo "最新版本Cloudreve：$LATEST_VERSION"
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

# 安装 Cloudreve
install_cloudreve() {
    echo "开始安装 Cloudreve"

    # 创建安装目录
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "创建目录$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR" || { echo "无法创建目录 $INSTALL_DIR"; press_enter; return; }
    else
        echo "Cloudreve 目录已存在$INSTALL_DIR"
    fi

    # 检查依赖
    check_dependencies

    # 检测架构
    detect_architecture

    # 获取最新版本
    get_latest_version

    # 构建下载链接
    get_download_url

    # 切换到安装目录
    if ! cd "$INSTALL_DIR"; then
        echo "无法切换到安装目录：$INSTALL_DIR"
        press_enter
        return
    fi

    # 下载最新版本
    TAR_FILE="cloudreve_${LATEST_VERSION#v}_linux_${ARCH}.tar.gz"
    if ! wget -O "$TAR_FILE" "$DOWNLOAD_URL"; then
        echo "下载 $DOWNLOAD_URL 失败，请检查网络连接或下载链接"
        press_enter
        return
    fi

    # 解压下载的文件
    if ! tar -xzvf "$TAR_FILE"; then
        echo "解压 $TAR_FILE 失败，请手动检查文件"
        press_enter
        return
    fi

    # 删除下载的压缩包以节省空间
    rm -f "$TAR_FILE"

    # 赋予可执行权限
    chmod +x cloudreve

    # 运行 Cloudreve 以生成初始配置
    nohup ./cloudreve > "$LOG_FILE" 2>&1 &
    sleep 5

    # 检查 Cloudreve 是否已启动
    if ! pgrep -f cloudreve > /dev/null; then
        echo "Cloudreve 启动失败，请检查日志文件。"
        press_enter
        return
    fi

    # 创建 systemd 服务文件
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Cloudreve
Documentation=https://docs.cloudreve.org
After=network.target

[Service]
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/cloudreve
Restart=on-abnormal
RestartSec=5s
KillMode=mixed

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd 守护进程
    systemctl daemon-reload

    # 启动并启用 Cloudreve 服务
    systemctl start cloudreve
    systemctl enable cloudreve
    systemctl restart cloudreve
    
    # 获取本机IP地址
    HOST_IP=$(curl -s http://checkip.amazonaws.com)

    echo "Cloudreve 安装并启动 http://${HOST_IP}:5212"
    cat "$LOG_FILE"
    press_enter
}

# 卸载 Cloudreve
uninstall_cloudreve() {

    # 停止服务
    if systemctl is-active --quiet cloudreve; then
        systemctl stop cloudreve
    else
        echo "Cloudreve 服务未运行，跳过停止步骤"
    fi

    # 禁用服务
    if systemctl is-enabled --quiet cloudreve; then
        systemctl disable cloudreve
    else
        echo "Cloudreve 服务未启用，跳过禁用步骤"
    fi

    # 移除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
    else
        echo "$SERVICE_FILE 不存在，跳过"
    fi

    # 重新加载 systemd 守护进程
    systemctl daemon-reload

    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
    else
        echo "$INSTALL_DIR 不存在，跳过"
    fi

    echo "Cloudreve 已成功卸载"
    press_enter
}

# 重启 Cloudreve
restart_cloudreve() {

    if systemctl is-active --quiet cloudreve; then
        systemctl restart cloudreve
        echo "Cloudreve 已重启"
    else
        echo "Cloudreve 服务未运行，尝试启动"
        systemctl start cloudreve
        if [ $? -eq 0 ]; then
            echo "Cloudreve 已启动"
        else
            echo "无法启动 Cloudreve 服务"
        fi
    fi

    press_enter
}

# 查看 Cloudreve 状态
status_cloudreve() {
    systemctl status cloudreve
    press_enter
}

# 查看 Cloudreve 密码
view_password() {

    if [ -f "$LOG_FILE" ]; then
        echo "Cloudreve 管理员信息："
        grep -i 'admin' "$LOG_FILE" || echo "未找到管理员信息。"
    else
        echo "日志文件不存在，无法查看密码。"
    fi
    press_enter
}

# 显示菜单
show_menu() {
    clear
    echo "============================="
    echo "     Cloudreve 管理脚本      "
    echo "============================="
    echo "1. 安装 Cloudreve 服务"
    echo "2. 卸载 Cloudreve 服务"
    echo "3. 重启 Cloudreve 服务"
    echo "4. 查看 Cloudreve 状态"
    echo "5. 查看 Cloudreve 密码"
    echo "0. 退出"
    echo "============================="
}

# 主循环
main() {
    check_root

    while true; do
        show_menu
        read -rp "请输入选项编号：" choice
        case $choice in
            1)
                install_cloudreve
                ;;
            2)
                uninstall_cloudreve
                ;;
            3)
                restart_cloudreve
                ;;
            4)
                status_cloudreve
                ;;
            5)
                view_password
                ;;
            0)
                
                exit 0
                ;;
            *)
                echo "无效选项，请输入 0-5 之间的数字。"
                press_enter
                ;;
        esac
    done
}

# 执行主函数
main