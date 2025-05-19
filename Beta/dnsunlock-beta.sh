#!/bin/bash

# 一键管理和配置 dnsmasq 脚本
# 请确保使用 sudo 或 root 权限运行此脚本

# 脚本版本和更新时间
VERSION="V_1.0.1"
LAST_UPDATED=$(date +"%Y-%m-%d")

# 检查是否以 root 身份运行6
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m[错误] 请以 root 权限运行此脚本！\033[0m"
  exit 1
fi

# 检查系统是否为 Debian/Ubuntu
if ! grep -Ei 'debian|ubuntu' /etc/os-release > /dev/null; then
  echo -e "\033[31m[错误] 此脚本仅适用于 Debian 和 Ubuntu 系统！\033[0m"
  exit 1
fi

# 检查 curl 和 jq 是否安装，未安装则自动安装
if ! command -v curl &> /dev/null; then
    echo -e "\033[31mcurl 未安装，正在安装...\033[0m"
    sudo apt-get update && sudo apt-get install -y curl
fi

if ! command -v jq &> /dev/null; then
    echo -e "\033[31mjq 未安装，正在安装...\033[0m"
    sudo apt-get update && sudo apt-get install -y jq
fi

# 指定配置文件的下载地址
CONFIG_URL="https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dnsmasq.conf"
CONFIG_FILE="/etc/dnsmasq.conf"
SCRIPT_NAME="dnsunlock-beta.sh"
SCRIPT_PATH="/root/$SCRIPT_NAME"
SYMLINK_PATH="/usr/local/bin/ddnsb"
AUTHOR="Jimmydada"

# 检查并创建 ddnsb 快捷命令（符号链接）
create_symlink() {
  SYMLINK_PATH="/usr/local/bin/ddnsb"  # 快捷命令的目标路径
  SCRIPT_PATH="/path/to/your/script"   # 脚本的实际路径（需要替换为脚本的真实路径）

  if [ ! -f "$SYMLINK_PATH" ]; then
    echo -e "\033[1;32m首次运行，创建快捷命令 ddnsb...\033[0m"
    sudo ln -sf "$SCRIPT_PATH" "$SYMLINK_PATH"
    sudo chmod +x "$SYMLINK_PATH"
    echo -e "\033[1;32m快捷命令 ddnsb 创建成功！\033[0m"
  else
    echo -e "\033[1;33m快捷指令 ddnsb 已存在，快速进入设置\033[0m"
  fi
}

# 获取当前外部IP地址和所属地区
IP_INFO=$(curl -s http://ipinfo.io/json)
IP_ADDRESS=$(echo $IP_INFO | jq -r '.ip')
REGION=$(echo $IP_INFO | jq -r '.region')


# 执行检查和创建符号链接的操作
create_symlink

# 公共函数：检查端口占用并释放
check_and_release_port() {
  local port=$1
  echo -e "\033[1;34m检查端口 $port 的占用情况...\033[0m"

  # 检查端口是否被占用
  if lsof -i :$port | grep -q LISTEN; then
    echo -e "\033[31m端口 $port 被以下进程占用：\033[0m"
    lsof -i :$port

    # 检查是否是由 smartdns 占用
    if lsof -i :$port | grep -q 'smartdns'; then
      echo -e "\033[33msmartdns 服务正在占用端口 $port，尝试停止服务...\033[0m"
      systemctl stop smartdns && systemctl disable smartdns
      if [ $? -eq 0 ]; then
        echo -e "\033[1;32msmartdns 服务已成功停止。\033[0m"
      else
        echo -e "\033[31m[错误] 无法停止 smartdns 服务，请手动检查。\033[0m"
      fi
    fi

    # 检查是否是由 dnsmasq 占用
    if lsof -i :$port | grep -q 'dnsmasq'; then
      echo -e "\033[33mdnsmasq 服务正在占用端口 $port，尝试停止服务...\033[0m"
      systemctl stop dnsmasq && systemctl disable dnsmasq
      if [ $? -eq 0 ]; then
        echo -e "\033[1;32mdnsmasq 服务已成功停止。\033[0m"
      else
        echo -e "\033[31m[错误] 无法停止 dnsmasq 服务，请手动检查。\033[0m"
      fi
    fi

    # 检测并处理 systemd-resolved 服务
    if systemctl is-active --quiet systemd-resolved; then
        echo -e "\033[33m检测到 systemd-resolved 正在运行，占用端口 $port。\033[0m"
        echo -e "\033[33m尝试停止 systemd-resolved 服务...\033[0m"
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
        echo -e "\033[1;32m[成功] systemd-resolved 服务已停止并禁用。\033[0m"
    else
        echo -e "\033[1;32msystemd-resolved 服务未运行。\033[0m"
    fi

    # 检测其他未知进程并尝试终止
    echo -e "\033[33m尝试关闭端口 $port 的其他占用进程...\033[0m"
    lsof -i :$port | awk 'NR>1 {print $2}' | xargs -r kill -9
    echo -e "\033[1;32m端口 $port 已释放。\033[0m"
  else
    echo -e "\033[1;32m端口 $port 未被占用。\033[0m"
  fi
}


# 公共函数：设置 resolv.conf 并锁定
set_and_lock_resolv_conf() {
  local nameserver=$1
  echo -e "\033[1;34m备份 /etc/resolv.conf 文件...\033[0m"
  cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null
  echo -e "\033[1;34m删除旧的 /etc/resolv.conf 并创建新文件...\033[0m"
  rm -f /etc/resolv.conf
  echo "nameserver $nameserver" > /etc/resolv.conf
  echo -e "\033[1;34m锁定 /etc/resolv.conf 文件...\033[0m"
  chattr +i /etc/resolv.conf
  echo -e "\033[1;32m操作成功！当前 nameserver 已设置为 $nameserver 并已锁定。\033[0m"
}

# 判断系统类型并升级系统
get_package_manager() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    else
        echo -e "\033[31m[错误] 无法检测系统信息！\033[0m"
        exit 1
    fi

    case "$OS_NAME" in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            ;;
        alpine)
            PACKAGE_MANAGER="apk"
            ;;
        *)
            echo -e "\033[31m[错误] 不支持的系统：$OS_NAME\033[0m"
            exit 1
            ;;
    esac
}

# 升级系统和包管理器
upgrade_system() {
    get_package_manager
    
    if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
        echo -e "\033[1;33m开始升级系统...\033[0m"
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y curl dnsmasq lsof
    elif [[ "$PACKAGE_MANAGER" == "apk" ]]; then
        echo -e "\033[1;33m开始升级系统...\033[0m"
        sudo apk update && sudo apk upgrade
        sudo apk add curl dnsmasq lsof
    fi
}

# 显示标题和备注
echo -e "\033[1;34m======================================\033[0m"
echo -e "\033[1;32m       一键配置 dnsmasq 分流脚本       \033[0m"
echo -e "\033[1;36m       版本：  $VERSION       \033[0m"
echo -e "\033[1;36m       更新时间：$LAST_UPDATED        \033[0m"
echo -e "\033[1;36m       本脚本由 $AUTHOR 维护          \033[0m"
echo -e "\033[1;36m    VPS IP： $IP_ADDRESS  $REGION     \033[0m"
echo -e "\033[1;34m======================================\033[0m"
echo -e "\n"

# 显示主菜单
echo -e "\033[1;33m请选择要执行的操作：\033[0m"
echo -e "\033[1;36m1.\033[0m \033[1;32mdnsmasq 分流配置\033[0m"
echo -e "\033[1;36m2.\033[0m \033[1;32msmartdns 分流配置\033[0m"
echo -e "\033[1;36m3.\033[0m \033[1;32mresolv 分流配置（全局代理）\033[0m"
echo -e "\033[1;36m4.\033[0m \033[1;32m检测流媒体解锁支持情况\033[0m"
echo -e "\033[1;36m5.\033[0m \033[1;32m检查系统端口 53 占用情况\033[0m"
echo -e "\033[1;36m6.\033[0m \033[1;32m删除脚本\033[0m"
echo -e "\033[1;36m7.\033[0m \033[1;32m更新脚本\033[0m"
echo -e "\033[1;36m0.\033[0m \033[1;31m退出\033[0m"
echo -e "\n\033[1;33m请输入数字 (0-7):\033[0m"
read main_choice

case $main_choice in
1)
  # dnsmasq 分流配置子菜单
  while true; do
  echo -e "\033[1;33m请选择要执行的操作：\033[0m"
  echo -e "\033[1;36m1.\033[0m \033[1;32m安装并配置 dnsmasq 分流\033[0m"
  echo -e "\033[1;36m2.\033[0m \033[1;32m卸载 dnsmasq 并恢复默认配置\033[0m"
  echo -e "\033[1;36m3.\033[0m \033[1;32m更新 dnsmasq 配置文件\033[0m"
  echo -e "\033[1;36m4.\033[0m \033[1;32m重启 dnsmasq 服务\033[0m"
  echo -e "\033[1;36m0.\033[0m \033[1;31m退出脚本\033[0m"
  echo -e "\n\033[1;33m请输入数字 (0-4):\033[0m"
  read dnsmasq_choice
  
  case $dnsmasq_choice in
    1)
    # 升级系统和包管理器
    upgrade_system
    
    # 安装并配置 dnsmasq
    echo "执行安装 dnsmasq 的相关操作..."
    
    # 安装 dnsmasq
    apt update && apt install -y dnsmasq
    if [ $? -ne 0 ]; then
      echo -e "\033[31m[错误] dnsmasq 安装失败，请检查系统环境！\033[0m"
      exit 1
    fi

    # 检查是否成功安装
    if ! command -v dnsmasq >/dev/null 2>&1; then
        echo -e "\033[31m[错误] dnsmasq 安装失败，请检查！\033[0m"
        exit 1
    fi
    echo -e "\033[1;32m[dnsmasq] 安装完成。\033[0m"

    # 检查是否安装 lsof
    if ! command -v lsof >/dev/null 2>&1; then
        echo -e "\033[33m检测到系统未安装 lsof 工具，正在安装...\033[0m"
        apt update && apt install -y lsof
        if ! command -v lsof >/dev/null 2>&1; then
            echo -e "\033[31m[错误] lsof 安装失败，请手动安装后重试！\033[0m"
            exit 1
        fi
        echo -e "\033[1;32m[lsof] 工具安装完成。\033[0m"
    fi

     # 下载并更新配置文件
    echo -e "\033[1;34m下载并覆盖 dnsmasq 配置文件...\033[0m"
    curl -o $CONFIG_FILE $CONFIG_URL
    if [ $? -ne 0 ]; then
        echo -e "\033[31m[错误] 配置文件下载失败，请检查网络连接！\033[0m"
        exit 1
    fi
    echo -e "\033[1;32m配置文件已更新：$CONFIG_FILE\033[0m"

# 提示用户是否调整配置文件中的 IP
    read -p "配置文件中 IP 为 154.12.177.22 和 157.20.104.47，是否调整？(回车默认Alice DNS，输入y调整自己的解锁IP): " adjust
    if [[ "$adjust" == "y" || "$adjust" == "Y" ]]; then
        read -p "请输入您的解锁IP: " unlock_ip
        # 修改配置文件中的 IP 地址
        echo -e "\033[1;34m正在修改配置文件中的 IP 地址...\033[0m"
        sed -i "s/154.12.177.22/$unlock_ip/g" $CONFIG_FILE
        sed -i "s/157.20.104.47/$unlock_ip/g" $CONFIG_FILE
        echo -e "\033[1;32m配置文件中的 IP 已更新为新的解锁IP：$unlock_ip\033[0m"
    else
        echo -e "\033[1;32m未调整配置文件中的 IP。\033[0m"
    fi

# 检查端口 53 是否被占用
PORT_IN_USE=$(sudo netstat -tuln | grep ':53')
if [ -n "$PORT_IN_USE" ]; then
  echo -e "\033[1;34m端口 53 已被占用，检查是否为 systemd-resolved...\033[0m"
  SYSTEMD_RESOLVED=$(ps aux | grep 'systemd-resolved' | grep -v 'grep')
  if [ -n "$SYSTEMD_RESOLVED" ]; then
    echo -e "\033[1;33msystemd-resolved 正在占用端口 53，停止 systemd-resolved 服务...\033[0m"
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
  else
    echo -e "\033[1;33m其他进程占用端口 53，停止相关服务...\033[0m"
    sudo systemctl stop dnsmasq
    sudo systemctl disable dnsmasq
  fi
else
  echo -e "\033[1;32m端口 53 未被占用，可以继续配置！\033[0m"
fi

    # 备份并更新 /etc/resolv.conf
    set_and_lock_resolv_conf "127.0.0.1"

    # 重启 dnsmasq 服务
    echo -e "\033[1;34m重启 dnsmasq 服务...\033[0m"
    systemctl restart dnsmasq && systemctl enable dnsmasq
    if [ $? -eq 0 ]; then
        echo -e "\033[1;32mdnsmasq 服务已成功启动并启用开机自启！\033[0m"
    else
        echo -e "\033[31m[错误] dnsmasq 服务启动失败，请检查配置！\033[0m"
    fi
    ;;
    
  2)
    # 卸载 dnsmasq 并恢复默认配置
    echo "执行卸载 dnsmasq 的相关操作..."
    apt-get purge -y dnsmasq
    systemctl disable --now dnsmasq
    rm -f $CONFIG_FILE
    echo -e "\033[1;32mdnsmasq 已成功卸载并恢复默认配置！\033[0m"
    ;;

3)
    # 更新 dnsmasq 配置文件
    echo -e "\033[1;34m进入 dnsmasq 配置文件更新菜单...\033[0m"
    echo -e "\033[1;33m请选择要更新的配置：\033[0m"
    echo -e "\033[1;36m1.\033[0m \033[1;32m更新为 HK 配置\033[0m"
    echo -e "\033[1;36m2.\033[0m \033[1;32m更新为 SG 配置\033[0m"
    echo -e "\033[1;36m3.\033[0m \033[1;32m更新为全量配置\033[0m"
    echo -e "\033[1;36m0.\033[0m \033[1;31m退出脚本\033[0m"
    read update_choice

    # 根据选择进入下一步操作
    case $update_choice in
  1)
    # 更新为 HK 配置
    CONFIG_URL="https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dnsmasq.conf.hk"
    TARGET_FILE="dnsmasq.conf.hk"
    REGION="HK"
    ;;
  2)
    # 更新为 SG 配置
    CONFIG_URL="https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dnsmasq.conf.sg"
    TARGET_FILE="dnsmasq.conf.sg"
    REGION="SG"
    ;;
  3)
    # 更新为全量配置
    CONFIG_URL="https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dnsmasq.conf.allsg"
    TARGET_FILE="dnsmasq.conf.allsg"
    REGION="AllSG"
    ;;
  *)
    echo -e "\033[31m无效选择，请输入0-3！\033[0m"
    exit 1
    ;;
  esac

  echo -e "\033[1;34m开始更新为 $REGION 配置...\033[0m"

  # 备份旧的配置文件
  if [ -f /etc/dnsmasq.conf ]; then
    echo -e "\033[1;33m备份原有配置文件为 /etc/dnsmasq.conf.bak...\033[0m"
    mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
  fi

  # 下载新的配置文件
  echo -e "\033[1;33m下载新的 $REGION 配置文件...\033[0m"
  curl -o "/etc/$TARGET_FILE" "$CONFIG_URL"
  if [ $? -eq 0 ]; then
    echo -e "\033[1;32m$REGION 配置文件下载成功！\033[0m"
    
    # 提示用户是否更换 IP
    if [ "$REGION" == "AllSG" ]; then
      echo -e "\033[1;33m配置文件中包含 IP 地址 157.20.104.47，是否需要替换为自己的 IP 地址？(回车默认不修改，输入 y 修改)\033[0m"
      read use_own_ip

      if [ "$use_own_ip" == "y" ]; then
        echo -e "\033[1;33m请输入您的 IP 地址：\033[0m"
        read user_ip
        # 替换文件中的 IP 地址
        sed -i "s/157.20.104.47/$user_ip/g" /etc/$TARGET_FILE
        echo -e "\033[1;32mIP 地址已替换为 $user_ip\033[0m"
      else
        echo -e "\033[1;32m保留原有 IP 地址！\033[0m"
      fi
    fi

    # 将新的配置文件替换为 dnsmasq 的默认配置文件
    mv "/etc/$TARGET_FILE" /etc/dnsmasq.conf
    echo -e "\033[1;32m$REGION 配置文件更新成功！\033[0m"

    # 重启 dnsmasq 服务
    echo -e "\033[1;33m重启 dnsmasq 服务...\033[0m"
    systemctl restart dnsmasq
    if [ $? -eq 0 ]; then
      echo -e "\033[1;32mdnsmasq 服务重启成功！\033[0m"
    else
      echo -e "\033[31m重启 dnsmasq 服务失败，请检查日志！\033[0m"
    fi
  else
    echo -e "\033[31m$REGION 配置文件下载失败，请检查网络连接！\033[0m"
    # 恢复原始配置（如果有备份）
    if [ -f /etc/dnsmasq.conf.bak ]; then
      echo -e "\033[1;33m恢复原始配置文件...\033[0m"
      mv /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
    fi
  fi
  ;;
  
  4)
    # 重启 dnsmasq 服务
    echo -e "\033[1;34m重启 dnsmasq 服务...\033[0m"
    systemctl restart dnsmasq
    if [ $? -eq 0 ]; then
      echo -e "\033[1;32mdnsmasq 服务已成功重启！\033[0m"
    else
      echo -e "\033[31m[错误] dnsmasq 服务重启失败！\033[0m"
    fi
    ;;

    0)
      break
      ;;
    
    *)
      echo -e "\033[31m无效选择，请重新输入！\033[0m"
      ;;
    esac
  done
  ;;

2)
  # smartdns 分流配置子菜单
  while true; do
  echo -e "\033[1;33m请选择要执行的操作：\033[0m"
  echo -e "\033[1;36m1.\033[0m \033[1;32m安装并配置 smartdns 分流\033[0m"
  echo -e "\033[1;36m2.\033[0m \033[1;32m重启 smartdns 服务\033[0m"
  echo -e "\033[1;36m3.\033[0m \033[1;32m卸载 smartdns 并恢复默认 resolv.conf 配置\033[0m"
  echo -e "\033[1;36m4.\033[0m \033[1;32m一键更新全量配置\033[0m"
  echo -e "\033[1;36m0.\033[0m \033[1;31m退出脚本\033[0m"
  echo -e "\n\033[1;33m请输入数字 (0-4):\033[0m"
  read smartdns_choice

  case $smartdns_choice in
1)
# 安装 smartdns
echo -e "\033[1;34m正在安装 smartdns...\033[0m"
apt update && apt install -y smartdns
if [ $? -ne 0 ]; then
  echo -e "\033[31m[错误] smartdns 安装失败，请检查系统环境！\033[0m"
  exit 1
fi

# 下载 smartdns 配置文件
echo -e "\033[1;34m正在下载 smartdns 配置文件...\033[0m"
curl -o /etc/smartdns/smartdns.conf https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/smartdns.conf
if [ $? -ne 0 ]; then
  echo -e "\033[31m[错误] 配置文件下载失败！\033[0m"
  exit 1
fi

# 检测 smartdns 配置文件中的默认 IP
DEFAULT_IP1="154.12.177.22"
DEFAULT_IP2="157.20.104.47"

echo -e "\033[1;34m检测到配置文件中的默认 IP 为：\033[0m"
echo -e "\033[1;33m1. $DEFAULT_IP1\033[0m"
echo -e "\033[1;33m2. $DEFAULT_IP2\033[0m"
echo -e "\033[1;34m是否需要修改这些 IP？(y/N):\033[0m"
read change_ip

if [[ "$change_ip" == "y" || "$change_ip" == "Y" ]]; then
  echo -e "\033[1;34m请输入第一个 IP 的新值（留空则保留 $DEFAULT_IP1）：\033[0m"
  read new_ip1
  if [ -n "$new_ip1" ]; then
    sed -i "s/$DEFAULT_IP1/$new_ip1/" /etc/smartdns/smartdns.conf
    echo -e "\033[1;32m已将 $DEFAULT_IP1 替换为 $new_ip1！\033[0m"
  else
    echo -e "\033[1;33m保留 $DEFAULT_IP1！\033[0m"
  fi

  echo -e "\033[1;34m请输入第二个 IP 的新值（留空则保留 $DEFAULT_IP2）：\033[0m"
  read new_ip2
  if [ -n "$new_ip2" ]; then
    sed -i "s/$DEFAULT_IP2/$new_ip2/" /etc/smartdns/smartdns.conf
    echo -e "\033[1;32m已将 $DEFAULT_IP2 替换为 $new_ip2！\033[0m"
  else
    echo -e "\033[1;33m保留 $DEFAULT_IP2！\033[0m"
  fi
else
  echo -e "\033[1;33m保持默认 IP 配置！\033[0m"
fi

# 检查端口 53 是否被占用
PORT_IN_USE=$(sudo netstat -tuln | grep ':53')
if [ -n "$PORT_IN_USE" ]; then
  echo -e "\033[1;34m端口 53 已被占用，检查是否为 systemd-resolved...\033[0m"
  SYSTEMD_RESOLVED=$(ps aux | grep 'systemd-resolved' | grep -v 'grep')
  if [ -n "$SYSTEMD_RESOLVED" ]; then
    echo -e "\033[1;33msystemd-resolved 正在占用端口 53，停止 systemd-resolved 服务...\033[0m"
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
  else
    echo -e "\033[1;33m其他进程占用端口 53，停止相关服务...\033[0m"
    sudo systemctl stop dnsmasq
    sudo systemctl disable dnsmasq
  fi
else
  echo -e "\033[1;32m端口 53 未被占用，可以继续配置！\033[0m"
fi

# 检查 /etc/resolv.conf 文件是否被锁定，如果已锁定则解锁
if lsattr /etc/resolv.conf | grep -q 'i'; then
  echo -e "\033[1;33m文件 /etc/resolv.conf 已被锁定，正在解锁...\033[0m"
  chattr -i /etc/resolv.conf
  if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 解锁 /etc/resolv.conf 文件失败！\033[0m"
    exit 1
  fi
fi

# 备份 /etc/resolv.conf 文件
echo -e "\033[1;34m备份 /etc/resolv.conf 文件...\033[0m"
cp /etc/resolv.conf /etc/resolv.conf.bak
if [ $? -ne 0 ]; then
  echo -e "\033[31m[错误] /etc/resolv.conf 备份失败！\033[0m"
  exit 1
fi

# 修改 /etc/resolv.conf 中的 nameserver 为 127.0.0.1
echo -e "\033[1;34m修改 /etc/resolv.conf 文件中的 nameserver 为 127.0.0.1...\033[0m"
echo "nameserver 127.0.0.1" > /etc/resolv.conf
if [ $? -ne 0 ]; then
  echo -e "\033[31m[错误] 修改 /etc/resolv.conf 文件失败！\033[0m"
  exit 1
fi

# 锁定 /etc/resolv.conf 文件
echo -e "\033[1;34m锁定 /etc/resolv.conf 文件...\033[0m"
chattr +i /etc/resolv.conf
if [ $? -ne 0 ]; then
  echo -e "\033[31m[错误] 锁定 /etc/resolv.conf 文件失败！\033[0m"
  exit 1
fi

# 启动 smartdns 服务并设置为开机启动
echo -e "\033[1;34m启动 smartdns 并设置为开机启动...\033[0m"
systemctl restart smartdns && systemctl enable smartdns
if [ $? -ne 0 ]; then
  echo -e "\033[31m[错误] smartdns 启动失败！\033[0m"
  exit 1
fi

echo -e "\033[1;32msmartdns 配置已完成，服务已启动并设置为开机启动！\033[0m"
;;

  2)
    # 重启 smartdns 服务
    echo -e "\033[1;34m重启 smartdns 服务...\033[0m"
    systemctl restart smartdns
    if [ $? -eq 0 ]; then
      echo -e "\033[1;32msmartdns 服务已成功重启！\033[0m"
    else
      echo -e "\033[31m[错误] smartdns 服务重启失败！\033[0m"
    fi
    ;;

 3)
    # 卸载 smartdns 并恢复默认 resolv.conf 配置
    echo -e "\033[1;34m卸载 smartdns 并恢复默认 resolv.conf 配置...\033[0m"

    # 卸载 smartdns
    apt-get purge -y smartdns
    if [ $? -eq 0 ]; then
      echo -e "\033[1;32msmartdns 已成功卸载！\033[0m"
    else
      echo -e "\033[31m[错误] 卸载 smartdns 失败！\033[0m"
      exit 1
    fi

    # 恢复默认 resolv.conf 配置
    if [ -f /etc/resolv.conf.bak ]; then
      echo -e "\033[1;34m恢复原始 /etc/resolv.conf 配置...\033[0m"
      cp /etc/resolv.conf.bak /etc/resolv.conf
      chattr -i /etc/resolv.conf
      echo -e "\033[1;32m已恢复原始配置！\033[0m"
    else
      echo -e "\033[31m[错误] 找不到备份文件 /etc/resolv.conf.bak！\033[0m"
    fi
    ;;

    4)
      # 一键更新全量配置
      CONFIG_URL="https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/smartdns.conf.sg"
      CONFIG_FILE="/etc/smartdns/smartdns.conf"
      BACKUP_FILE="/etc/smartdns/smartdns.conf.bak"

      echo "正在下载最新的 SmartDNS 配置文件..."
      curl -o /tmp/smartdns.conf.sg $CONFIG_URL
      if [ $? -ne 0 ]; then
        echo -e "\033[31m[错误] 配置文件下载失败！请检查网络连接。\033[0m"
        continue
      fi

      echo "检测到配置文件中可能需要更换的 IP：157.20.104.47"
      echo -e "\033[1;34m是否需要替换为其他 IP 地址？[y/N]\033[0m"
      read replace_choice
      if [[ "$replace_choice" =~ ^[Yy]$ ]]; then
        echo -e "\033[1;34m请输入新的 IP 地址：\033[0m"
        read new_ip
        sed -i "s/157\.20\.104\.47/$new_ip/g" /tmp/smartdns.conf.sg
        echo -e "\033[1;32m已将 157.20.104.47 替换为 $new_ip\033[0m"
      fi

      # 检测是否存在默认配置文件
      if [ -f $CONFIG_FILE ]; then
        echo "备份当前的 SmartDNS 配置文件..."
        cp $CONFIG_FILE $BACKUP_FILE
        if [ $? -ne 0 ]; then
          echo -e "\033[31m[错误] 配置文件备份失败！\033[0m"
          continue
        fi
      else
        echo -e "\033[1;33m未检测到默认配置文件，跳过备份。\033[0m"
      fi

      echo "替换 SmartDNS 配置文件..."
      mv /tmp/smartdns.conf.sg $CONFIG_FILE
      if [ $? -ne 0 ]; then
        echo -e "\033[31m[错误] 配置文件替换失败！\033[0m"
        continue
      fi

      echo "重启 SmartDNS 服务..."
      systemctl restart smartdns
      if [ $? -ne 0 ]; then
        echo -e "\033[31m[错误] SmartDNS 服务重启失败！\033[0m"
      else
        echo -e "\033[1;32mSmartDNS 配置已更新并成功重启服务！\033[0m"
      fi
      ;;

    0)
      break
      ;;
    *)
      echo -e "\033[31m无效选择，请重新输入！\033[0m"
      ;;
    esac
  done
  ;;

3)
  # resolv 文件分流配置子菜单
  while true; do
  echo -e "\033[1;33m请选择要执行的操作：\033[0m"
  echo -e "\033[1;36m1.\033[0m \033[1;32m解锁 /etc/resolv.conf 文件\033[0m"
  echo -e "\033[1;36m2.\033[0m \033[1;32m锁定 /etc/resolv.conf 文件\033[0m"
  echo -e "\033[1;36m3.\033[0m \033[1;32m一键全局代理（修改系统 DNS 配置）\033[0m"
  echo -e "\033[1;36m4.\033[0m \033[1;32m恢复原始 /etc/resolv.conf 配置\033[0m"
  echo -e "\033[1;36m5.\033[0m \033[1;32m一键恢复 8.8.8.8 并重启系统 DNS\033[0m"
  echo -e "\033[1;36m0.\033[0m \033[1;31m退出脚本\033[0m"
  echo -e "\n\033[1;33m请输入数字 (0-5):\033[0m"
  read resolv_choice
  
  case $resolv_choice in
  1)
    # 解锁 resolv.conf 文件
    echo -e "\033[1;34m解锁 /etc/resolv.conf 文件...\033[0m"
    chattr -i /etc/resolv.conf
    echo -e "\033[1;32m文件解锁成功！\033[0m"
    ;;

  2)
    # 锁定 resolv.conf 文件
    echo -e "\033[1;34m锁定 /etc/resolv.conf 文件...\033[0m"
    chattr +i /etc/resolv.conf
    echo -e "\033[1;32m文件已成功锁定！\033[0m"
    ;;

  3)
  # 一键更换 nameserver
  echo -e "\033[1;34m检测 /etc/resolv.conf 是否被锁定...\033[0m"

  # 检测是否被锁定
  if lsattr /etc/resolv.conf | grep -q 'i'; then
    echo -e "\033[1;33m检测到 /etc/resolv.conf 被锁定，正在解锁...\033[0m"
    chattr -i /etc/resolv.conf
    if [ $? -eq 0 ]; then
      echo -e "\033[1;32m文件已解锁！\033[0m"
    else
      echo -e "\033[31m解锁失败，请检查权限！\033[0m"
      exit 1
    fi
  else
    echo -e "\033[1;32m文件未锁定，无需解锁。\033[0m"
  fi

  # 提示用户输入新的 nameserver 地址
  echo -e "\033[1;34m请输入要更换的 nameserver 地址（例如 8.8.8.8）：\033[0m"
  read nameserver

  # 验证输入是否为有效的 IP 地址
  if [[ ! $nameserver =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "\033[31m输入的 DNS 地址无效，请输入正确的 IPv4 地址！\033[0m"
    exit 1
  fi

  # 更新 /etc/resolv.conf 文件
  echo -e "\033[1;34m正在更新 /etc/resolv.conf 配置...\033[0m"
  echo "nameserver $nameserver" > /etc/resolv.conf
  if [ $? -eq 0 ]; then
    echo -e "\033[1;32m更新成功：nameserver $nameserver\033[0m"
  else
    echo -e "\033[31m更新失败，请检查权限！\033[0m"
    exit 1
  fi

  # 锁定 /etc/resolv.conf 文件
  echo -e "\033[1;34m正在锁定 /etc/resolv.conf...\033[0m"
  chattr +i /etc/resolv.conf
  if [ $? -eq 0 ]; then
    echo -e "\033[1;32m文件已成功锁定！\033[0m"
  else
    echo -e "\033[31m锁定失败，请检查权限！\033[0m"
    exit 1
  fi

  # 重启 DNS 服务
  echo -e "\033[1;34m正在重启系统 DNS 服务...\033[0m"
  systemctl restart systemd-resolved
  if [ $? -eq 0 ]; then
    echo -e "\033[1;32m系统 DNS 服务已重启！\033[0m"
  else
    echo -e "\033[31m系统 DNS 服务重启失败，请检查配置或日志！\033[0m"
    exit 1
  fi
  ;;

  4)
    # 恢复原始配置
    echo -e "\033[1;34m恢复原始 /etc/resolv.conf 配置...\033[0m"
    cp /etc/resolv.conf.bak /etc/resolv.conf
    chattr -i /etc/resolv.conf
    echo -e "\033[1;32m已恢复原始配置！\033[0m"
    ;;
    
  5)
    # 一键恢复 8.8.8.8 并重启系统 DNS
      echo -e "\033[1;34m检测 /etc/resolv.conf 是否被锁定...\033[0m"
      if lsattr /etc/resolv.conf | grep -q "\-i\-"; then
        echo -e "\033[1;33m文件已锁定，正在解锁...\033[0m"
        chattr -i /etc/resolv.conf
        echo -e "\033[1;32m文件已解锁，继续操作...\033[0m"
      else
        echo -e "\033[1;32m文件未锁定，无需解锁。\033[0m"
      fi

      echo -e "\033[1;34m备份原有的 /etc/resolv.conf 文件...\033[0m"
      cp /etc/resolv.conf /etc/resolv.conf.bak
      echo -e "\033[1;34m修改 /etc/resolv.conf 配置为 8.8.8.8...\033[0m"
      echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > /etc/resolv.conf
      echo -e "\033[1;34m重启系统 DNS 服务...\033[0m"
      systemctl restart systemd-resolved
      if [ $? -eq 0 ]; then
        echo -e "\033[1;32m系统 DNS 已成功设置为 8.8.8.8 并重启！\033[0m"
      else
        echo -e "\033[31m[错误] DNS 服务重启失败，请检查配置！\033[0m"
      fi
      ;;
      
    0)
      break
      ;;
    *)
      echo -e "\033[31m无效选择，请重新输入！\033[0m"
      ;;
    esac
  done
  ;;

4)
  # 检测流媒体解锁支持情况
  echo "检测流媒体解锁支持情况..."
  bash <(curl -L -s https://raw.githubusercontent.com/1-stream/RegionRestrictionCheck/main/check.sh)
  if [ $? -eq 0 ]; then
    echo "流媒体解锁检测完成！"
  else
    echo "流媒体解锁检测失败，请检查网络连接或脚本 URL！"
  fi
  ;;

5)
  # 检查系统端口 53 占用情况
  check_and_release_port 53
  ;;

6)
  # 删除脚本本地文件
  echo -e "\033[1;34m删除脚本本地文件...\033[0m"
  rm -f $0
  echo -e "\033[1;32m脚本已成功删除！\033[0m"
  ;;

7)
  # 更新脚本
  echo -e "\033[1;34m检查远程脚本版本...\033[0m"
  
  # 获取远程脚本的版本号
  REMOTE_VERSION=$(curl -s https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh | grep "VERSION=" | cut -d '"' -f 2)
  
  # 当前脚本的版本号
 CURRENT_VERSION=$(grep 'VERSION=' /root/dns-unlock.sh | cut -d '"' -f 2)
  
  echo -e "\033[1;33m当前版本：$CURRENT_VERSION\033[0m"
  echo -e "\033[1;33m远程版本：$REMOTE_VERSION\033[0m"
  
  # 比较版本号
  if [ "$REMOTE_VERSION" \> "$CURRENT_VERSION" ]; then
    echo -e "\033[1;32m检测到新版本：$REMOTE_VERSION\033[0m"
    echo -e "\033[1;33m正在下载并更新脚本...\033[0m"
    
    # 下载并替换当前脚本
    curl -o /root/dns-unlock.sh https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dns-unlock.sh
    if [ $? -eq 0 ]; then
      echo -e "\033[1;32m脚本已成功更新为版本 $REMOTE_VERSION\033[0m"
      
      # 设置脚本可执行权限
      chmod +x /root/dns-unlock.sh

      # 重新执行更新后的脚本
      echo -e "\033[1;34m重新启动脚本...\033[0m"
      /root/dns-unlock.sh
      exit 0
    else
      echo -e "\033[31m[错误] 下载新脚本失败，请检查网络连接！\033[0m"
    fi
  else
    echo -e "\033[1;32m当前已经是最新版本，无需更新！\033[0m"
  fi
  ;;
  
  0)
  echo -e "\033[1;31m退出脚本...\033[0m"
  exit 0
  ;;

*)
  echo -e "\033[31m无效选择，请重新输入！\033[0m"
  ;;
esac
