# 3xui Geo Updater

[English](README.md) | [简体中文](README_zh.md) | [Русский](README_ru.md) | [فارسی](README_fa.md)

一个轻量级、多语言的 **3x-ui** Geo 文件自动更新工具，支持数据源选择、定时更新、日志记录和安全的重启机制。

![Main Menu Preview](screenshots/main-menu-preview.png)

该工具可帮助基于 3x-ui 部署的环境保持 Geo 相关规则文件的最新状态，同时避免不必要的服务中断。它支持多个上游数据源、灵活的定时任务、简单的命令行菜单，并且**仅在文件实际发生变化时**才会触发重启。

## 功能特性

- 多语言界面
  - 简体中文
  - 英语 (English)
  - 俄语 (Русский)
  - 波斯语 (فارسی)
- 首次运行语言选择
- 支持多种 Geo 规则数据源
- 支持单选或多选数据源
- 定时更新模式
  - 每天 (Daily)
  - 每周 (Weekly)
  - 每 N 天 (Every N days)
  - 自定义 cron 表达式
- 默认执行时间：**03:00**
- **仅当文件实际发生改变时才重启 x-ui**
- 日志记录支持
- 内置卸载选项
- 内置 Swap (虚拟内存) 管理菜单
- 快捷命令：
  - `xgeo`
  - `3xui-geo`
- 自动选择定时器后端
  - 标准系统使用系统自带的 cron
  - 受支持的小内存 RHEL 系系统自动使用 **Supercronic**
- Supercronic 模式包含：
  - systemd 服务管理
  - 开机自启
  - 故障自动重启

## 支持的数据源

本项目目前支持以下 Geo 规则上游源：

1. **Loyalsoldier**
   - `geoip.dat`
   - `geosite.dat`

2. **chocolate4u**
   - `geoip_IR.dat`
   - `geosite_IR.dat`

3. **runetfreedom**
   - `geoip_RU.dat`
   - `geosite_RU.dat`

## 工作原理

更新器会从配置的上游源下载最新的 Geo 文件，并将其与当前安装的本地文件进行比对。只有在文件内容发生实质性变化时，才会进行替换。

如果至少有一个选中的文件发生了更新，脚本将重启 `x-ui` 服务，以使新的 Geo 数据生效。

如果所有文件内容均未发生改变，**则不会触发任何重启操作**。

## 为什么需要这个项目

虽然 3x-ui 面板本身提供了手动更新 Geo 文件的选项，但许多用户希望拥有一个更加安全、自动化的维护流程。

本项目旨在补充以下体验：

- 自动化定时执行
- 灵活的数据源选择
- 多语言交互式管理界面
- 运行日志留存
- 仅在必要时才重启的安全逻辑
- 首次运行语言选择
- 为长期维护节点提供更便捷的操作体验

## 环境要求

- Linux 服务器
- 已安装并正常运行的 `3x-ui`
- Root 权限
- 系统需具备以下基础工具：
  - `bash`, `curl`, `cmp`, `install`, `awk`, `grep`, `mktemp`, `date`, `xargs`

本安装程序主要依赖标准 Linux 系统上通常自带的通用实用工具。

在标准系统上，如果系统缺失 cron，安装程序会自动尝试安装并启动它。
在受支持的小内存 RHEL 系系统上，安装程序将自动切换为使用 **Supercronic** 而非系统 cron。

## 安装指南

### 快速安装
安装程序会自动选择定时器后端：
- 在标准系统上，它使用系统 cron 并会在需要时尝试安装/启动它。
- 在受支持的小内存 RHEL 系系统上，它会自动切换为 **Supercronic**。
```bash
curl -fsSL -o install-3xui-geo-updater.sh [https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh](https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh) && chmod +x install-3xui-geo-updater.sh && bash install-3xui-geo-updater.sh
```

### 1. 下载安装脚本

将安装脚本下载到您的服务器上，例如：

```bash
curl -fsSL -o install-3xui-geo-updater.sh [https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh](https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh)
```

或者克隆整个代码仓库：

```bash
git clone [https://github.com/violetaini/3xui-geo-auto-update.git](https://github.com/violetaini/3xui-geo-auto-update.git)
cd 3xui-geo-auto-update
```

### 2. 赋予执行权限

```bash
chmod +x install-3xui-geo-updater.sh
```

### 3. 以 root 权限运行安装程序

```bash
sudo bash install-3xui-geo-updater.sh
```

安装完成后，管理菜单将会自动启动。

### 首次运行
在首次运行时，脚本会要求您在进入主菜单前选择一种语言。
选择后，系统将保存您的偏好并在日后自动使用该语言。

## 使用方法

**打开管理菜单：**

```bash
xgeo
```

或

```bash
3xui-geo
```

**手动运行更新检查：**
打开菜单并选择：`立即运行更新检查`

**卸载脚本：**

```bash
xgeo uninstall
```

您也可以直接在管理菜单中选择卸载选项。

## 菜单概览

管理面板支持以下操作：

- 配置或修改自动更新
- 立即运行更新检查
- 查看运行日志
- 查看当前配置
- 切换显示语言
- 移除定时任务
- Swap (虚拟内存) 管理
- 卸载本脚本

## 定时模式说明

更新器支持以下定时调度模式：

- **每天 (Daily):** 每天凌晨 03:00 运行
- **每周 (Weekly):** 每周指定某天的凌晨 03:00 运行
- **每 N 天 (Every N Days):** 每隔 N 天的凌晨 03:00 运行
- **自定义 (Custom Cron):** 供高级用户使用标准的 cron 表达式进行完全控制

## 定时器后端说明 (Scheduler Backend)

本项目支持两种定时器后端：

### 1. 系统 cron
用于标准系统。
如果 cron 缺失，安装程序会自动尝试安装并启动它。

### 2. Supercronic
在受支持的小内存 RHEL 系系统上自动使用。

目前，当系统总内存低于 **2 GiB** 时，以下系统将被强制使用 Supercronic 模式：
- Anolis
- CentOS Stream
- Oracle Linux
- AlmaLinux
- Rocky Linux
- Alibaba Cloud Linux

在 Supercronic 模式下，安装程序将：
- 下载 Supercronic 的独立可执行文件
- 创建专用的 crontab 文件
- 创建 systemd 服务
- 启用开机自动启动
- 启用故障自动重启

## 日志记录

默认日志文件路径：

```bash
/var/log/3xui-geo-updater.log
```

查看最后 50 行日志：

```bash
tail -n 50 /var/log/3xui-geo-updater.log
```

实时追踪日志输出：

```bash
tail -f /var/log/3xui-geo-updater.log
```

## 已安装组件

安装程序会在系统中创建以下文件：

- `/usr/local/bin/3xui-geo-runner.sh`
- `/usr/local/bin/3xui-geo-manager.sh`
- `/usr/local/bin/3xui-geo-uninstall.sh`
- `/usr/local/bin/xgeo`
- `/usr/local/bin/3xui-geo`

配置文件：
- `/etc/3xui-geo-updater.conf`

状态记录目录：
- `/var/lib/3xui-geo-updater`

日志文件：
- `/var/log/3xui-geo-updater.log`

当启用 Supercronic 模式时，安装程序还会创建：
- `/usr/local/bin/supercronic`
- `/etc/3xui-geo-updater.cron`
- `/etc/systemd/system/3xui-geo-supercronic.service`

## 安全机制

本项目内置了多项旨在保障系统安全的机制：

- 文件替换前进行内容比对
- 仅在文件实际变化时重启服务
- 进程锁防止并发执行冲突
- 运行前检查必要的系统依赖
- 根据系统环境自动选择定时器后端
- 在标准系统上自动安装并修复 cron 服务启动
- 在受支持的小内存 RHEL 系系统上自动降级使用 Supercronic
- 重新配置时自动对定时任务进行去重处理
- 提供专用的、清理彻底的卸载脚本
- 卸载后提示清理 shell 缓存

## 部署须知

本项目专为已经安装并正常运行 3x-ui 的服务器设计。
它不会帮您安装 3x-ui 本身。

在标准的 Linux 系统上，如果缺失 cron，安装程序会自动尝试安装并启动它。
在受支持的小内存 RHEL 系系统上，安装程序将自动切换为使用 Supercronic 而非依赖系统 cron。

## 开源声明与免责条款

本项目是一个独立的社区工具。
它未附属于以下任何实体，也未获得其背书或官方支持：

- 3x-ui
- Xray
- Supercronic
- 任何上游 Geo 规则的维护者
- 任何主机提供商或服务运营商

### 无担保声明
本软件按“原样”提供，不提供任何明示或暗示的担保，包括但不限于：适销性、特定用途的适用性、非侵权性、可用性以及运行安全性。
**使用风险由您自行承担。**

### 用户责任
使用本项目即表示您承认并同意：

- 您有责任在运行前审查相关代码
- 您有责任核实该工具在您所在司法管辖区的使用是否合法
- 您有责任确保遵守您的服务器、网络、提供商及服务条款
- 对于因使用本工具而造成的任何配置更改、服务中断或负面影响，您需承担全部责任

### 上游数据及第三方权利
本项目可能会从第三方上游源下载规则文件。
这些文件、命名规范、更新逻辑及任何相关权利均归其各自的维护者或所有者所有。
用户应自行审查他们选择启用的任何上游数据源的许可、条款及使用条件。

### 安全建议
请勿在生产系统上盲目运行来自互联网的自动化脚本。
始终建议您先审查代码，在安全的环境中进行测试，并妥善备份重要的配置和数据。

### 法律声明
本代码仓库仅用于教育、运维和管理自动化目的。
本仓库中的任何内容均不应被解释为法律建议、合规建议，或在任何国家/地区或环境中保证合法使用的承诺。
如有法律或合规方面的顾虑，请咨询具备资格的专业人士。

## 开源协议

MIT License

```text
MIT License

Copyright (c) 2026 violetaini

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 仓库目录结构

```text
.
├── install-3xui-geo-updater.sh
├── LICENSE
├── README.md
├── README_fa.md
├── README_ru.md
├── README_zh.md
└── screenshots/
    └── main-menu-preview.png
```

## 参与贡献

欢迎提交 Issue 和 Pull Request。
如果您希望为本项目做出贡献，请：

- 清晰地描述您遇到的问题
- 说明您的运行环境
- 如果适用，请附带相关日志
- 保持 PR 的修改范围专注，以便于代码审查

## 鸣谢

感谢 3x-ui 的维护团队以及各位上游 Geo 规则提供者的辛勤工作。
如果这个项目对您有帮助，欢迎给仓库点个 Star。
