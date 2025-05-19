#!/bin/bash

# 一键管理和配置 dnsmasq 脚本
# 适用系统: Debian/Ubuntu
# 脚本版本：V_1.0
# 更新时间：$(date +"%Y-%m-%d")
# 作者: Jimmydada (优化支持 by ChatGPT)

# 配置下载地址和相关变量
CONFIG_URL="https://raw.githubusercontent.com/jc-lw/DNS-Alice-Unlock/refs/heads/main/dnsmasq.conf"
CONFIG_FILE="/etc/dnsmasq.conf"
SCRIPT_NAME="dnsmasq-manager.sh"
RESOLV_CONF="/etc/resolv.conf"
BACKUP_SUFFIX=".bak"

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
  echo -e "\033[1;34m备份 $RESOLV_CONF 文件...\033[0m"
  cp "$RESOLV_CONF" "${RESOLV_CONF}${BACKUP_SUFFIX}" 2>/dev/null
  echo -e "\033[1;34m删除旧的 $RESOLV_CONF 并创建新文件...\033[0m"
  echo "nameserver $nameserver" > "$RESOLV_CONF"
  echo -e "\033[1;34m锁定 $RESOLV_CONF 文件...\033[0m"
  chattr +i "$RESOLV_CONF"
  echo -e "\033[1;32m操作成功！当前 nameserver 已设置为 $nameserver 并已锁定。\033[0m"
}

# 菜单标题和说明
clear
echo -e "\033[1;34m======================================\033[0m"
echo -e "\033[1;32m       一键配置 dnsmasq 管理脚本       \033[0m"
echo -e "\033[1;36m       版本：  V_1.0                  \033[0m"
echo -e "\033[1;36m       更新时间：$(date +"%Y-%m-%d")  \033[0m"
echo -e "\033[1;34m======================================\033[0m"
echo -e "\n"

# 显示菜单
echo -e "\033[1;33m请选择要执行的操作：\033[0m"
echo -e "\033[1;36m1.\033[0m 安装并配置 dnsmasq"
echo -e "\033[1;36m2.\033[0m 卸载 dnsmasq 并恢复默认配置"
echo -e "\033[1;36m3.\033[0m 更新 dnsmasq 配置文件"
echo -e "\033[1;36m4.\033[0m 解锁 /etc/resolv.conf 文件"
echo -e "\033[1;36m5.\033[0m 锁定 /etc/resolv.conf 文件"
echo -e "\033[1;36m6.\033[0m 恢复原始 /etc/resolv.conf 配置"
echo -e "\033[1;36m7.\033[0m 检测流媒体解锁支持情况"
echo -e "\033[1;36m8.\033[0m 检查端口 53 占用情况"
echo -e "\033[1;36m9.\033[0m 删除本脚本文件"
echo -e "\033[1;36m10.\033[0m 一键更换 resolv.conf 中的 nameserver"
echo -e "\n\033[1;33m请输入数字 (1-10):\033[0m"
read choice

# 主功能逻辑
case $choice in
1)
  echo -e "\033[1;34m开始安装 dnsmasq 并配置...\033[0m"
  apt update && apt install -y dnsmasq
  if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] dnsmasq 安装失败！\033[0m"
    exit 1
  fi

  curl -o "$CONFIG_FILE" "$CONFIG_URL"
  if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 配置文件下载失败！\033[0m"
    exit 1
  fi

  check_and_release_port 53
  set_and_lock_resolv_conf "127.0.0.1"
  systemctl restart dnsmasq && systemctl enable dnsmasq
  if [ $? -eq 0 ]; then
    echo -e "\033[1;32mdnsmasq 已成功启动！\033[0m"
  else
    echo -e "\033[31m[错误] 启动 dnsmasq 失败！\033[0m"
  fi
  ;;
2)
  echo -e "\033[1;34m卸载 dnsmasq 并恢复默认配置...\033[0m"
  apt purge -y dnsmasq
  rm -f "$CONFIG_FILE"
  systemctl disable dnsmasq
  echo -e "\033[1;32mdnsmasq 已卸载，恢复成功。\033[0m"
  ;;
3)
  echo -e "\033[1;34m更新 dnsmasq 配置...\033[0m"
  curl -o "$CONFIG_FILE" "$CONFIG_URL"
  systemctl restart dnsmasq
  echo -e "\033[1;32m配置更新成功。\033[0m"
  ;;
4)
  echo -e "\033[1;34m解锁 resolv.conf 文件...\033[0m"
  chattr -i "$RESOLV_CONF"
  echo -e "\033[1;32m解锁成功！\033[0m"
  ;;
5)
  echo -e "\033[1;34m锁定 resolv.conf 文件...\033[0m"
  chattr +i "$RESOLV_CONF"
  echo -e "\033[1;32m锁定成功！\033[0m"
  ;;
6)
  echo -e "\033[1;34m恢复原始 resolv.conf 配置...\033[0m"
  mv "${RESOLV_CONF}${BACKUP_SUFFIX}" "$RESOLV_CONF" 2>/dev/null
  echo -e "\033[1;32m恢复完成。\033[0m"
  ;;
7)
  echo -e "\033[1;34m检测流媒体解锁支持情况...\033[0m"
  bash <(curl -sL IP.Check.Place)
  ;;
8)
  check_and_release_port 53
  ;;
9)
  rm -f "$SCRIPT_NAME"
  echo -e "\033[1;32m脚本已删除。\033[0m"
  ;;
10)
  echo -e "\033[1;34m选择 nameserver:\033[0m"
  echo -e "\033[1;36m1.\033[0m 香港 (154.12.177.22)"
  echo -e "\033[1;36m2.\033[0m 新加坡 (157.20.104.47)"
  read ns_choice
  case $ns_choice in
  1) set_and_lock_resolv_conf "154.12.177.22" ;;
  2) set_and_lock_resolv_conf "157.20.104.47" ;;
  *) echo -e "\033[31m无效选择。\033[0m" ;;
  esac
  ;;
*)
  echo -e "\
