#!/bin/sh
# core.sh —— DDNS 引擎
# 遍历记录表 → 取址 → 与本地状态缓存比对 → 调用 CF 更新 → 写回状态。
# 依赖 common.sh / config.sh / ipsource.sh / cloudflare.sh。

# ---------------------------------------------------------------------------
# 状态缓存（name|type=value）
# ---------------------------------------------------------------------------
_state_key() { printf '%s|%s' "$1" "$2"; }

state_get() {
    [ -f "$STATE_FILE" ] || return 1
    _k=$(_state_key "$1" "$2")
    awk -F'=' -v k="$_k" '$1==k{print $2; exit}' "$STATE_FILE"
}

state_set() {
    _k=$(_state_key "$1" "$2"); _v=$3
    mkdir -p "$CFDDNS_DATA"; touch "$STATE_FILE"
    _tmp="$STATE_FILE.tmp.$$"
    awk -v k="$_k" -v v="$_v" '
        BEGIN { d = 0 }
        index($0, k "=") == 1 { print k "=" v; d = 1; next }
        { print }
        END { if (!d) print k "=" v }
    ' "$STATE_FILE" >"$_tmp" && mv -f "$_tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# 主流程：core_run [--force] [--dry-run]
# ---------------------------------------------------------------------------
core_run() {
    _force=0; _dry=0
    for _a in "$@"; do
        case "$_a" in
            --force)   _force=1 ;;
            --dry-run) _dry=1 ;;
            *) log_warn "core_run: 忽略未知参数 $_a" ;;
        esac
    done

    require_cmd curl
    config_load

    if [ "$_dry" = 0 ] && ! config_ready; then
        die "未配置 Cloudflare（缺 CF_API_TOKEN / CF_ZONE_ID），请编辑 ${CONFIG_FILE}（参考 config.example）"
    fi
    if [ "$(record_count)" -le 0 ] 2>/dev/null; then
        die "记录表为空，请在 $RECORDS_FILE 添加记录（参考 records.example）"
    fi

    log_info "===== 开始检查（force=${_force} dry-run=${_dry}）====="

    records_read | while IFS='|' read -r name type source param ttl proxied rid; do
        name=$(trim "$name"); type=$(trim "$type"); source=$(trim "$source")
        param=$(trim "$param"); rid=$(trim "$rid")
        ttl=${ttl:-60}; proxied=${proxied:-false}
        [ -n "$name" ] || continue

        ip=$(ipsource_resolve "$source" "$param") || { log_warn "[$name $type] 取址失败，跳过"; continue; }

        if [ "$_dry" = 1 ]; then
            log_ok "[$name $type] 探测到 = ${ip}（dry-run，不更新）"
            continue
        fi

        last=$(state_get "$name" "$type")
        if [ "$_force" = 0 ] && [ -n "$last" ] && [ "$ip" = "$last" ]; then
            log_info "[$name $type] 未变化（${ip}），跳过"
            continue
        fi

        # 需要 record_id：优先用 records.conf 缓存，否则查 CF（顺便回填、并对齐 state）
        if [ -z "$rid" ]; then
            info=$(cf_resolve_record "$name" "$type") || { log_warn "[$name $type] 解析记录ID失败，跳过"; continue; }
            rid=$(printf '%s' "$info" | cut -f1)
            cur=$(printf '%s' "$info" | cut -f2)
            if [ -z "$rid" ]; then
                rid=$(cf_create_record "$type" "$name" "$ip" "$ttl" "$proxied") || continue
                record_set_id "$name" "$type" "$rid"
                state_set "$name" "$type" "$ip"
                log_ok "[$name $type] 记录不存在，已新建并设为 $ip"
                continue
            fi
            record_set_id "$name" "$type" "$rid"
            if [ "$_force" = 0 ] && [ "$cur" = "$ip" ]; then
                state_set "$name" "$type" "$ip"
                log_info "[$name $type] CF 上已是 ${ip}，仅同步本地状态"
                continue
            fi
        fi

        if cf_update_record "$rid" "$type" "$name" "$ip" "$ttl" "$proxied"; then
            state_set "$name" "$type" "$ip"
            log_ok "[$name $type] 已更新为 $ip"
        else
            log_warn "[$name $type] 更新失败，保留旧状态，下次重试"
        fi
    done

    log_info "===== 检查结束 ====="
}
