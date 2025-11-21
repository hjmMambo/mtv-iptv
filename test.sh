#! /bin/bash

 #Alpine系统安装代理
. /etc/os-release

if [[ "${NAME}" == *Alpine* ]]; then
	echo -e "\033[1;32m检测当前系统为 ${NAME}\033[0m"
	echo -e "\033[1;32m安装 openssl\033[0m"
	apk add openssl > /dev/null			# 安装自签证书
	echo -e "\033[1;32m安装 caddy\033[0m"
	apk add caddy > /dev/null			# 安装caddy

	domain_list=()
	echo -e "\033[1;32m----自签证书生成----\033[0m"
	
	for (( i=1; i<=2; i++)); do
		if (( i == 1 )); then
			echo -n "输入面板的主域名："
			read address
		else
			echo -n "输入节点的域名："
			read address
		fi
		
		certs_path="/certs/${address}_ecc"
		mkdir -p ${certs_path}
		openssl genrsa -out ${certs_path}/server.key 2048
		openssl req -new -key ${certs_path}/server.key -out ${certs_path}/server.csr -subj "/CN=${address}"
		openssl x509 -req -in ${certs_path}/server.csr -out ${certs_path}/server.crt -signkey ${certs_path}/server.key -days 3650 > /dev/null 2>&1
		chmod 604 ${certs_path}/server.key
		domain_list+=("${address}")			# 添加域名到数组中
	done
	for (( i=0; i<${#domain_list[@]}; i++ )); do
		echo -e "\033[1;32m自签证书生成成功，证书路径：/certs/${domain_list[i]}_ecc\033[0m"
	done
	

	
	echo -e "\033[1;32m自动配置caddy文件...\033[0m"
	
	caddy_file="/etc/caddy/Caddyfile"
	
	cat << EOF > ${caddy_file}
${domain_list[0]} {
	tls /certs/${domain_list[0]}_ecc/server.crt /certs/${domain_list[0]}_ecc/server.key
	@sui path /suiguipanelweb*
	handle @sui {
		reverse_proxy localhost:12345
	}

	handle {
		redir https://bing.com
	}
}

${domain_list[1]} {
	tls /certs/${domain_list[1]}_ecc/server.crt /certs/${domain_list[1]}_ecc/server.key
	@grpc path /vlessgrpcdoros233*
	handle @grpc {
		reverse_proxy localhost:20001 {
			transport http {
                versions h2c
            }
		}
	}
	
	handle {
		redir https://bing.com
	}
}
EOF
	echo -e "\033[1;32m启动caddy\033[0m"
	rc-service caddy start
	echo -e "\033[1;32m安装 s-ui 面板\033[0m"
	
	curl -fsSL https://raw.githubusercontent.com/hjmMambo/mtv-iptv/refs/heads/main/install.sh -o install.sh
	chmod +x install.sh
	./install.sh
	
	nohup /usr/local/s-ui/sui > /var/log/s-ui.log 2>&1 &
	echo -e "\033[1;32m成功启动 s-ui\033[0m"
else
	echo "不相等"
fi

