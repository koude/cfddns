#!/bin/sh
# update.sh —— 在线更新
# 从 UPDATE_MIRROR（raw 根地址）按文件清单逐个下载到临时目录，全部成功后再覆盖，
# 只更新程序文件 + 示例 + version，保留 conf/config 与 conf/records.conf。
# 依赖 common.sh / config.sh。

# 需要随更新覆盖的文件清单（相对仓库根）
UPDATE_FILES="version install.sh \
scripts/common.sh scripts/config.sh scripts/ipsource.sh scripts/cloudflare.sh \
scripts/core.sh scripts/service.sh scripts/menu.sh scripts/update.sh scripts/cfddns.sh \
conf/config.example conf/records.example"

# 比较版本：_ver_gt A B → A 比 B 新返回 0（按点分数字逐段比较）
_ver_gt() {
    awk -v a="$1" -v b="$2" '
        function cmp(x, y,  na, nb, pa, pb, i, n) {
            na = split(x, pa, "."); nb = split(y, pb, ".")
            n = (na > nb) ? na : nb
            for (i = 1; i <= n; i++) {
                if ((pa[i]+0) > (pb[i]+0)) return 1
                if ((pa[i]+0) < (pb[i]+0)) return -1
            }
            return 0
        }
        BEGIN { exit (cmp(a, b) == 1 ? 0 : 1) }
    '
}

# 取远端版本号
update_remote_version() {
    config_load
    curl -fsSL --max-time 15 "${UPDATE_MIRROR}/version" 2>/dev/null | tr -d '[:space:]'
}

# 仅检查是否有新版本（不改动）
update_check() {
    _remote=$(update_remote_version)
    _local=$(read_version)
    [ -n "$_remote" ] || { log_error "无法获取远端版本（检查 UPDATE_MIRROR / 网络）"; return 2; }
    log_info "本地版本 ${_local}，远端版本 ${_remote}"
    if _ver_gt "$_remote" "$_local"; then
        log_info "有新版本可更新：${_local} → ${_remote}"
        return 0
    fi
    log_ok "已是最新版本（${_local}）"
    return 1
}

# 执行更新
update_run() {
    require_cmd curl
    config_load
    _remote=$(update_remote_version)
    _local=$(read_version)
    [ -n "$_remote" ] || die "无法获取远端版本（检查 UPDATE_MIRROR / 网络）"
    if ! _ver_gt "$_remote" "$_local"; then
        log_ok "已是最新版本（${_local}），无需更新"
        return 0
    fi
    log_info "开始更新：${_local} → ${_remote}（镜像源 ${UPDATE_MIRROR}）"

    _tmp=$(mktemp -d 2>/dev/null || echo "/tmp/cfddns-up.$$")
    mkdir -p "$_tmp"
    # 1) 全部下载到临时目录，任一失败即中止（保证原子性）
    for _f in $UPDATE_FILES; do
        mkdir -p "$_tmp/$(dirname "$_f")"
        if ! curl -fsSL --max-time 30 "${UPDATE_MIRROR}/${_f}" -o "$_tmp/$_f" || [ ! -s "$_tmp/$_f" ]; then
            rm -rf "$_tmp"
            die "下载失败：${_f}（已中止，未改动任何文件）"
        fi
    done

    # 2) 覆盖到安装目录（不动 conf/config 与 conf/records.conf）
    for _f in $UPDATE_FILES; do
        mkdir -p "$CFDDNS_ROOT/$(dirname "$_f")"
        cp -f "$_tmp/$_f" "$CFDDNS_ROOT/$_f"
    done
    chmod +x "$CFDDNS_ROOT"/scripts/*.sh "$CFDDNS_ROOT/install.sh" 2>/dev/null
    rm -rf "$_tmp"

    log_ok "已更新到 ${_remote}。如改动了 cron 行为，可在菜单重新安装定时。"
}
