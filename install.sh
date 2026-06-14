#!/bin/sh
# install.sh —— 安装 cfddns 到持久化目录并设置 cron
#
# 两种用法：
#   1) 一键直装（管道执行，自动从镜像源下载）：
#        sh -c "$(curl -fsSL https://raw.githubusercontent.com/koude/cfddns/main/install.sh)"
#        # 自定义间隔/镜像： CFDDNS_INTERVAL=3 url=<raw根> sh -c "$(curl -fsSL .../install.sh)"
#   2) 本地安装（已下载/解压仓库后，在仓库目录内）：
#        sh install.sh [间隔分钟，默认 5]
#
# 目标默认 /data/cfddns（可用 CFDDNS_INSTALL_DIR 覆盖）。
# 只写 /data 目录 + crontab，绝不碰网络/防火墙；可用 `cfddns uninstall` 卸载。
set -e

SRC=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd 2>/dev/null) || SRC=.
INSTALL_DIR=${CFDDNS_INSTALL_DIR:-/data/cfddns}
INTERVAL=${1:-${CFDDNS_INTERVAL:-5}}
MIRROR=${url:-${CFDDNS_MIRROR:-https://raw.githubusercontent.com/koude/cfddns/main}}

# 需要落地的文件清单（相对仓库根）
INSTALL_FILES="version \
scripts/common.sh scripts/config.sh scripts/ipsource.sh scripts/cloudflare.sh \
scripts/core.sh scripts/service.sh scripts/menu.sh scripts/update.sh scripts/cfddns.sh \
conf/config.example conf/records.example"

# 判定来源：本地有 scripts/cfddns.sh 用本地，否则从镜像源下载
if [ -f "$SRC/scripts/cfddns.sh" ]; then
    echo "==> 本地安装（来源 ${SRC}）"
else
    echo "==> 一键直装：从镜像源下载（${MIRROR}）"
    command -v curl >/dev/null 2>&1 || { echo "错误：需要 curl"; exit 1; }
    STAGE=$(mktemp -d 2>/dev/null || echo "/tmp/cfddns-src.$$")
    mkdir -p "$STAGE"
    for f in $INSTALL_FILES; do
        mkdir -p "$STAGE/$(dirname "$f")"
        if ! curl -fsSL --max-time 30 "$MIRROR/$f" -o "$STAGE/$f" || [ ! -s "$STAGE/$f" ]; then
            rm -rf "$STAGE"
            echo "错误：下载失败 ${f}（检查镜像源/网络，未改动任何文件）"; exit 1
        fi
    done
    SRC=$STAGE
fi

echo "==> 安装到 ${INSTALL_DIR}（cron 间隔 ${INTERVAL} 分钟）"

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

# 清理下载暂存
if [ -n "${STAGE:-}" ]; then rm -rf "$STAGE"; fi

# 3. 设置 cron（持久化 + 重启自启）
export CFDDNS_ROOT="$INSTALL_DIR"
. "$INSTALL_DIR/scripts/common.sh"
. "$INSTALL_DIR/scripts/service.sh"
service_cron_install "$INTERVAL"

cat <<EOF

==> 安装完成。后续步骤：
  1) 填配置:  $INSTALL_DIR/scripts/cfddns.sh config set CF_API_TOKEN <Token>
              $INSTALL_DIR/scripts/cfddns.sh config set CF_ZONE_ID   <ZoneID>
  2) 加记录:  $INSTALL_DIR/scripts/cfddns.sh record add <域名> <A|AAAA> <wan4|host6> [param]
  3) 试运行:  $INSTALL_DIR/scripts/cfddns.sh run --dry-run
  4) 正式跑:  $INSTALL_DIR/scripts/cfddns.sh run --force
  也可直接进菜单:  $INSTALL_DIR/scripts/cfddns.sh
  cron 已每 ${INTERVAL} 分钟自动执行；重启后随 crond 恢复。
  卸载:      $INSTALL_DIR/scripts/cfddns.sh uninstall
EOF
