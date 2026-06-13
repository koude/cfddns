#!/bin/sh
# common.sh —— CFDDNS 公共函数库
# 全程 POSIX / busybox ash 写法，不依赖 bash 特性。
# 由 cfddns.sh 在确定 CFDDNS_ROOT 后 source 进来。

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
# CFDDNS_ROOT  : 仓库/安装根目录（含 scripts/ conf/）
# CFDDNS_DATA  : 运行期数据目录（config / records / state / log），可被环境变量覆盖，
#                安装版会指向持久化目录；开发期默认用 conf/。
: "${CFDDNS_ROOT:?common.sh 需要先设置 CFDDNS_ROOT}"
: "${CFDDNS_DATA:=$CFDDNS_ROOT/conf}"

CONFIG_FILE="$CFDDNS_DATA/config"
RECORDS_FILE="$CFDDNS_DATA/records.conf"
STATE_FILE="$CFDDNS_DATA/state"
CFDDNS_LOG="$CFDDNS_DATA/cfddns.log"
LOG_MAX_BYTES=262144   # 256KB 触发轮转

# ---------------------------------------------------------------------------
# 颜色（仅在 stderr 为 TTY 时启用）
# ---------------------------------------------------------------------------
if [ -t 2 ]; then
    C_RED='\033[31m'; C_GRN='\033[32m'; C_YEL='\033[33m'; C_BLU='\033[34m'; C_RST='\033[0m'
else
    C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_RST=''
fi

# ---------------------------------------------------------------------------
# 日志
# ---------------------------------------------------------------------------
_log_rotate() {
    [ -f "$CFDDNS_LOG" ] || return 0
    # busybox 的 wc -c / stat 都可能在，优先 wc
    size=$(wc -c <"$CFDDNS_LOG" 2>/dev/null || echo 0)
    [ "$size" -gt "$LOG_MAX_BYTES" ] 2>/dev/null && mv -f "$CFDDNS_LOG" "$CFDDNS_LOG.1"
    return 0
}

_log() {
    _level=$1; shift
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    _line="$_ts [$_level] $*"
    mkdir -p "$CFDDNS_DATA" 2>/dev/null
    _log_rotate
    printf '%s\n' "$_line" >>"$CFDDNS_LOG" 2>/dev/null
    # 同时回显到 stderr（带颜色）
    case "$_level" in
        ERROR) printf '%b%s%b\n' "$C_RED" "$_line" "$C_RST" >&2 ;;
        WARN)  printf '%b%s%b\n' "$C_YEL" "$_line" "$C_RST" >&2 ;;
        OK)    printf '%b%s%b\n' "$C_GRN" "$_line" "$C_RST" >&2 ;;
        *)     [ "${CFDDNS_VERBOSE:-1}" = "1" ] && printf '%s\n' "$_line" >&2 ;;
    esac
}

log_info()  { _log INFO  "$@"; }
log_ok()    { _log OK    "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }

die() { log_error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# 依赖检查
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
    for _c in "$@"; do
        have "$_c" || die "缺少依赖命令: $_c"
    done
}

# ---------------------------------------------------------------------------
# JSON 抠字段（busybox 无 jq 时的兜底；若有 jq 则优先）
#   json_str  <key>   从 stdin 取第一个 "key":"字符串值"
#   json_bool <key>   从 stdin 取第一个 "key":true/false
# 注意：仅适用于 CF API 这种结构简单的响应，按出现顺序取首个匹配。
# ---------------------------------------------------------------------------
json_str() {
    if have jq; then
        jq -r --arg k "$1" '.. | objects | .[$k]? // empty' 2>/dev/null | head -n1
    else
        grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 \
            | sed -E 's/.*:[[:space:]]*"(.*)"$/\1/'
    fi
}

json_bool() {
    grep -oE "\"$1\"[[:space:]]*:[[:space:]]*(true|false)" | head -n1 \
        | grep -oE '(true|false)$'
}

# ---------------------------------------------------------------------------
# 杂项
# ---------------------------------------------------------------------------
# 去掉字符串首尾空白
trim() { printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

# 读取 version 文件内容（无则 0）
read_version() {
    if [ -f "$CFDDNS_ROOT/version" ]; then
        trim "$(cat "$CFDDNS_ROOT/version")"
    else
        echo "0"
    fi
}
