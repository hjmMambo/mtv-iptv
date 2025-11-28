#!/bin/bash

green="\033[1;32m"
colorend="\033[0m"

echo -e "${green}安装必要安装包${colorend}"
apk add bash curl
echo -n "正在安装 openssl"
apk add openssl
# echo -n "正在安装 iproute2"
# apk add iproute2
echo -n "正在安装 nginx"
apk add nginx
# 下载xray内核
echo -e "${green}下载 Xray 内核${colorend}"
wget https://github.com/hjmMambo/mtv-iptv/blob/main/Xray-linux-64.zip
# 解压xray程序到 /usr/local/bin 目录下，方便直接调用
unzip /root/Xray-linux-64.zip -d /usr/local/bin
chmod +x /usr/local/bin/xray
mkdir -p /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log
chmod +rw /var/log/xray/*.log
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
chmod +rw /usr/local/etc/xray/config.json
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
                    "0.0.0.0/8",
	                "10.0.0.0/8",
	                "100.64.0.0/10",
	                "127.0.0.0/8",
	                "169.254.0.0/16",
	                "172.16.0.0/12",
	                "192.0.0.0/24",
	                "192.0.2.0/24",
	                "192.88.99.0/24",
	                "192.168.0.0/16",
	                "198.18.0.0/15",
	                "198.51.100.0/24",
	                "203.0.113.0/24",
	                "224.0.0.0/4",
	                "240.0.0.0/4",
	                "fc00::/7",
	                "fe80::/10"
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
cat << EOF > /etc/nginx/nginx.conf
user nginx;
worker_processes auto;
events {
    worker_connections 1024;
}
http {
	server {
	    listen 443 ssl http2;
	    listen [::]:443 ssl http2;
	    server_name ${domain};
	    ssl_certificate /certs/${domain}_ecc/server.crt;
	    ssl_certificate_key /certs/${domain}_ecc/server.key;
	    location ^~ /${vless_path} {
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
	        proxy_pass http://localhost:${vless_port};
	        proxy_set_header Host \$host;
	        proxy_set_header X-Real-IP \$remote_addr;
	    }
	    location / {
	        return 302 ${fake_url};
	    }
	}
}
EOF
nginx_status=$(rc-service nginx status)
sleep 0.5s
echo "nginx_status:${nginx_status}"
if [[ ${nginx_status} == *"started"* || ${nginx_status} == *"already been started"* ]]; then
    echo -e "${green}检测到 nginx 已启动${colorend}"
    echo -e "${green}重新启动 nginx${colorend}"
    rc-service nginx restart
else
    echo -e "${green}启动 nginx${colorend}"
	rc-service nginx start
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
