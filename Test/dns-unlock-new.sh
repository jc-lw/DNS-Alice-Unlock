#!/bin/bash

# 一键管理和配置 dnsmasq 脚本
# 请确保使用 sudo 或 root 权限运行此脚本

# 脚本版本和更新时间
VERSION="V_0.8.9"
LAST_UPDATED=$(date +"%Y-%m-%d")

# 指定配置文件的下载地址
CONFIG_URL="https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dnsmasq.conf"
CONFIG_FILE="/etc/dnsmasq.conf"
SCRIPT_NAME="dns-unlock.sh"
AUTHOR="Jimmydada"

# 检查是否以 root 身份运行
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m[错误] 请以 root 权限运行此脚本！\033[0m"
  exit 1
fi

# 检查系统是否为 Debian/Ubuntu
if ! grep -Ei 'debian|ubuntu' /etc/os-release > /dev/null; then
  echo -e "\033[31m[错误] 此脚本仅适用于 Debian 和 Ubuntu 系统！\033[0m"
  exit 1
fi

# 公共函数：检查端口占用并释放
check_and_release_port() {
  local port=$1
  echo -e "\033[1;34m检查端口 $port 的占用情况...\033[0m"
  if lsof -i :$port | grep -q LISTEN; then
    echo -e "\033[31m端口 $port 被以下进程占用：\033[0m"
    lsof -i :$port
    echo -e "\033[33m尝试关闭相关进程...\033[0m"
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

# 显示标题和备注
echo -e "\033[1;34m======================================\033[0m"
echo -e "\033[1;32m       一键配置 dnsmasq 分流脚本       \033[0m"
echo -e "\033[1;36m       版本：  $VERSION       \033[0m"
echo -e "\033[1;36m       更新时间：$LAST_UPDATED        \033[0m"
echo -e "\033[1;36m       本脚本由 $AUTHOR 维护          \033[0m"
echo -e "\033[1;36m     再次打开脚本 bash dns-unlock.sh  \033[0m"
echo -e "\033[1;34m======================================\033[0m"
echo -e "\n"

# 显示主菜单
echo -e "\033[1;33m请选择要执行的操作：\033[0m"
echo -e "\033[1;36m1.\033[0m \033[1;32mdnsmasq 分流配置\033[0m"
echo -e "\033[1;36m2.\033[0m \033[1;32msmartdns 分流配置\033[0m"
echo -e "\033[1;36m3.\033[0m \033[1;32mresolv 文件分流配置\033[0m"
echo -e "\033[1;36m4.\033[0m \033[1;32m检测流媒体解锁支持情况\033[0m"
echo -e "\033[1;36m5.\033[0m \033[1;32m检查系统端口 53 占用情况\033[0m"
echo -e "\033[1;36m6.\033[0m \033[1;32m删除脚本本地文件\033[0m"
echo -e "\033[1;36m0.\033[0m \033[1;31m退出\033[0m"
echo -e "\n\033[1;33m请输入数字 (1-6):\033[0m"
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
    # 安装并配置 dnsmasq
    echo "执行安装 dnsmasq 的相关操作..."
    
    # 安装 dnsmasq
    apt update && apt install -y dnsmasq
    if [ $? -ne 0 ]; then
      echo -e "\033[31m[错误] dnsmasq 安装失败，请检查系统环境！\033[0m"
      exit 1
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

    # 检查端口 53 占用情况
    check_and_release_port 53

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
    echo -e "\033[1;36m0.\033[0m \033[1;31m退出脚本\033[0m"
    read update_choice

    # 根据选择进入下一步操作
    case $config_choice in
    1)
      # 更新为 HK 配置
      echo -e "\033[1;34m更新 dnsmasq 配置为 HK 配置...\033[0m"
      curl -o $CONFIG_FILE "https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dnsmasq.conf.hk"
      echo -e "\033[1;32mdnsmasq 配置已更新为 HK 配置！\033[0m"
      systemctl restart dnsmasq
      ;;

    2)
      # 更新为 SG 配置
      echo -e "\033[1;34m更新 dnsmasq 配置为 SG 配置...\033[0m"
      curl -o $CONFIG_FILE "https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dnsmasq.conf.sg"
      echo -e "\033[1;32mdnsmasq 配置已更新为 SG 配置！\033[0m"
      systemctl restart dnsmasq
      ;;
    *)
      echo -e "\033[31m[错误] 无效的选项！\033[0m"
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
  echo -e "\033[1;36m0.\033[0m \033[1;31m退出脚本\033[0m"
  echo -e "\n\033[1;33m请输入数字 (0-3):\033[0m"
  read smartdns_choice

  case $smartdns_choice in
  1)
# 安装 smartdns
  echo "安装 smartdns..."
  apt update && apt install -y smartdns
  if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] smartdns 安装失败，请检查系统环境！\033[0m"
    exit 1
  fi

  # 下载 smartdns 配置文件
  echo "下载 smartdns 配置文件..."
  curl -o /etc/smartdns/smartdns.conf https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/smartdns.conf
  if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 配置文件下载失败！\033[0m"
    exit 1
  fi

  # 检查端口 53 是否被占用
  PORT_IN_USE=$(sudo netstat -tuln | grep ':53')
  if [ -n "$PORT_IN_USE" ]; then
    echo "端口 53 已被占用，检查是否为 systemd-resolved..."
    SYSTEMD_RESOLVED=$(ps aux | grep 'systemd-resolved' | grep -v 'grep')
    if [ -n "$SYSTEMD_RESOLVED" ]; then
      echo "systemd-resolved 正在占用端口 53，停止 systemd-resolved 服务..."
      systemctl stop systemd-resolved
      systemctl disable systemd-resolved
    else
      echo "其他进程占用端口 53，停止相关服务..."
      sudo systemctl stop dnsmasq
      sudo systemctl disable dnsmasq
    fi
  else
    echo "端口 53 未被占用，可以继续配置！"
  fi

  # 检查 /etc/resolv.conf 文件是否已被锁定，如果已锁定则解锁
  if lsattr /etc/resolv.conf | grep -q 'i'; then
    echo "文件 /etc/resolv.conf 已被锁定，正在解锁..."
    chattr -i /etc/resolv.conf
    if [ $? -ne 0 ]; then
      echo -e "\033[31m[错误] 解锁 /etc/resolv.conf 文件失败！\033[0m"
      exit 1
    fi
  fi

  # 备份 /etc/resolv.conf 文件
  echo "备份 /etc/resolv.conf 文件..."
  cp /etc/resolv.conf /etc/resolv.conf.bak
  if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] /etc/resolv.conf 备份失败！\033[0m"
    exit 1
  fi

  # 修改 /etc/resolv.conf 中的 nameserver 为 127.0.0.1
  echo "修改 /etc/resolv.conf 文件中的 nameserver 为 127.0.0.1..."
  sed -i 's/nameserver .*/nameserver 127.0.0.1/' /etc/resolv.conf
  if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 修改 /etc/resolv.conf 文件失败！\033[0m"
    exit 1
  fi

  # 锁定 /etc/resolv.conf 文件
  echo "锁定 /etc/resolv.conf 文件..."
  chattr +i /etc/resolv.conf
  if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 锁定 /etc/resolv.conf 文件失败！\033[0m"
    exit 1
  fi

  # 启动 smartdns 服务并设置为开机启动
  echo "启动 smartdns 并设置为开机启动..."
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
  echo -e "\033[1;36m3.\033[0m \033[1;32m一键更换 resolv.conf 中的 nameserver\033[0m"
  echo -e "\033[1;36m4.\033[0m \033[1;32m恢复原始 /etc/resolv.conf 配置\033[0m"
  echo -e "\033[1;36m0.\033[0m \033[1;31m退出脚本\033[0m"
  echo -e "\n\033[1;33m请输入数字 (0-4):\033[0m"
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
    echo -e "\033[1;34m请输入要更换的 nameserver 地址：\033[0m"
    read nameserver
    set_and_lock_resolv_conf $nameserver
    ;;

  4)
    # 恢复原始配置
    echo -e "\033[1;34m恢复原始 /etc/resolv.conf 配置...\033[0m"
    cp /etc/resolv.conf.bak /etc/resolv.conf
    chattr -i /etc/resolv.conf
    echo -e "\033[1;32m已恢复原始配置！\033[0m"
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

0)
  echo -e "\033[1;31m退出脚本...\033[0m"
  exit 0
  ;;

*)
  echo -e "\033[31m[错误] 无效的选项！\033[0m"
  ;;
esac

