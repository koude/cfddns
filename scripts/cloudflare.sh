#!/bin/sh
# cloudflare.sh —— Cloudflare API v4 模块
# 依赖 common.sh（json_str/json_bool/日志）与已加载的全局配置（CF_API_TOKEN/CF_ZONE_ID）。

CF_API_BASE="https://api.cloudflare.com/client/v4"

# 底层请求：cf_api METHOD PATH [JSON_BODY] —— 输出响应体（含错误时的 JSON）
# 故意不加 curl -f，以便 4xx 时仍能拿到 CF 的错误 JSON 来解析。
cf_api() {
    _method=$1; _path=$2; _data=$3
    set -- -sS --max-time 20 -X "$_method" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json"
    [ -n "$_data" ] && set -- "$@" --data "$_data"
    curl "$@" "$CF_API_BASE$_path" 2>/dev/null
}

# 从响应里取第一条错误信息（用于日志）
cf_errmsg() {
    _m=$(printf '%s' "$1" | json_str message)
    [ -n "$_m" ] && printf '%s' "$_m" || printf '未知错误（响应: %.120s）' "$1"
}

# 校验 Token 是否有效
cf_verify_token() {
    _resp=$(cf_api GET "/user/tokens/verify")
    [ "$(printf '%s' "$_resp" | json_bool success)" = "true" ]
}

# 列出 Zone（需要 jq；无 jq 时请手动填 CF_ZONE_ID）。输出 "zone_id<TAB>zone_name" 每行一条。
cf_list_zones() {
    _resp=$(cf_api GET "/zones?per_page=50&status=active")
    [ "$(printf '%s' "$_resp" | json_bool success)" = "true" ] || {
        log_error "列出 Zone 失败: $(cf_errmsg "$_resp")"; return 1
    }
    if have jq; then
        printf '%s' "$_resp" | jq -r '.result[] | "\(.id)\t\(.name)"'
    else
        log_warn "无 jq，无法自动列出 Zone，请手动填写 CF_ZONE_ID"
        return 2
    fi
}

# 解析记录：cf_resolve_record NAME TYPE —— 输出 "record_id<TAB>current_content"
#   记录不存在时 record_id 为空（content 也空），调用方可据此决定 PATCH 还是 POST。
cf_resolve_record() {
    _name=$1; _type=$2
    _resp=$(cf_api GET "/zones/$CF_ZONE_ID/dns_records?type=$_type&name=$_name")
    [ "$(printf '%s' "$_resp" | json_bool success)" = "true" ] || {
        log_error "查询记录 $_name($_type) 失败: $(cf_errmsg "$_resp")"; return 2
    }
    _id=$(printf '%s' "$_resp" | json_str id)
    _content=$(printf '%s' "$_resp" | json_str content)
    printf '%s\t%s\n' "$_id" "$_content"
}

# 更新记录：cf_update_record ID TYPE NAME CONTENT TTL PROXIED
cf_update_record() {
    _body=$(printf '{"type":"%s","name":"%s","content":"%s","ttl":%s,"proxied":%s}' \
        "$2" "$3" "$4" "${5:-60}" "${6:-false}")
    _resp=$(cf_api PATCH "/zones/$CF_ZONE_ID/dns_records/$1" "$_body")
    [ "$(printf '%s' "$_resp" | json_bool success)" = "true" ] && return 0
    log_error "更新记录 $3($2) 失败: $(cf_errmsg "$_resp")"
    return 1
}

# 新建记录：cf_create_record TYPE NAME CONTENT TTL PROXIED —— 成功时 stdout 输出新 record_id
cf_create_record() {
    _body=$(printf '{"type":"%s","name":"%s","content":"%s","ttl":%s,"proxied":%s}' \
        "$1" "$2" "$3" "${4:-60}" "${5:-false}")
    _resp=$(cf_api POST "/zones/$CF_ZONE_ID/dns_records" "$_body")
    if [ "$(printf '%s' "$_resp" | json_bool success)" = "true" ]; then
        printf '%s\n' "$(printf '%s' "$_resp" | json_str id)"
        return 0
    fi
    log_error "新建记录 $2($1) 失败: $(cf_errmsg "$_resp")"
    return 1
}
