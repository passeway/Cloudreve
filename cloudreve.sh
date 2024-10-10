#!/bin/bash

# 检查是否具有超级用户权限
if [ "$EUID" -ne 0 ]; then 
  echo "请使用超级用户权限（sudo）运行此脚本"
  exit
fi

# 定义 Cloudreve 安装目录
INSTALL_DIR="/etc/Cloudreve"

# 检查并创建 /etc/Cloudreve 目录
if [ ! -d "$INSTALL_DIR" ]; then
    echo "创建 Cloudreve 目录：$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
else
    echo "Cloudreve 目录已存在：$INSTALL_DIR"
fi

# 获取 Cloudreve 最新版本号
LATEST_VERSION=$(curl -s https://api.github.com/repos/cloudreve/Cloudreve/releases/latest | jq -r '.tag_name')

# 构建 Linux 版本的下载链接
DOWNLOAD_URL="https://github.com/cloudreve/Cloudreve/releases/download/${LATEST_VERSION}/cloudreve_${LATEST_VERSION#v}_linux_amd64.tar.gz"

# 切换到安装目录
cd "$INSTALL_DIR"

# 使用 wget 下载最新版本到指定目录
echo "正在下载 Cloudreve $LATEST_VERSION 到 $INSTALL_DIR..."
if ! wget $DOWNLOAD_URL; then
    echo "下载失败，请检查网络连接或下载链接。"
    exit 1
fi

# 下载完成后解压
echo "下载完成，开始解压..."
if ! tar -xzvf cloudreve_${LATEST_VERSION#v}_*.tar.gz; then
    echo "解压失败，请手动检查文件。"
    exit 1
fi

# 赋予 cloudreve 可执行权限
sudo chmod +x cloudreve

# 手动运行一次 Cloudreve 以获取初始管理员信息
echo "正在运行 Cloudreve 获取初始管理员信息..."
sudo nohup ./cloudreve > cloudreve.log 2>&1 &

# 创建 systemd 服务文件
SERVICE_FILE="/usr/lib/systemd/system/cloudreve.service"

sudo bash -c "cat > $SERVICE_FILE <<EOF
[Unit]
Description=Cloudreve
Documentation=https://docs.cloudreve.org
After=network.target
After=mysqld.service
Wants=network.target

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
EOF"

# 重新加载 systemd 守护进程
sudo systemctl daemon-reload

# 启动并启用 Cloudreve 服务
sudo systemctl start cloudreve
# 设置 Cloudreve 开机自启动
sudo systemctl enable cloudreve

# 查看 Cloudreve 管理员信息
echo "请查看 Cloudreve 管理员信息:"
cat /etc/Cloudreve/cloudreve.log
