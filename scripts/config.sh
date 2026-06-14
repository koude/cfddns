#!/bin/sh
# config.sh —— 全局配置与记录表的读写
# 依赖 common.sh（CONFIG_FILE / RECORDS_FILE / 日志函数）。

# ---------------------------------------------------------------------------
# 全局配置（config 文件，KEY="value" 形式，可被 source）
# ---------------------------------------------------------------------------
DEFAULT_INTERVAL=5
DEFAULT_MIRROR="https://raw.githubusercontent.com/koude/cfddns/main"

config_load() {
    # 默认值
    CF_API_TOKEN=""
    CF_ZONE_ID=""
    CF_ZONE_NAME=""
    INTERVAL="$DEFAULT_INTERVAL"
    UPDATE_MIRROR="$DEFAULT_MIRROR"
    # 覆盖
    [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
}

# config_set KEY VALUE —— 幂等 upsert 一个键（值会被引号包裹，可含特殊字符）
config_set() {
    _k=$1; _v=$2
    mkdir -p "$CFDDNS_DATA"; touch "$CONFIG_FILE"
    _tmp="$CONFIG_FILE.tmp.$$"
    awk -v k="$_k" -v v="$_v" '
        BEGIN { done = 0 }
        $0 ~ "^" k "=" { print k "=\"" v "\""; done = 1; next }
        { print }
        END { if (!done) print k "=\"" v "\"" }
    ' "$CONFIG_FILE" >"$_tmp" && mv -f "$_tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE" 2>/dev/null   # 含 API Token，限权
}

config_ready() {
    [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ]
}

# 合法的全局配置键
CONFIG_KEYS="CF_API_TOKEN CF_ZONE_ID CF_ZONE_NAME INTERVAL UPDATE_MIRROR"

config_key_valid() {
    for _ck in $CONFIG_KEYS; do [ "$_ck" = "$1" ] && return 0; done
    return 1
}

# 脱敏展示当前配置（Token 只露首尾各 4 位）
config_show() {
    config_load
    if [ -n "$CF_API_TOKEN" ]; then
        _head=$(printf '%s' "$CF_API_TOKEN" | cut -c1-4)
        _tail=$(printf '%s' "$CF_API_TOKEN" | sed -E 's/.*(.{4})$/\1/')
        _tmask="${_head}****${_tail}"
    else
        _tmask="(未设置)"
    fi
    printf 'CF_API_TOKEN  = %s\n' "$_tmask"
    printf 'CF_ZONE_ID    = %s\n' "${CF_ZONE_ID:-(未设置)}"
    printf 'CF_ZONE_NAME  = %s\n' "${CF_ZONE_NAME:-(未设置)}"
    printf 'INTERVAL      = %s (分钟)\n' "$INTERVAL"
    printf 'UPDATE_MIRROR = %s\n' "$UPDATE_MIRROR"
}

# ---------------------------------------------------------------------------
# 记录表 records.conf
# 每行：name|type|source|param|ttl|proxied|record_id
#   type    : A | AAAA
#   source  : wan4（路由器公网 IPv4） | host6（按内网主机取 GUA）
#   param   : host6 时 = 内网IPv4 或 MAC，可追加 ",后缀" 用于精确过滤（如 192.168.31.50,::100）
#   record_id: 首次解析后回填缓存
# 以 # 开头为注释。
# ---------------------------------------------------------------------------

# 输出有效记录行（去注释/空行/字段不足的行）
records_read() {
    [ -f "$RECORDS_FILE" ] || return 0
    awk -F'|' '!/^[[:space:]]*#/ && NF>=6 && $1!=""' "$RECORDS_FILE"
}

record_count() {
    records_read | grep -c . 2>/dev/null || echo 0
}

# record_add name type source param ttl proxied
record_add() {
    mkdir -p "$CFDDNS_DATA"; touch "$RECORDS_FILE"
    printf '%s|%s|%s|%s|%s|%s|\n' \
        "$1" "$2" "$3" "$4" "${5:-60}" "${6:-false}" >>"$RECORDS_FILE"
}

# record_del_index N —— 删除第 N 条有效记录（1 起，供菜单用）
record_del_index() {
    _idx=$1
    [ -f "$RECORDS_FILE" ] || return 1
    _tmp="$RECORDS_FILE.tmp.$$"
    awk -F'|' -v target="$_idx" '
        /^[[:space:]]*#/ || NF<6 || $1=="" { print; next }
        { n++; if (n==target) next; print }
    ' "$RECORDS_FILE" >"$_tmp" && mv -f "$_tmp" "$RECORDS_FILE"
}

# record_set_id name type id —— 回填某条记录的 record_id 缓存
record_set_id() {
    _name=$1; _type=$2; _id=$3
    [ -f "$RECORDS_FILE" ] || return 1
    _tmp="$RECORDS_FILE.tmp.$$"
    awk -F'|' -v OFS='|' -v n="$_name" -v t="$_type" -v id="$_id" '
        /^[[:space:]]*#/ || NF<6 || $1=="" { print; next }
        $1==n && $2==t { $7=id; print; next }
        { print }
    ' "$RECORDS_FILE" >"$_tmp" && mv -f "$_tmp" "$RECORDS_FILE"
}
