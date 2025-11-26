#!/bin/bash

green="\033[1;32m"
colorend="\033[0m"


echo -e "${green}安装必要安装包${colorend}"
apk add bash curl sudo

echo -e "${green}正在安装 openssl${colorend}"
apk add openssl


echo -e "${green}正在安装 iproute2${colorend}"
apk add iproute2


echo -e "${green}正在安装 caddy${colorend}"
apk add caddy

echo -e "${green}正在安装 cloudflared${colorend}"

sudo mkdir -p --mode=0755 /usr/share/keyrings && 
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null &&
sudo mkdir -p /etc/apt/sources.list.d
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list &&
curl -L https://github.com/cloudflare/cloudflared/releases/download/2025.11.1/cloudflared-linux-amd64 -o cloudflared && 
chmod +x cloudflared && 
mv cloudflared /usr/local/bin


# 下载xray内核
echo -e "${green}下载 Xray 内核${colorend}"
wget https://github.com/XTLS/Xray-core/releases/download/v25.10.15/Xray-linux-64.zip

# 解压xray程序到 /usr/local/bin 目录下，方便直接调用
unzip /root/Xray-linux-64.zip -d /usr/local/bin
chmod +x /usr/local/bin/xray            # 设置xray执行权限

# 创建xray存放日志文件
mkdir -p /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log
chmod +rw /var/log/xray/*.log	# 设置日志文件权限


# 创建OpenRC服务
touch /etc/init.d/xray_service
chmod +x /etc/init.d/xray_service



cat << \EOF > /etc/init.d/xray_service
#!/sbin/openrc-run

depend() {
    need net
}

name="xray"
description="Xray-core service"
command="/usr/local/bin/xray"			# xray执行文件路径
command_args="-c /usr/local/etc/xray/config.json"	# xray的节点配置信息。
pidfile="/var/run/xray.pid"
background="true"
extra_started_commands="reload"

start() {
    start-stop-daemon --start \
        --exec ${command} \
        --pidfile ${pidfile} \
        --background \
        --make-pidfile \
        -- ${command_args} # 将 command_args 传递给 Xray 进程
}

stop() {
	start-stop-daemon --stop \
	    --pidfile ${pidfile}
}

reload() {
	start-stop-daemon --signal HUP \
        --pidfile ${pidfile}
}
EOF


# 创建节点配置文件
mkdir -p /usr/local/etc/xray
touch /usr/local/etc/xray/config.json
chmod +rw /usr/local/etc/xray/config.json

# 生成uuid
uuid=$(xray uuid)
# 生成路径
vless_path=$(cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c 8)

echo -e "${green}隧道配置教程：${colorend}"
echo -e "${green}1.打开：https://one.dash.cloudflare.com${colorend}"
echo -e "${green}2.网络——连接器——创建隧道——选择cloudflared——自定义命名隧道——保存${colorend}"
echo -e "${green}3.选择任一操作系统点击——在下方命令中找到 evJhI 开头的密钥复制下来——点击 下一步${colorend}"
echo -e "${green}4.子域可选——域 填写托管在cloudflare的域名——服务 类型选 http ,url填写 localhost:80 —— 点击 完成设置${colorend}"

echo -n "输入隧道域名："
read domain

echo -n "输入隧道Token(--token后面的内容)："
read tunnel_token

echo -n "输入端口(默认:20001)："
read vless_port
vless_port=${vless_port:-20001}

echo -n "输入要伪装的域名(默认:https://bing.com)："
read fake_url
fake_url=${fake_url:-https://bing.com}


cat << EOF > /usr/local/etc/xray/config.json
{
    "log": {
        "loglevel": "warning"
    },
    "dns": {
        "servers": [
            "8.8.8.8",
            "1.1.1.1"
        ]
    },
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:private"
                ],
                "outboundTag": "block"
            }
        ]
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": "${vless_port}",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}",
                        "level": 0
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "tlsSettings": {
                    "allowInsecure": false,
                    "alpn": [
                        "http/1.1"
                    ]
                },
                "wsSettings": {
                    "path": "/${vless_path}",
                    "host":"${domain}"
                }
            }
        }
    ],
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom"
        },
        {
            "tag": "block",
            "protocol": "blackhole"
        }
    ]
}
EOF



# 配置caddy
cat << EOF > /etc/caddy/Caddyfile
:80 {
    @path path /${vless_path}*
    handle @path {
        reverse_proxy localhost:${vless_port}
    }
	
    handle {
        redir ${fake_url}
    }
}
EOF



# 启动caddy
caddy_status=$(rc-service caddy status)
sleep 0.5s
echo "${green}caddy_status:${caddy_status}${colorend}"
if [[ ${caddy_status} == *"started"* || ${caddy_status} == *"already been started"* ]]; then
    echo -e "${green}检测到 caddy 已启动${colorend}"
    echo -e "${green}重新加载 caddy${colorend}"
    rc-service caddy reload
else
    echo -e "${green}启动 caddy${colorend}"
	rc-service caddy start
fi

# 启动隧道
echo -e "${green}启动 隧道${colorend}"
nohup cloudflared tunnel run --token ${tunnel_token} &


# 启动 x-ray
xray_status=$(rc-service xray_service status)
sleep 0.5s
echo "xray_status:${xray_status}"
if [[ ${xray_status} == *"started"* || ${xray_status} == *"already been started"* ]]; then
    echo -e "${green}检测到 xray 已启动${colorend}"
    echo -e "${green}重新启动 xray${colorend}"
    rc-service xray_service restart
else
    echo -e "${green}启动 xray${colorend}"
	rc-service xray_service start
fi

# 节点信息
echo -e "${green}vless://${uuid}@${domain}:443?encryption=none&security=tls&sni=${domain}&type=ws&path=%2F${vless_path}#vless${colorend}"
