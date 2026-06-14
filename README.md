# cfddns

类 ShellCrash 风格的 **Cloudflare DDNS** 脚本，面向路由器（首发适配 Redmi AX6000 官方固件）与一般 Linux。
纯 POSIX / busybox `ash` 实现，**无需 jq、无需额外运行时**。

特别支持一个其它 DDNS 工具普遍做不到的场景：**在路由器上、按内网主机的 MAC 取到它当前的公网 IPv6（GUA），把 AAAA 记录指向内网某台主机**，自动跟随 ISP 前缀变化。

## 特性

- ☁️ 只对接 **Cloudflare**（API v4，使用 Scoped API Token）
- 🌐 **IPv4 + IPv6** 双栈，单条配置维护多条 A / AAAA 记录、多台主机
- 🧭 取址方式可扩展：
  - `wan4` — 路由器公网 IPv4 出口
  - `host6` — 内网主机的公网 IPv6 GUA（内网 IP → MAC → 邻居表，按当前 LAN 前缀过滤、排除失效/旧地址）
- 🧰 一键安装、**交互式菜单 TUI**、**命令行选项**两种用法
- 🔁 **在线更新**（比对远端 `version`，更新程序、保留配置）
- 💾 持久化：装到 `/data`，靠 `crontab` 定时与重启自启（与 ShellCrash 同机制）
- 🗒️ 仅写 `/data` 目录 + crontab（可选 `/etc/profile` 加全局命令）；**不碰网络/防火墙**

## 依赖

`sh`(busybox ash)、`curl`、`ip`、`crond`/`crontab`、`awk`/`sed`/`grep`。AX6000 官方固件均自带；无需 `jq`。

## 安装

在路由器上（已 SSH/root）。

**一键直装**（自动从镜像源下载）：

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/koude/cfddns/main/install.sh)"
```

自定义间隔或镜像源（国内直连 GitHub 慢时）：

```sh
CFDDNS_INTERVAL=3 url=https://cdn.jsdelivr.net/gh/koude/cfddns@main \
  sh -c "$(curl -fsSL https://cdn.jsdelivr.net/gh/koude/cfddns@main/install.sh)"
```

**或本地安装**（先下载解压再装）：

```sh
cd /tmp
curl -L -o cfddns.tar.gz https://codeload.github.com/koude/cfddns/tar.gz/refs/heads/main
tar -xzf cfddns.tar.gz 2>/dev/null || { gunzip -f cfddns.tar.gz && tar -xf cfddns.tar; }
cd cfddns-main && sh install.sh 5
```

安装只做两件写操作：复制文件到 `/data/cfddns`、往 `/etc/crontabs/root` 加一行（加前自动备份为 `*.cfddns.bak`）。

## 配置

可用菜单，也可用命令行选项（二选一）。

### 命令行

```sh
DIR=/data/cfddns/scripts/cfddns.sh

# 1) Cloudflare 凭证（Token 需含该 Zone 的 DNS:Edit + Zone:Read）
$DIR config set CF_API_TOKEN  <你的Token>
$DIR config set CF_ZONE_ID    <你的ZoneID>
$DIR config set CF_ZONE_NAME  example.com      # 可选，仅展示

# 2) 记录（示例：群晖 + Debian，各 A+AAAA）
$DIR record add nas.example.com A    wan4
$DIR record add nas.example.com AAAA host6 192.168.50.3,::3
$DIR record add deb.example.com A    wan4
$DIR record add deb.example.com AAAA host6 192.168.50.6

# 3) 验证 / 运行
$DIR config show                 # Token 脱敏展示
$DIR record list
$DIR run --dry-run               # 只探测打印，不调用 API
$DIR run --force                 # 强制推送一次
```

### 菜单

```sh
/data/cfddns/scripts/cfddns.sh          # 进入交互菜单
# 或安装全局命令后（菜单「定时与服务」里开启），重新登录即可直接：
cfddns
```

### 记录字段（`conf/records.conf`）

```
name | type | source | param | ttl | proxied | record_id
```

| 字段 | 说明 |
|------|------|
| `type` | `A` 或 `AAAA` |
| `source` | `wan4`（路由器公网 IPv4）/ `host6`（按内网主机取 GUA） |
| `param` | `wan4` 留空；`host6` 填「内网IPv4」或「MAC」，可加 `,固定后缀`（如 `192.168.50.3,::3`） |
| `proxied` | 直连内网主机务必 `false` |
| `record_id` | 留空，首次运行自动回填缓存 |

> `host6` 取址：内网IP → ARP 取 MAC → `ip -6 neigh` 候选 → 按当前 LAN /64 前缀过滤（丢弃 ISP 换前缀后残留的旧地址）→ EUI-64 优先 / 有后缀则精确匹配。
> 群晖等手设了静态后缀的主机建议填后缀（如 `::3`）；地址干净（单一稳定 GUA）的主机可留空。

## 外网访问的前置条件（需你自行在路由器配置）

- **IPv4**：多台主机共用一个公网 IPv4，需在路由器配 **端口转发**，靠端口区分服务。
- **IPv6**：无 NAT，AAAA 直接指向主机 GUA，需在路由器 **防火墙放行入站** 到该主机的对应端口（pinhole）。

## 常用命令

```sh
cfddns                 # 交互菜单（TTY 下裸跑即进菜单）
cfddns run [--dry-run|--force]
cfddns config set|get|show
cfddns record list|add|del <序号>
cfddns update          # 在线更新（保留配置）
cfddns check-update
cfddns uninstall       # 移除 cron（程序文件保留）
```

## 更新

```sh
cfddns update          # 比对远端 version，仅覆盖程序文件，保留 conf/
```

镜像源可改：`cfddns config set UPDATE_MIRROR <raw根地址>`（支持 GitHub raw / jsDelivr 等）。

## 卸载

```sh
cfddns uninstall                 # 移除 cron 与全局命令
rm -rf /data/cfddns              # 如需彻底删除程序与配置
```
回滚 crontab：`cp /etc/crontabs/root.cfddns.bak /etc/crontabs/root`

## FAQ

- **IPv6 能像 IPv4 那样“指向路由器再端口转发到内网主机”吗？** 不能。IPv6 无 NAT，AAAA 必须直接指向目标主机的 GUA，路由器只做防火墙放行。
- **没有公网 IPv4（CGNAT）怎么办？** 只配 `AAAA`（`host6`）即可，A 记录可不加。
- **Debian/Linux 有隐私临时地址导致取址漂移？** 关闭隐私扩展，或给主机设固定后缀并在 `param` 里用 `,::6` 锁定。

## 许可

[MIT](LICENSE) © 2026 koude
