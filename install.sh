#!/bin/sh
# install.sh —— 安装 cfddns 到持久化目录并设置 cron
# 用法（在仓库目录内）：  sh install.sh [间隔分钟，默认 5]
# 目标默认 /data/cfddns（可用 CFDDNS_INSTALL_DIR 覆盖）。
# 只写 /data 目录 + crontab，绝不碰网络/防火墙；可用 `cfddns.sh uninstall` 卸载。
set -e

SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR=${CFDDNS_INSTALL_DIR:-/data/cfddns}
INTERVAL=${1:-5}

echo "==> 安装 cfddns 到 ${INSTALL_DIR}（cron 间隔 ${INTERVAL} 分钟）"

# 1. 校验目标父目录存在且可写（持久化分区，如 /data）
PDIR=$(dirname "$INSTALL_DIR")
[ -d "$PDIR" ] || { echo "错误：父目录 $PDIR 不存在"; exit 1; }
if ! ( touch "$PDIR/.cfddns_wtest" 2>/dev/null && rm -f "$PDIR/.cfddns_wtest" ); then
    echo "错误：$PDIR 不可写，无法安装（请确认是持久化的可写分区）"; exit 1
fi

# 2. 复制程序文件（保留已存在的 config / records.conf / state，不覆盖）
mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/conf"
cp -f "$SRC"/scripts/*.sh "$INSTALL_DIR/scripts/"
cp -f "$SRC"/version "$INSTALL_DIR/"
cp -f "$SRC"/conf/config.example "$INSTALL_DIR/conf/"
cp -f "$SRC"/conf/records.example "$INSTALL_DIR/conf/"
chmod +x "$INSTALL_DIR"/scripts/*.sh

if [ ! -f "$INSTALL_DIR/conf/config" ]; then
    cp "$SRC/conf/config.example" "$INSTALL_DIR/conf/config"
    chmod 600 "$INSTALL_DIR/conf/config"
    echo "  + 已生成 conf/config（含 Token，权限 600，待填写）"
else
    echo "  = 保留已存在的 conf/config"
fi
if [ ! -f "$INSTALL_DIR/conf/records.conf" ]; then
    cp "$SRC/conf/records.example" "$INSTALL_DIR/conf/records.conf"
    echo "  + 已生成 conf/records.conf（待编辑）"
else
    echo "  = 保留已存在的 conf/records.conf"
fi

# 3. 设置 cron（持久化 + 重启自启）
export CFDDNS_ROOT="$INSTALL_DIR"
. "$INSTALL_DIR/scripts/common.sh"
. "$INSTALL_DIR/scripts/service.sh"
service_cron_install "$INTERVAL"

cat <<EOF

==> 安装完成。后续步骤：
  1) 填配置:  vi $INSTALL_DIR/conf/config         # CF_API_TOKEN / CF_ZONE_ID
  2) 填记录:  vi $INSTALL_DIR/conf/records.conf    # 参考 records.example
  3) 试运行:  $INSTALL_DIR/scripts/cfddns.sh run --dry-run
  4) 正式跑:  $INSTALL_DIR/scripts/cfddns.sh run --force
  cron 已每 ${INTERVAL} 分钟自动执行；重启后随 crond 恢复。
  卸载:      $INSTALL_DIR/scripts/cfddns.sh uninstall
EOF
