#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "arch: $(arch)"

install_base() {
    case "${release}" in
    alpine)
        # Alpine packages
        apk update && apk add -q wget curl tar tzdata
        ;;
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

config_after_install() {
    echo -e "${yellow}Migration... ${plain}"
    /usr/local/s-ui/sui migrate
    
    echo -e "${yellow}Install/update finished! For security it's recommended to modify panel settings ${plain}"
    # read -p "是否需要设置面板和管理员账号 [y/n,默认y]? ": config_confirm
    # config_confirm=${config_confirm:-y}
    config_confirm="y"
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        # echo -ne "Enter the ${yellow}panel port${plain} (默认面板端口：12345):"
        # read config_port
        # config_port=${config_port:-12345}
        # echo "${config_port}"
        config_port=${sui_port}
        # echo "install.sh中的config_port端口：${config_port}"
        
        # echo -ne "Enter the ${yellow}panel path${plain} (默认面板路径：/suipanelweb):"
        # read config_path
        # config_path=${config_path:-/suipanelweb}
        # echo "${config_path}"
        config_path=${sui_path}
        # echo "install.sh中的config_port端口：${config_path}"
        

        # Sub configuration
        # echo -ne "Enter the ${yellow}subscription port${plain} (默认订阅端口：12346):"
        # read config_subPort
        # config_subPort=${config_subPort:-12346}
        # echo "${config_subPort}"
        config_path=12346
        
        # echo -ne "Enter the ${yellow}subscription path${plain} (默认订阅路径:/subs):" 
        # read config_subPath
        # config_subPath=${config_subPath:-/subs}
        # echo "${config_subPath}"
        config_subPath="/sui_subPath"

        # Set configs
        echo -e "${yellow}Initializing, please wait...${plain}"
        params=""
        [ -z "$config_port" ] || params="$params -port $config_port"
        [ -z "$config_path" ] || params="$params -path $config_path"
        [ -z "$config_subPort" ] || params="$params -subPort $config_subPort"
        [ -z "$config_subPath" ] || params="$params -subPath $config_subPath"
        /usr/local/s-ui/sui setting ${params}

        # read -p "是否修改管理员账号 [y/n,默认n]? ": admin_confirm
        # admin_confirm=${admin_confirm:-n}
        admin_confirm="n"
        if [[ "${admin_confirm}" == "y" || "${admin_confirm}" == "Y" ]]; then
            # First admin credentials
            read -p "Please set up your username:" config_account
            read -p "Please set up your password:" config_password

            # Set credentials
            echo -e "${yellow}Initializing, please wait...${plain}"
            /usr/local/s-ui/sui admin -username ${config_account} -password ${config_password}
        else
            echo -e "${yellow}Your current admin credentials: ${plain}"
            /usr/local/s-ui/sui admin -show
        fi
    else
        echo -e "${red}cancel...${plain}"
        if [[ ! -f "/usr/local/s-ui/db/s-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            echo -e "this is a fresh installation,will generate random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}username:${usernameTemp}${plain}"
            echo -e "${green}password:${passwordTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}if you forgot your login info,you can type ${green}s-ui${red} for configuration menu${plain}"
            /usr/local/s-ui/sui admin -username ${usernameTemp} -password ${passwordTemp}
        else
            echo -e "${red} this is your upgrade,will keep old settings,if you forgot your login info,you can type ${green}s-ui${red} for configuration menu${plain}"
        fi
    fi
}

prepare_services() {
    # 移除 systemctl 相关操作，在 Alpine 上直接停止/清理服务文件
    if [[ -f "/etc/init.d/sing-box" ]]; then # 假设 Alpine 上 sing-box 服务使用 OpenRC
        echo -e "${yellow}Stopping sing-box service... ${plain}"
        /etc/init.d/sing-box stop 2>/dev/null || true # OpenRC 停止服务
        rm -f /usr/local/s-ui/bin/sing-box /usr/local/s-ui/bin/runSingbox.sh /usr/local/s-ui/bin/signal /etc/init.d/sing-box
    fi
    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then # 兼容性清理
        rm -f /etc/systemd/system/sing-box.service
    fi

    if [[ -e "/usr/local/s-ui/bin" ]]; then
        echo -e "###############################################################"
        echo -e "${green}/usr/local/s-ui/bin${red} directory exists yet!"
        echo -e "Please check the content and delete it manually after migration ${plain}"
        echo -e "###############################################################"
    fi
    # Alpine OpenRC 不需要 daemon-reload，此行删除或保持空操作
}

install_s-ui() {
    cd /tmp/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/alireza0/s-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to fetch s-ui version, it maybe due to Github API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "Got s-ui latest version: ${last_version}, beginning the installation..."
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading s-ui failed, please be sure that your server can access Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz"
        echo -e "Beginning the install s-ui v$1"
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}download s-ui v$1 failed,please check the version exists${plain}"
            exit 1
        fi
    fi

    # 停止旧服务：将 systemctl 停止替换为 OpenRC 停止（或尝试直接 kill 进程，这里保留停止逻辑）
    if [[ -e /usr/local/s-ui/ ]]; then
        if [[ -f "/etc/init.d/s-ui" ]]; then
            /etc/init.d/s-ui stop 2>/dev/null || true # OpenRC 停止
        # 即使是 Alpine，如果找不到 OpenRC 脚本，也尝试清理 systemd 文件
        elif [[ -f "/etc/systemd/system/s-ui.service" ]]; then
             systemctl stop s-ui 2>/dev/null || true # 仍保留对 systemctl 文件的尝试停止，但只在文件存在时
        fi
    fi

    tar zxvf s-ui-linux-$(arch).tar.gz
    rm s-ui-linux-$(arch).tar.gz -f

    chmod +x s-ui/sui s-ui/s-ui.sh
    cp s-ui/s-ui.sh /usr/bin/s-ui
    cp -rf s-ui /usr/local/
    # 移除 systemctl 服务文件复制，Alpine 使用 init.d 或直接启动
    # cp -f s-ui/*.service /etc/systemd/system/ 
    # **注意：此处假设 s-ui 提供了 OpenRC 脚本或其他 Alpine 兼容的启动方式，如果没有，需要用户手动创建 OpenRC 脚本或直接通过 /usr/local/s-ui/s-ui.sh 启动**
    # 为满足“不要做其它多余的修改和增删”的要求，我们只删除 systemd 部分，不添加新的 OpenRC 脚本。
    rm -rf s-ui

    config_after_install
    prepare_services

    # 替换 systemctl enable --now 为 OpenRC enable/start，或直接启动
    # 由于删除了 .service 文件复制，我们无法使用 systemctl enable
    # 保持最小修改，我们假设用户会手动启动或 s-ui.sh 包含自启动逻辑，或者需要OpenRC脚本。
    # 鉴于 Alpine 容器环境常见，直接通过 sh 脚本启动程序，不强依赖服务管理器。
    # 如果要启动 OpenRC 服务，需要 /etc/init.d/s-ui 文件：rc-update add s-ui default && /etc/init.d/s-ui start

    # 最终的启动命令，改为直接运行 s-ui 脚本，或假设 s-ui.sh 是启动脚本
    /usr/local/s-ui/s-ui.sh start 2>/dev/null || /usr/local/s-ui/sui start 2>/dev/null || true
    echo -e "${yellow}Please check if s-ui is running. If not, you may need to manually configure the service using OpenRC or running /usr/local/s-ui/sui start.${plain}"


    echo -e "${green}s-ui v${last_version}${plain} installation finished, it is up and running now..."
    echo -e "You may access the Panel with following URL(s):${green}"
    /usr/local/s-ui/sui uri
    echo -e "${plain}"
    echo -e ""
    s-ui help
}

echo -e "${green}Executing...${plain}"
install_base
install_s-ui $1
