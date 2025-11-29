#!/bin/bash

Green="\033[0;32m"
Red="\033[0;31m"
Yellow="\033[0;33m"
end="\033[0m"

log() {
	local LEVEL="$1"
	local MSG="$2"
	case "${LEVEL}" in
		info)
			echo -e "${Green}${MSG}${end}"
			;;
		warn)
			echo -e "${Yellow}${MSG}${end}"
			;;
		error)
			echo -e "${Red}${MSG}${end}"
			;;
	esac
}

if [[ $# == 0 ]]; then
    log warn "请输入 warp h 进入控制台"
    exit 1
fi

restart_service() {
    /usr/bin/wg-quick down wgcf             # 删除 warp 接口
    cd /etc/warp

    # 获取 wgcf-profile.conf的内容，用于配置wireguard
    wireguard_systemName="wgcf_service"
    PrivateKey=$(grep '^PrivateKey' wgcf-profile.conf | cut -d= -f2- | awk '$1=$1') 
    Address=$(grep '^Address' wgcf-profile.conf | cut -d= -f2- | tr -d '[:space:]')
    Address_ipv4=$(echo ${Address} | cut -d, -f1 | tr -d '[:space:]')
    Address_ipv6=$(echo ${Address} | cut -d, -f2 | tr -d '[:space:]')
    PublicKey=$(grep '^PublicKey' wgcf-profile.conf | cut -d= -f2- | tr -d '[:space:]')
    Endpoint=$(grep '^Endpoint' wgcf-profile.conf | cut -d= -f2- | tr -d '[:space:]')

    current_ip=$(curl -s ifconfig.me)
    if (( ${choose} == 1 )); then
        Address=$Address_ipv4
        Dns="2606:4700:4700::1111,2001:4860:4860::8888"
        rules=$'PostUp = ip -6 rule add from '"${current_ip}"$' lookup main\nPostDown = ip -6 rule delete from '"${current_ip}"$' lookup main'
        AllowedIPs="0.0.0.0/0"
    elif (( ${choose} == 2 )); then
        Address=$Address_ipv6
        Dns="1.1.1.1,8.8.8.8"
        rules=$'PostUp = ip -4 rule add from '"${current_ip}"$' lookup main\nPostDown = ip -4 rule delete from '"${current_ip}"$' lookup main'
        AllowedIPs="::/0"
    elif (( ${choose} == 3 )); then
        Address="${Address_ipv4},${Address_ipv6}"
        Dns="2606:4700:4700::1111,2001:4860:4860::8888,1.1.1.1,8.8.8.8"
        if echo ${current_ip} | grep -Eq '^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$'; then
            rules=$'PostUp = ip -4 rule add from '"${current_ip}"$' lookup main\nPostDown = ip -4 rule delete from '"${current_ip}"$' lookup main'
        else
            rules=$'PostUp = ip -6 rule add from '"${current_ip}"$' lookup main\nPostDown = ip -6 rule delete from '"${current_ip}"$' lookup main'
        fi
        AllowedIPs="0.0.0.0/0,::/0"
    else
        log error "输入有误"
        exit 1
    fi
    cat > /etc/wireguard/wgcf.conf <<EOF
[Interface]
PrivateKey = ${PrivateKey}
Address = ${Address}
DNS = ${Dns}
MTU = 1400
${rules}

[Peer]
PublicKey = ${PublicKey}
AllowedIPs = ${AllowedIPs}
Endpoint = ${Endpoint}
EOF
    log info "重启 Warp"
    rc-service ${wireguard_systemName} restart > /dev/null
    log info "成功启动 wireguard"
}


param=$1
case "${param}" in
    h)
        log warn "1.仅有 ipv6 的vps开启ipv4（默认）"
        log warn "2.仅有 ipv4 的vps开启ipv6"
        log warn "3.开启双栈"
        log warn "4.卸载 Warp"
        echo -n "请选择:"
        read choose
        if (( $choose == 4 )); then
            exit 1
        fi
        restart_service
        ;;
    *)
        log erre "输入有误"
        ;;
esac
