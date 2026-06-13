#!/bin/sh
# service.sh —— cron 持久化（照搬 ShellCrash 的机制：写 /etc/crontabs/root）
# 仅维护本项目自己的一行（以 "# cfddns" 结尾标记），绝不动其它条目（含 ShellCrash 的）。
# 依赖 common.sh（日志）与 CFDDNS_ROOT。
# CRONTAB_FILE 可用环境变量覆盖（便于测试）。

CRONTAB_FILE="${CRONTAB_FILE:-/etc/crontabs/root}"
CRON_TAG="# cfddns"

_cron_line() {
    printf '*/%s * * * * %s/scripts/cfddns.sh run >/dev/null 2>&1 %s' \
        "${1:-5}" "$CFDDNS_ROOT" "$CRON_TAG"
}

# busybox crond 每分钟自动扫描 crontab 变更；这里温和地触发一次重载，绝不强杀进程
_crond_reload() {
    if [ -x /etc/init.d/cron ]; then
        /etc/init.d/cron reload >/dev/null 2>&1 \
            || /etc/init.d/cron restart >/dev/null 2>&1 || :
    fi
    return 0
}

# 写入/更新 cfddns 的 cron 行（先备份、去重、原子替换）
service_cron_install() {
    _int=${1:-5}
    mkdir -p "$(dirname "$CRONTAB_FILE")"
    touch "$CRONTAB_FILE"
    cp -f "$CRONTAB_FILE" "$CRONTAB_FILE.cfddns.bak" 2>/dev/null
    _tmp="$CRONTAB_FILE.tmp.$$"
    grep -v "$CRON_TAG" "$CRONTAB_FILE" >"$_tmp" 2>/dev/null || :
    _cron_line "$_int" >>"$_tmp"
    printf '\n' >>"$_tmp"
    mv -f "$_tmp" "$CRONTAB_FILE"
    _crond_reload
    log_ok "已写入 cron（每 ${_int} 分钟一次），原 crontab 备份于 ${CRONTAB_FILE}.cfddns.bak"
}

# 移除 cfddns 的 cron 行（保留其它条目）
service_cron_remove() {
    [ -f "$CRONTAB_FILE" ] || return 0
    cp -f "$CRONTAB_FILE" "$CRONTAB_FILE.cfddns.bak" 2>/dev/null
    _tmp="$CRONTAB_FILE.tmp.$$"
    grep -v "$CRON_TAG" "$CRONTAB_FILE" >"$_tmp" 2>/dev/null || :
    mv -f "$_tmp" "$CRONTAB_FILE"
    _crond_reload
    log_ok "已移除 cfddns 的 cron 条目"
}

# 当前是否已安装 cron
service_cron_status() {
    [ -f "$CRONTAB_FILE" ] && grep -q "$CRON_TAG" "$CRONTAB_FILE"
}
