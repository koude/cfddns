#!/bin/sh
# cfddns.sh —— 入口分发
# 用法：cfddns <command> [args]
#   run [--force] [--dry-run]   执行一次检查/更新（cron 调用 run）
#   version                     显示版本
#   help                        显示帮助
#   menu / update               占位（后续阶段提供）

# --- 解析自身所在目录（兼容软链接调用）---------------------------------------
prog="$0"
if command -v readlink >/dev/null 2>&1; then
    rl=$(readlink -f "$prog" 2>/dev/null) && [ -n "$rl" ] && prog="$rl"
fi
SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "$prog")" && pwd) || exit 1
CFDDNS_ROOT=$(CDPATH= cd -- "$SCRIPTS_DIR/.." && pwd) || exit 1
export CFDDNS_ROOT

# --- 载入模块 ---------------------------------------------------------------
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/config.sh"
. "$SCRIPTS_DIR/ipsource.sh"
. "$SCRIPTS_DIR/cloudflare.sh"
. "$SCRIPTS_DIR/core.sh"
. "$SCRIPTS_DIR/service.sh"

usage() {
    cat <<EOF
cfddns $(read_version) —— Cloudflare DDNS

用法: cfddns <命令> [参数]

命令:
  run [--force] [--dry-run]   执行一次检查/更新
                                --dry-run 只探测打印 IP，不调用 API、不需配置
                                --force   忽略本地缓存强制推送
  version                     显示版本
  help                        显示本帮助
  uninstall                   移除 cron（程序文件保留，提示如何彻底删除）
  menu                        交互式菜单（Phase 3）
  update                      在线更新（Phase 4）

配置文件: $CONFIG_FILE
记录文件: $RECORDS_FILE
日志文件: $CFDDNS_LOG
EOF
}

cmd=${1:-help}
[ $# -gt 0 ] && shift

case "$cmd" in
    run)                   core_run "$@" ;;
    version|-v|--version)  echo "cfddns $(read_version)" ;;
    help|-h|--help|"")     usage ;;
    menu)                  echo "菜单 TUI 将在 Phase 3 提供。" ;;
    update)                echo "在线更新将在 Phase 4 提供。" ;;
    uninstall)
        service_cron_remove
        echo "已移除 cron。程序文件仍在 ${CFDDNS_ROOT}；如需彻底删除：rm -rf ${CFDDNS_ROOT}"
        ;;
    *)                     echo "未知命令: $cmd" >&2; usage; exit 1 ;;
esac
