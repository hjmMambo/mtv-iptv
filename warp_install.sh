#!/bin/bash

Green="\033[0;32m"
Red="\033[0;31m"
Yellow="\033[0;33m"
end="\033[0m"


# 检查当前是否是alpine系统
# 最好能顺便检查是否是内核低于5.6的

# 代替输出
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

# 检查是否是root权限和alpine系统
check_system() {
    log info "正在检查当前系统"
    if [[ ! $(id -u) == 0 ]]; then
        log error "必须以root权限运行"
        exit 1
    fi

    if [[ ! -f /etc/alpine-release ]]; then
        log error "仅支持 Alpine系统"
        exit 1
    fi

    # log info "清理旧文件"
    # rm -rf /tmp/wgcf-account.toml           # 删除注册cloudflare warp的账户文件
    # rm -rf /tmp/wgcf-profile.conf           # 删除注册时生成的wireguard配置文件
    # rm -rf /etc/warp/wgcf-profile.conf      # 删除复制到warp路径的wgcf-profile文件
    # rm -rf /usr/local/bin/wgcf              # 删除注册程序
    # rm -rf /etc/init.d/wgcf_service         # 删除服务文件
    # log info "清理旧文件结束"
}

# 安装各种软件包依赖以及wgcf
install() {
    log info "正在安装依赖包"
    apk update > /dev/null
    # apk add --no-cache wireguard-tools iproute2 openresolv iptables curl > /dev/null
    cat_list=$(cat /etc/apk/world)
    install_list=(wireguard-tools iproute2 openresolv iptables curl)
    for var in ${install_list[@]}; do
        if ! echo "${cat_list}" | grep -q "^${var}"; then
            echo "正在安装 ${var}"
            apk add ${var}
        fi
    done

    # ------------- 还没解决 wgcf 下载安装的问题，因为是处于ipv6环境中没办法下载------------------------
    # -------------- 还要安装wgcf，这里暂时省略 --------------
    # chmod +x /usr/local/bin/wgcf
    
    # ------------测试使用--------------
    chmod +x /root/wgcf 
    cp /root/wgcf /usr/local/bin
    sleep 1s

    log info "安装 wireguard 内核"
    if ! modprobe wireguard 2> /dev/null; then
        log error "wireguard内核安装失败"
    else
        log info "wireguard安装成功!"
    fi
}

# 注册cloudflare账户以及生成wireguard配置
register() {
    log info "正在注册"
    if [[ ! -f "/usr/local/bin/wgcf" ]]; then
        log error "注册失败，查看wgcf是否已经安装"
        exit 1
    fi

    cd /tmp
    log info "注册 Cloudfalre WARP 账户"
    yes | /usr/local/bin/wgcf register 2> /dev/null
    sleep 5s

    log info "生成 WireGuard 配置"
    /usr/local/bin/wgcf generate 2> /dev/null
}

# 配置wireguard
configuration() {
    if [[ ! -f wgcf-profile.conf ]]; then
        log error "wireguard配置生成失败"
        exit 1
    fi

    mkdir -p /etc/warp
    cp wgcf-profile.conf /etc/warp

    # 获取 wgcf-profile.conf的内容，用于配置wireguard
    PrivateKey=$(grep '^PrivateKey' wgcf-profile.conf | cut -d= -f2- | awk '$1=$1') 
    Address=$(grep '^Address' wgcf-profile.conf | cut -d= -f2- | tr -d '[:space:]')
    Address_ipv4=$(echo ${Address} | cut -d, -f1 | tr -d '[:space:]')
    Address_ipv6=$(echo ${Address} | cut -d, -f2 | tr -d '[:space:]')
    PublicKey=$(grep '^PublicKey' wgcf-profile.conf | cut -d= -f2- | tr -d '[:space:]')
    Endpoint=$(grep '^Endpoint' wgcf-profile.conf | cut -d= -f2- | tr -d '[:space:]')
    # log info ${PrivateKey}
    # log info ${Address}
    # log info "${Address_ipv4}"
    # log info "${Address_ipv6}"
    # log info "${PublicKey}"
    # log info "${Endpoint}"
    


    if [[ -z ${PrivateKey} || -z ${PublicKey} ]]; then
        log error "读取wireguard配置失败"
        exit 1
    fi


    
    log warn "1.仅有 ipv6 的vps开启ipv4（默认）"
    log warn "2.仅有 ipv4 的vps开启ipv6"
    log warn "3.开启双栈"
    log warn "4.卸载 Warp"
    echo -n "请选择:"
    read choose_menu
    choose_menu=${choose_menu:-1}

    current_ip=$(curl -s ifconfig.me)
    # if echo ${ip} | grep -Eq '^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$'; then
    if (( ${choose_menu} == 1 )); then
        Address=$Address_ipv4
        Dns="2606:4700:4700::1111,2001:4860:4860::8888"
        rules=$'PostUp = ip -6 rule add from '"${current_ip}"$' lookup main\nPostDown = ip -6 rule delete from '"${current_ip}"$' lookup main'
        AllowedIPs="0.0.0.0/0"
    elif (( ${choose_menu} == 2 )); then
        Address=$Address_ipv6
        Dns="1.1.1.1,8.8.8.8"
        rules=$'PostUp = ip -4 rule add from '"${current_ip}"$' lookup main\nPostDown = ip -4 rule delete from '"${current_ip}"$' lookup main'
        AllowedIPs="::/0"
    elif (( ${choose_menu} == 3 )); then
        Address="${Address_ipv4},${Address_ipv6}"
        Dns="2606:4700:4700::1111,2001:4860:4860::8888,1.1.1.1,8.8.8.8"
        if echo ${current_ip} | grep -Eq '^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$'; then
            rules=$'PostUp = ip -4 rule add from '"${current_ip}"$' lookup main\nPostDown = ip -4 rule delete from '"${current_ip}"$' lookup main'
        else
            rules=$'PostUp = ip -6 rule add from '"${current_ip}"$' lookup main\nPostDown = ip -6 rule delete from '"${current_ip}"$' lookup main'
        fi
            
        AllowedIPs="0.0.0.0/0,::/0"
    elif (( ${choose_menu} == 4 )); then
        /usr/bin/wg-quick down wgcf             # 删除 warp 接口
        rm -rf /tmp/wgcf_account.toml           # 删除注册cloudflare warp的账户文件
        rm -rf /tmp/wgcf-profile.conf           # 删除注册时生成的wireguard配置文件
        rm -rf /etc/warp/wgcf-profile.conf      # 删除复制到warp路径的wgcf-profile文件
        rm -rf /usr/local/bin/wgcf              # 删除注册程序
        rm -rf /etc/init.d/wgcf_service         # 删除服务文件
        rm -rf /etc/wireguard/                  # 删除wireguard
        exit -1
        log info "卸载 Warp 成功"
    else
        log error "输入有误"
        exit 1
    fi
    # 在wireguard默认配置目录下，生成 WireGuard 配置文件
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
    log info "WireGuard 配置已生成"

    wireguard_systemName="wgcf_service"

    if [[ ! -f "/etc/init.d/${wireguard_systemName}" ]]; then
        log info "wgcf.service 不存在，开始创建"

        cat > "/etc/init.d/${wireguard_systemName}" << 'EOF'
#!/sbin/openrc-run
name="wireguard_service"
description="wireguard_service ready"
pidfile="/var/run/wireguard_service.pid"

depend() {
    need net
}

command="/usr/bin/wg-quick"
command_args="up wgcf"
stop_command_args="down wgcf"

start() {
    ebegin "启动 Warp 服务"
    start-stop-daemon --start \
        --exec $command \
        --pidfile $pidfile \
        --make-pidfile \
        --background \
        -- $command_args
    eend $?
}

# stop() {
#     ebegin "卸载 Warp 服务"
#     "$command" $stop_command_args > /dev/null 2>&1
#     start-stop-daemon --stop --quiet \
#         --pidfile $pidfile
#     eend $?
# }

restart() {
    svc_stop
    svc_start
}
EOF
    fi
    chmod +x "/etc/init.d/${wireguard_systemName}"
    # log info "启动 Warp"
    # 先检查 Warp 的状态
    log info "启动 wireguard"
    wireguard_status=$(rc-service ${wireguard_systemName} start 2>&1)
    # 如果服务没有启动，就使用start命令启动
    if [[ ${wireguard_status} =~ "already been started" ]]; then       # 如果服务已经启动，就使用restart命令重启
        log warn "检测到 Warp 已经启动"
        log info "重启 Warp"
        rc-service ${wireguard_systemName} restart > /dev/null
    fi
    log info "成功启动 Wrap"
    wget https://raw.githubusercontent.com/hjmMambo/mtv-iptv/refs/heads/main/warp_control.sh -O warp
    chmod +x warp
    mv warp /usr/local/bin
    log info "可输入 warp h 打开控制台"
    # rm -rf /tmp/wgcf_account.toml           # 删除注册cloudflare warp的账户文件
    # rm -rf /tmp/wgcf-profile.conf           # 删除注册时生成的wireguard配置文件
    # rm -rf /etc/warp/wgcf-profile.conf      # 删除复制到warp路径的wgcf-profile文件
    # rm -rf /usr/local/bin/wgcf              # 删除注册程序
}




if [ $# -eq 1 ]; then
    check_system
    install
    register
    configuration
fi
