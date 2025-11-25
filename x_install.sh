#!/bin/bash

green="\033[1;32m"
colorend="\033[0m"

echo -e "${green}安装必要安装包${colorend}"
apk add bash curl sudo
echo -n "正在安装 openssl"
apk add openssl
echo -n "正在安装 iproute2"
apk add iproute2
echo -n "正在安装 caddy"
apk add caddy
echo -e "${green}下载 Xray 内核${colorend}"
wget https://github.com/XTLS/Xray-core/releases/download/v25.10.15/Xray-linux-64.zip
unzip /root/Xray-linux-64.zip -d /usr/local/bin
chmod +x /usr/local/bin/xray
mkdir -p /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log
chmod a+w /var/log/xray/*.log
touch /etc/init.d/xray_service
chmod +x /etc/init.d/xray_service
cat << \EOF > /etc/init.d/xray_service
#!/sbin/openrc-run
depend() {
    need net
}
name="xray"
description="Xray-core service"
command="/usr/local/bin/xray"
command_args="-c /usr/local/etc/xray/config.json"
pidfile="/var/run/xray.pid"
background="true"
extra_started_commands="reload"
start() {
    start-stop-daemon --start \
        --exec ${command} \
        --pidfile ${pidfile} \
        --background \
        --make-pidfile \
        -- ${command_args}
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
mkdir -p /usr/local/etc/xray
touch /usr/local/etc/xray/config.json
chmod r+w /usr/local/etc/xray/config.json
uuid=$(xray uuid)
vless_path=$(cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c 8)
echo -n "输入域名："
read domain
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
echo -e "${green}------------生成自签证书------------${colorend}"
mkdir -p /certs/${domain}_ecc/ && 
cd /certs/${domain}_ecc/ && 
openssl genrsa -out server.key 2048 && 
openssl req -new -key server.key -out server.csr -subj "/CN=${domain}" && 
openssl x509 -req -in server.csr -out server.crt -signkey server.key -days 3650 && 
chmod 604 server.key
cat << EOF > /etc/caddy/Caddyfile
${domain} {
	tls /certs/${domain}_ecc/server.crt /certs/${domain}_ecc/server.key
    @path path /${vless_path}*
    handle @path {
        reverse_proxy localhost:${vless_port}
    }
    handle {
        redir ${fake_url}
    }
}
EOF
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
echo -e "${green}vless://${uuid}@${domain}:443?encryption=none&security=tls&sni=${domain}&type=ws&path=%2F${vless_path}#vless${colorend}"
