-#! /bin/bash

 #Alpine系统安装代理
. /etc/os-release

if [[ "${NAME}" == *Alpine* ]]; then
	echo -e "\033[1;32m检测当前系统为 ${NAME}\033[0m"
	echo -e "\033[1;32m安装 openssl\033[0m"
	apk add openssl > /dev/null			# 安装自签证书
	echo -e "\033[1;32m安装 caddy\033[0m"
	apk add caddy > /dev/null			# 安装caddy
	echo -e "\033[1;32m安装 iproute2\033[0m"
	apk add iproute2

	domain_list=()
	# echo -e "\033[1;32m----自签证书生成----\033[0m"

	# echo -e "\033[1;32m选项：\033[0m"
	# echo "1：签发1个域名证书并配置信息（面板和节点使用同一个证书,默认选项）"
	# echo "2：签发2个不同的域名证书并配置信息（面板和节点各一个）"
	# echo -n "选择："
	# read address_choose
	# address_choose=${address_choose:-1}
	
	address_choose=1
	if (( ${address_choose} == 1 )); then
		echo -e "\033[1;32m注意：第一个输入域名不是填写dns记录里的域名，而是填写解析域名。\033[0m"
		echo -n "输入域名："
		read address
		
		echo -n "输入dns记录上的域名："
		read address_domain

		echo -n "输入面板端口(默认：12345)："
		read sui_port
		sui_port=${sui_port:-12345}
		
		echo -n "输入面板路径(格式：/路径,默认:/panel)："
		read sui_path
		sui_path=${sui_path:-/panel}
		
		echo -n "输入服务端的节点端口(默认:20001)："
		read proxy_port
		proxy_port=${proxy_port:-20001}
		
		certs_path="/certs/${address}_ecc"
		mkdir -p ${certs_path}
		openssl genrsa -out ${certs_path}/server.key 2048
		openssl req -new -key ${certs_path}/server.key -out ${certs_path}/server.csr -subj "/CN=*.${address}"
		openssl x509 -req -in ${certs_path}/server.csr -out ${certs_path}/server.crt -signkey ${certs_path}/server.key -days 3650 > /dev/null 2>&1
		chmod 604 ${certs_path}/server.key
		echo -e "\033[1;32m自签证书生成成功，证书路径：/certs/${address}_ecc\033[0m"
		echo -e "\033[1;32m自动配置caddy文件...\033[0m"
		
		caddy_file="/etc/caddy/Caddyfile"				# 获取caddy配置文件的路径
	
		grpc_path=$(cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c 8)		# 生成随机的gprc路径
		cat << EOF > ${caddy_file}
*.${address} {
	tls /certs/owob.netlib.re_ecc/server.crt /certs/owob.netlib.re_ecc/server.key
	@fweb_suipanelweb {
		host ${address_domain}
		path ${sui_path}*
	}
	handle @fweb_suipanelweb {
		reverse_proxy localhost:${sui_port}
	}

	@grpc {
		host ${address_domain}
		path /${grpc_path}*
	}
	handle @grpc {
		reverse_proxy localhost:${proxy_port} {
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
		
	elif (( ${address_choose} == 2 )); then
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
	
		grpc_path=$(cat /dev/urandom | tr -cd 'a-zA-Z0-9' | head -c 8)
		cat << EOF > ${caddy_file}
${domain_list[0]} {
	tls /certs/${domain_list[0]}_ecc/server.crt /certs/${domain_list[0]}_ecc/server.key
	@sui path /panel*
	handle @sui {
		reverse_proxy localhost:12345
	}
	
	handle {
		redir https://bing.com
	}
}
	
${domain_list[1]} {
	tls /certs/${domain_list[1]}_ecc/server.crt /certs/${domain_list[1]}_ecc/server.key
	@grpc path /${grpc_path}*
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
	fi
	
	
	caddy_status=$(rc-service caddy status)
	if [[ ${message} == " * status: started" ]]; then
		echo -e "\033[1;32m检测caddy已启动\033[0m"
		echo -e "\033[1;32m重新加载caddy...\033[0m"
		rc-service caddy reload
		echo "caddy 服务正在运行"
	else
		echo -e "\033[1;32m启动caddy\033[0m"
		rc-service caddy start
fi
	
	echo -e "\033[1;32m安装 s-ui 面板\033[0m"
	
	# curl -fsSL https://raw.githubusercontent.com/hjmMambo/mtv-iptv/refs/heads/main/install.sh -o install.sh
	# chmod +x install.sh
	# ./install.sh
	source <(curl -sL https://raw.githubusercontent.com/hjmMambo/mtv-iptv/refs/heads/main/install.sh)
	
	nohup /usr/local/s-ui/sui > /var/log/s-ui.log 2>&1 &
	echo -e "\033[1;32m成功启动 s-ui\033[0m"
	if (( ${#domain_list[@]} != 0 )); then
		echo -e "\033[1;32ms-ui面板域名：${domain_list[0]}\033[0m"
	else
		echo -e "\033[1;32ms-ui面板域名：${address}\033[0m"
	fi
	
	echo -e "\033[1;32mgrpc路径：${grpc_path}\033[0m"
	echo -e "\033[1;32m节点配置端口:20001\033[0m"
else
	echo "不相等"
fi

