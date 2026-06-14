#!/bin/sh
# menu.sh —— 交互式菜单 TUI
# 由 cfddns.sh 调用（menu_main）。复用 config/record/core/service 各函数。
# 全程 POSIX/busybox ash；菜单临时变量统一加 m_ 前缀，避免覆盖被调用函数的内部变量。

_clear() { command -v clear >/dev/null 2>&1 && clear || printf '\n\n'; }
_pause() { printf '\n按回车继续...'; read -r m_dummy; }
_yesno() {
    printf '%s [y/N]: ' "$1"; read -r m_ans
    case "$m_ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

menu_header() {
    config_load
    _clear
    m_tok="未设置"; [ -n "$CF_API_TOKEN" ] && m_tok="已设置"
    m_cron="未装"; service_cron_status && m_cron="已装"
    m_sc="未装"; service_shortcut_status && m_sc="已装"
    printf '========== CFDDNS %s ==========\n' "$(read_version)"
    printf ' Zone : %s   Token: %s\n' "${CF_ZONE_NAME:-未设置}" "$m_tok"
    printf ' 记录 : %s 条   cron: %s   全局命令: %s\n' "$(record_count)" "$m_cron" "$m_sc"
    printf '=====================================\n'
}

# --- Cloudflare 配置 ---
menu_cf() {
    while true; do
        menu_header
        printf ' [Cloudflare 配置]\n'
        printf '  1) 设置 API Token\n'
        printf '  2) 设置 Zone ID\n'
        printf '  3) 设置 Zone 名称（仅展示）\n'
        printf '  4) 校验 Token\n'
        printf '  5) 查看当前配置（脱敏）\n'
        printf '  0) 返回\n'
        printf '请选择: '; read -r m_c
        case "$m_c" in
            1) printf '输入 CF API Token: '; read -r m_v
               [ -n "$m_v" ] && config_set CF_API_TOKEN "$m_v" && log_ok "已保存"; _pause ;;
            2) printf '输入 Zone ID: '; read -r m_v
               [ -n "$m_v" ] && config_set CF_ZONE_ID "$m_v" && log_ok "已保存"; _pause ;;
            3) printf '输入 Zone 名称: '; read -r m_v
               [ -n "$m_v" ] && config_set CF_ZONE_NAME "$m_v" && log_ok "已保存"; _pause ;;
            4) config_load
               if cf_verify_token; then log_ok "Token 有效"; else log_error "Token 无效或网络不通"; fi
               _pause ;;
            5) config_show; _pause ;;
            0) return ;;
        esac
    done
}

# --- 记录管理 ---
menu_record_add() {
    printf '完整域名（如 nas.example.com）: '; read -r m_name
    [ -n "$m_name" ] || { log_warn "已取消"; return; }
    printf '记录类型  1) A(IPv4)   2) AAAA(IPv6): '; read -r m_t
    case "$m_t" in
        1) m_type=A;  m_src=wan4; m_param=""
           echo "→ IPv4 取路由器公网出口（wan4）" ;;
        2) m_type=AAAA; m_src=host6
           printf '内网主机 IPv4（如 192.168.50.3）: '; read -r m_ip
           [ -n "$m_ip" ] || { log_warn "已取消"; return; }
           printf '固定后缀（可空；群晖建议 ::3，纯净的虚拟机可留空）: '; read -r m_sfx
           if [ -n "$m_sfx" ]; then m_param="${m_ip},${m_sfx}"; else m_param="$m_ip"; fi ;;
        *) log_warn "无效选择"; return ;;
    esac
    printf 'TTL 秒（默认 60）: '; read -r m_ttl; m_ttl=${m_ttl:-60}
    record_add "$m_name" "$m_type" "$m_src" "$m_param" "$m_ttl" false
    log_ok "已添加: ${m_name} ${m_type} ${m_src} ${m_param:-—}"
}

menu_record() {
    while true; do
        menu_header
        printf ' [记录管理]\n'
        cmd_record list
        printf '\n  1) 添加记录    2) 删除记录    0) 返回\n'
        printf '请选择: '; read -r m_c
        case "$m_c" in
            1) menu_record_add; _pause ;;
            2) printf '输入要删除的序号: '; read -r m_v
               printf '%s' "$m_v" | grep -qE '^[0-9]+$' && record_del_index "$m_v" && log_ok "已删除第 ${m_v} 条" || log_warn "无效序号"
               _pause ;;
            0) return ;;
        esac
    done
}

# --- 立即更新 ---
menu_run() {
    menu_header
    printf ' [立即更新]\n'
    printf '  1) 试运行（dry-run，只探测不改 CF）\n'
    printf '  2) 正常更新（有变化才推送）\n'
    printf '  3) 强制更新（--force）\n'
    printf '  0) 返回\n'
    printf '请选择: '; read -r m_c
    case "$m_c" in
        1) echo; core_run --dry-run ;;
        2) echo; core_run ;;
        3) echo; core_run --force ;;
        *) return ;;
    esac
    _pause
}

# --- 定时与服务 ---
menu_service() {
    while true; do
        menu_header
        printf ' [定时与服务]\n'
        printf '  1) 安装/更新 cron 定时\n'
        printf '  2) 移除 cron\n'
        printf '  3) 安装全局命令 cfddns（写 /etc/profile）\n'
        printf '  4) 移除全局命令\n'
        printf '  0) 返回\n'
        printf '请选择: '; read -r m_c
        case "$m_c" in
            1) printf '间隔分钟（默认 5）: '; read -r m_i; m_i=${m_i:-5}
               case "$m_i" in
                   ''|*[!0-9]*) log_warn "需为数字" ;;
                   *) service_cron_install "$m_i" ;;
               esac; _pause ;;
            2) service_cron_remove; _pause ;;
            3) service_shortcut_install; _pause ;;
            4) service_shortcut_remove; _pause ;;
            0) return ;;
        esac
    done
}

# --- 状态与日志 ---
menu_status() {
    menu_header
    printf ' [状态与日志]\n\n'
    config_show
    printf '\n--- 记录 ---\n'; cmd_record list
    printf '\n--- 日志（末 15 行）---\n'
    if [ -f "$CFDDNS_LOG" ]; then tail -n 15 "$CFDDNS_LOG"; else echo "（暂无日志）"; fi
    _pause
}

# --- 卸载 ---
menu_uninstall() {
    menu_header
    if _yesno "确认移除 cron 与全局命令？（配置/程序文件保留）"; then
        service_cron_remove
        service_shortcut_remove
        log_ok "已移除 cron 与全局命令；程序文件仍在 ${CFDDNS_ROOT}"
        echo "如需彻底删除程序与配置: rm -rf ${CFDDNS_ROOT}"
    fi
    _pause
}

# --- 主菜单 ---
menu_main() {
    while true; do
        menu_header
        printf '  1) 配置 Cloudflare\n'
        printf '  2) 记录管理\n'
        printf '  3) 立即更新\n'
        printf '  4) 定时与服务\n'
        printf '  5) 状态与日志\n'
        printf '  6) 在线更新（Phase 4）\n'
        printf '  7) 卸载\n'
        printf '  0) 退出\n'
        printf '请选择: '; read -r m_c
        case "$m_c" in
            1) menu_cf ;;
            2) menu_record ;;
            3) menu_run ;;
            4) menu_service ;;
            5) menu_status ;;
            6) echo "在线更新将在 Phase 4 提供。"; _pause ;;
            7) menu_uninstall ;;
            0) echo "再见。"; return 0 ;;
            *) ;;
        esac
    done
}
