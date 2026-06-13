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
  config set <KEY> <VALUE>    写入配置项（KEY: CF_API_TOKEN CF_ZONE_ID CF_ZONE_NAME INTERVAL UPDATE_MIRROR）
  config get <KEY>            读取某配置项
  config show                 脱敏展示当前配置
  record list                 列出所有记录（带序号）
  record add <name> <A|AAAA> <wan4|host6> [param] [ttl] [proxied]
                              添加一条记录
  record del <序号>           删除指定序号的记录
  uninstall                   移除 cron（程序文件保留，提示如何彻底删除）
  menu                        交互式菜单（Phase 3）
  update                      在线更新（Phase 4）

配置文件: $CONFIG_FILE
记录文件: $RECORDS_FILE
日志文件: $CFDDNS_LOG
EOF
}

# cfddns config {set|get|show}
cmd_config() {
    config_load
    _sub=${1:-show}; [ $# -gt 0 ] && shift
    case "$_sub" in
        set)
            _k=$1
            [ -n "$_k" ] && [ $# -ge 2 ] || die "用法: cfddns config set <KEY> <VALUE>（KEY: ${CONFIG_KEYS}）"
            config_key_valid "$_k" || die "未知配置键: ${_k}（可设: ${CONFIG_KEYS}）"
            shift
            _v=$*
            if [ "$_k" = INTERVAL ] && ! printf '%s' "$_v" | grep -qE '^[0-9]+$'; then
                die "INTERVAL 必须是数字（分钟）"
            fi
            config_set "$_k" "$_v"
            if [ "$_k" = CF_API_TOKEN ]; then
                log_ok "已写入 CF_API_TOKEN（已脱敏存于 ${CONFIG_FILE}，权限 600）"
            else
                log_ok "已写入 $_k = $_v"
            fi
            [ "$_k" = INTERVAL ] && echo "提示：cron 间隔变更需重新运行 install.sh 应用。"
            ;;
        get)
            _k=$1; [ -n "$_k" ] || die "用法: cfddns config get <KEY>"
            config_key_valid "$_k" || die "未知配置键: $_k"
            eval "printf '%s\n' \"\${$_k}\""
            ;;
        show|"") config_show ;;
        *) die "用法: cfddns config {set|get|show}" ;;
    esac
}

# cfddns record {list|add|del}
cmd_record() {
    _sub=${1:-list}; [ $# -gt 0 ] && shift
    case "$_sub" in
        list|"")
            if [ "$(record_count)" -le 0 ] 2>/dev/null; then
                echo "（暂无记录，用 cfddns record add 添加）"; return 0
            fi
            _n=0
            records_read | while IFS='|' read -r name type source param ttl proxied rid; do
                _n=$((_n + 1))
                printf '%2d) %-24s %-4s src=%-5s param=%-22s ttl=%s proxied=%s\n' \
                    "$_n" "$name" "$type" "$source" "${param:--}" "$ttl" "$proxied"
            done
            ;;
        add)
            _name=$1; _type=$2; _src=$3; _param=$4; _ttl=${5:-60}; _prox=${6:-false}
            [ -n "$_name" ] && [ -n "$_type" ] && [ -n "$_src" ] \
                || die "用法: cfddns record add <name> <A|AAAA> <wan4|host6> [param] [ttl] [proxied]"
            case "$_type" in A|AAAA) ;; *) die "type 只能是 A 或 AAAA" ;; esac
            case "$_src"  in wan4|host6) ;; *) die "source 只能是 wan4 或 host6" ;; esac
            if [ "$_src" = host6 ] && [ -z "$_param" ]; then
                die "host6 需要 param：内网IP 或 MAC，可加固定后缀，如 192.168.50.3,::3"
            fi
            record_add "$_name" "$_type" "$_src" "$_param" "$_ttl" "$_prox"
            log_ok "已添加记录: $_name $_type"
            ;;
        del)
            _idx=$1
            printf '%s' "$_idx" | grep -qE '^[0-9]+$' || die "用法: cfddns record del <序号>（序号见 record list）"
            record_del_index "$_idx" && log_ok "已删除第 $_idx 条记录"
            ;;
        *) die "用法: cfddns record {list|add|del}" ;;
    esac
}

cmd=${1:-help}
[ $# -gt 0 ] && shift

case "$cmd" in
    run)                   core_run "$@" ;;
    config)                cmd_config "$@" ;;
    record)                cmd_record "$@" ;;
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
