#!/bin/sh
# ipsource.sh —— 取址模块
# 提供按 source 类型解析出当前应写入 DNS 的 IP。
#   wan4   路由器公网 IPv4 出口
#   host6  内网某台主机的公网 IPv6 GUA（按 MAC 在邻居表中查）
# 依赖 common.sh（have / 日志）。

# ---------------------------------------------------------------------------
# 校验器
# ---------------------------------------------------------------------------
is_ipv4() {
    case "$1" in
        ''|*[!0-9.]*) return 1 ;;
    esac
    printf '%s' "$1" | awk -F. '
        NF!=4 { exit 1 }
        { for (i=1;i<=4;i++) if ($i=="" || $i<0 || $i>255) exit 1 }
    '
}

is_ipv6() { case "$1" in *:*) return 0 ;; *) return 1 ;; esac; }

is_mac() { printf '%s' "$1" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; }

normalize_mac() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# ---------------------------------------------------------------------------
# wan4：路由器公网 IPv4 出口
#   首选 Cloudflare 的 cdn-cgi/trace（返回的 ip= 即对端看到的公网 IP），
#   失败回退 api.ipify.org。
# ---------------------------------------------------------------------------
ipsource_wan4() {
    _ip=$(curl -4 -fsS --max-time 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
            | sed -n 's/^ip=//p')
    if ! is_ipv4 "$_ip"; then
        _ip=$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null)
    fi
    if is_ipv4 "$_ip"; then
        printf '%s\n' "$_ip"; return 0
    fi
    log_error "wan4: 取公网 IPv4 失败"
    return 1
}

# ---------------------------------------------------------------------------
# 由内网 IPv4 解析 MAC
# ---------------------------------------------------------------------------
arp_mac() {
    _ip=$1
    # 先尝试唤醒邻居表项（best-effort）
    ping -c 1 -W 1 "$_ip" >/dev/null 2>&1 || ping -c 1 "$_ip" >/dev/null 2>&1
    if have ip; then
        _m=$(ip neigh show "$_ip" 2>/dev/null \
                | awk '{for(i=1;i<=NF;i++) if($i=="lladdr"){print $(i+1); exit}}')
        [ -n "$_m" ] && { printf '%s\n' "$_m"; return 0; }
    fi
    if [ -r /proc/net/arp ]; then
        _m=$(awk -v ip="$_ip" '$1==ip{print $4; exit}' /proc/net/arp)
        case "$_m" in
            ''|00:00:00:00:00:00) : ;;
            *) printf '%s\n' "$_m"; return 0 ;;
        esac
    fi
    return 1
}

# ---------------------------------------------------------------------------
# 邻居表中某 MAC 的全局 IPv6（2000::/3），EUI-64 稳定地址优先排前
# ---------------------------------------------------------------------------
neigh_gua_by_mac() {
    _mac=$(normalize_mac "$1")
    _list=$(ip -6 neigh 2>/dev/null | awk -v m="$_mac" '
        { ll=""
          for (i=1;i<=NF;i++) if ($i=="lladdr") ll=$(i+1)
          if (tolower(ll)==m) print $1
        }' | awk '/^[23]/' | sort -u)
    [ -n "$_list" ] || return 1
    # EUI-64（含 ff:fe）通常是稳定地址，排前；隐私临时地址排后
    printf '%s\n' "$_list" | grep -i 'ff:fe'
    printf '%s\n' "$_list" | grep -iv 'ff:fe'
}

# 在候选地址里按固定后缀精确匹配（如 ::100 -> 末组 100）
match_suffix() {
    _tail=${2##*:}
    printf '%s\n' "$1" | grep -iE ":$_tail\$" | head -n1
}

# ---------------------------------------------------------------------------
# host6：取内网主机的公网 GUA
#   param 形如  192.168.31.50        （内网IPv4）
#               192.168.31.50,::100  （内网IPv4 + 固定后缀，多候选时精确过滤）
#               aa:bb:cc:dd:ee:ff    （直接给 MAC）
# ---------------------------------------------------------------------------
ipsource_host6() {
    _param=$1
    _target=${_param%%,*}
    _suffix=""
    case "$_param" in *,*) _suffix=${_param#*,} ;; esac

    if is_mac "$_target"; then
        _mac=$(normalize_mac "$_target")
    else
        _mac=$(arp_mac "$_target") || {
            log_error "host6: 无法由内网 IP $_target 解析 MAC（主机在线吗？）"
            return 1
        }
    fi
    [ -n "$_mac" ] || return 1

    _cands=$(neigh_gua_by_mac "$_mac") || {
        log_warn "host6: 邻居表未找到 MAC $_mac 的公网 IPv6（需主机近期有 IPv6 流量）"
        return 1
    }
    log_info "host6: MAC=$_mac 候选GUA=[$(printf '%s' "$_cands" | tr '\n' ' ')]"

    if [ -n "$_suffix" ]; then
        _want=$(match_suffix "$_cands" "$_suffix")
        if [ -n "$_want" ]; then
            printf '%s\n' "$_want"; return 0
        fi
        log_warn "host6: 候选中未匹配到后缀 ${_suffix}，改取首个稳定地址"
    fi
    printf '%s\n' "$_cands" | head -n1
}

# ---------------------------------------------------------------------------
# 统一入口：ipsource_resolve <source> <param>
# ---------------------------------------------------------------------------
ipsource_resolve() {
    case "$1" in
        wan4)  ipsource_wan4 ;;
        host6) ipsource_host6 "$2" ;;
        *)     log_error "未知取址类型: $1"; return 1 ;;
    esac
}
