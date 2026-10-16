#!/usr/bin/env bash
# ServerStatus 客户端「手机常驻」环境自检
#
# 用法（在 Termux 里）：
#     bash termux-check.sh                      # 只做本机能力自检
#     bash termux-check.sh 1.2.3.4 35601        # 顺带测试到服务端的连通性
#
# 说明：Termux 上没有 /usr/bin/env，请务必用 `bash 脚本名` 方式运行，
#       不要用 `./termux-check.sh`（除非先执行 termux-fix-shebang）。
set -u

ok()   { printf "  \033[32m[可用]\033[0m   %s\n" "$1"; }
warn() { printf "  \033[33m[受限]\033[0m   %s\n" "$1"; }
bad()  { printf "  \033[31m[不可用]\033[0m %s\n" "$1"; }
note() { printf "           %s\n" "$1"; }

SRV=${1:-}
PORT=${2:-35601}

echo "=================================================="
echo " ServerStatus 手机常驻自检"
echo "=================================================="

echo
echo "----- 1. 设备与运行环境 -----"
echo "  架构         : $(uname -m)"
echo "  内核         : $(uname -r)"
if [ -d /data/data/com.termux ] || [ -n "${TERMUX_VERSION:-}" ]; then
  echo "  运行环境     : Termux ${TERMUX_VERSION:-（版本未知）}"
  IS_TERMUX=1
else
  echo "  运行环境     : 非 Termux（普通 Linux/容器）"
  IS_TERMUX=0
fi
if command -v getprop >/dev/null 2>&1; then
  rel=$(getprop ro.build.version.release 2>/dev/null)
  sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  [ -n "$rel" ] && echo "  Android      : $rel (API $sdk)" && note "API >= 28 时部分 /proc/net 访问可能被 SELinux 限制"
fi
if command -v python3 >/dev/null 2>&1; then
  echo "  Python3      : $(python3 -V 2>&1)"
else
  bad "Python3 缺失 —— 客户端无法运行，请先 pkg install python"
fi

echo
echo "----- 2. /proc 采集能力（客户端逐项依赖）-----"
proc_check() { # proc_check <路径> <说明>
  if [ -r "$1" ] && head -c 1 "$1" >/dev/null 2>&1; then
    ok "$2"
  else
    bad "$2"
  fi
}
proc_check /proc/uptime   "/proc/uptime    开机时长"
proc_check /proc/meminfo  "/proc/meminfo   内存 / 交换分区"
proc_check /proc/stat     "/proc/stat      CPU 占用率"
proc_check /proc/net/dev  "/proc/net/dev   网卡累计流量与网速"

echo
echo "----- 3. df 磁盘统计能力 -----"
if command -v df >/dev/null 2>&1; then
  echo "  df 实现      : $(df --version 2>/dev/null | head -1 || echo 'BusyBox/toybox 版本')"
  note "df 路径: $(command -v df)"
fi
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
import subprocess
def probe(name, args):
    try:
        out = subprocess.check_output(args, stderr=subprocess.STDOUT)
        line = out.decode("utf-8", "replace").strip().splitlines()[-1]
        print(f"  [可用]   {name}")
        print(f"           末行: {line[:70]}")
    except Exception as e:
        print(f"  [不可用] {name}")
        print(f"           原因: {type(e).__name__}: {str(e)[:70]}")

probe("df -Tlm --total -t <文件系统白名单>（客户端首选）",
      ["df", "-Tlm", "--total", "-t", "ext4", "-t", "xfs", "-t", "btrfs"])
probe("df -Tlm --total（客户端回退路径）",
      ["df", "-Tlm", "--total"])
import os
try:
    v = round(os.getloadavg()[0], 2)
    print(f"  [可用]   os.getloadavg()  -> {v}")
except Exception as e:
    print(f"  [不可用] os.getloadavg()  原因: {type(e).__name__}: {str(e)[:70]}")
PY
fi

echo
echo "----- 4. 常驻机制（能否在后台长期存活）-----"
if [ "$IS_TERMUX" = "1" ]; then
  if command -v termux-wake-lock >/dev/null 2>&1; then
    ok "termux-wake-lock —— 关键：阻止系统在息屏/休眠时杀掉 Termux 进程"
  else
    bad "termux-wake-lock 缺失 —— 请执行: pkg install termux-api"
  fi
  if command -v sv >/dev/null 2>&1 && [ -d "${PREFIX:-/data/data/com.termux/files/usr}/etc/runit" ]; then
    ok "termux-services(runit, sv 命令) —— 可守护进程并在崩溃后自动重启"
  else
    warn "termux-services 未安装 —— 建议: pkg install termux-services"
  fi
  if [ -d "$HOME/.termux/boot" ]; then
    ok "Termux:Boot 自启目录 ~/.termux/boot 已存在"
    ls -1 "$HOME/.termux/boot" 2>/dev/null | sed 's/^/            /'
  else
    warn "~/.termux/boot 不存在 —— 需安装 Termux:Boot 插件并至少启动一次"
  fi
  # 电池优化 / 后台限制无法在 Termux 内查询，只能人工确认
  note "以下三项必须在系统设置里手工确认（Termux 内无法读取）："
  note "  · 电池优化 -> Termux 设为「不受限制 / 无限制 / 允许后台活动」"
  note "  · 厂商自启动管理 -> 允许 Termux 自启动（MIUI/EMUI/ColorOS/OriginOS 尤其要设）"
  note "  · 最近任务里不要划掉 Termux（划掉即结束会话）"
else
  warn "非 Termux 环境，跳过常驻项检查"
fi

echo
echo "----- 5. 与服务端连通性 -----"
if [ -z "$SRV" ]; then
  note "未提供服务端地址，跳过（用法: bash termux-check.sh <服务端IP> [端口]）"
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$SRV" "$PORT" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
try:
    s = socket.create_connection((host, port), 8)
    s.settimeout(5)
    banner = s.recv(256).decode("utf-8", "replace").strip()
    print(f"  [可用]   已连接 {host}:{port}")
    print(f"           服务端问候: {banner[:70]}")
    s.close()
except Exception as e:
    print(f"  [不可用] 连接 {host}:{port} 失败: {type(e).__name__}: {str(e)[:70]}")
PY
else
  warn "无 python3，改用 bash 探活"
  if timeout 8 bash -c "exec 3<>/dev/tcp/$SRV/$PORT" 2>/dev/null; then
    ok "TCP $SRV:$PORT 可建立连接"
  else
    bad "TCP $SRV:$PORT 连接失败"
  fi
fi

echo
echo "=================================================="
echo " 结论"
echo "=================================================="
note "· 第 2、3 节全部「可用」-> 可直接用 clients/status-client.py 上报完整指标。"
note "· 若个别项「不可用」-> 客户端已是逐项容错，该项显示为 0，节点不会掉线。"
note "· 常驻能否成立，取决于第 4 节：wake-lock + 电池优化白名单 + Termux:Boot 缺一不可。"
note "· 省电建议：客户端用 SS_INTERVAL=60 拉长上报间隔；"
note "  同时服务端必须用 --timeout=120 以上，否则节点会被反复断开。"
echo
