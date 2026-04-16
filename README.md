# 3xui Geo Updater

[English](README.md) | [简体中文](README_zh.md) | [Русский](README_ru.md) | [فارسی](README_fa.md)

A lightweight, multilingual Geo file auto-updater for **3x-ui**, with source selection, scheduled updates, logging, and safe restart behavior.

![Main Menu Preview](screenshots/main-menu-preview.png)

This tool helps keep Geo-related rule files up to date for 3x-ui-based deployments while avoiding unnecessary restarts. It supports multiple upstream sources, flexible scheduling, a simple command-line menu, and restarts **only when files actually change**.

## Features

- Multilingual interface
  - Simplified Chinese
  - English
  - Russian
  - Persian
- First-run language selection
- Supports multiple Geo rule sources
- Supports single or multiple source selection
- Scheduled update modes
  - Daily
  - Weekly
  - Every N days
  - Custom cron expression
- Default execution time: **03:00**
- Restarts **x-ui only when files actually change**
- Logging support
- Built-in uninstall option
- Built-in swap management menu
- Shortcut commands:
  - `xgeo`
  - `3xui-geo`
- Automatic scheduler backend selection
  - Standard systems use system cron
  - Supported low-memory RHEL-like systems first check for a usable built-in system cron
  - If no usable system cron is available, the installer automatically switches to Supercronic
- Supercronic mode includes:
  - systemd service management
  - automatic startup on boot
  - automatic restart on failure

## Supported Sources

This project currently supports the following Geo rule sources:

1. **Loyalsoldier**
   - `geoip.dat`
   - `geosite.dat`

2. **chocolate4u**
   - `geoip_IR.dat`
   - `geosite_IR.dat`

3. **runetfreedom**
   - `geoip_RU.dat`
   - `geosite_RU.dat`

## How It Works

The updater downloads the latest Geo files from the configured upstream source(s), compares them against the currently installed local files, and only replaces them if the file content has changed.

If at least one selected file changes, the script restarts `x-ui` so the new Geo data can take effect.

If nothing changes, **no restart happens**.

## Why This Project Exists

3x-ui already provides a manual Geo file update option, but many users want a safer and more automated workflow.

This project adds:

- Scheduled execution
- Source selection
- Multilingual interactive management
- Logging
- Restart-on-change-only logic
- First-run language selection
- A more convenient operational experience for long-term maintenance

## Requirements

- Linux server
- `3x-ui` already installed
- Root access
- Common system tools available:
  - `bash`
  - `curl`
  - `cmp`
  - `install`
  - `awk`
  - `grep`
  - `mktemp`
  - `date`
  - `xargs`

This installer relies mostly on common Linux utilities that are usually available on standard Linux systems.

On standard systems, the installer will try to install and start cron automatically if needed.

On supported low-memory RHEL-like systems, the installer first checks whether a usable built-in system cron already exists. If it does, the native system cron will be used. Otherwise, the installer automatically switches to **Supercronic**.

## Installation

### Quick install
The installer automatically selects the scheduler backend:

- On standard systems, it uses system cron and will try to install/start it if needed
- On supported low-memory RHEL-like systems, it first checks whether a usable built-in system cron already exists
- If a usable built-in system cron is available, it will be used directly
- Otherwise, the installer automatically switches to **Supercronic**
```bash
curl -fsSL -o install-3xui-geo-updater.sh https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh && chmod +x install-3xui-geo-updater.sh && bash install-3xui-geo-updater.sh
```

### 1. Download the installer

Place the installer script on your server, for example:

```bash
curl -fsSL -o install-3xui-geo-updater.sh https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh
```

Or clone the repository:

```bash
git clone https://github.com/violetaini/3xui-geo-auto-update.git
cd 3xui-geo-auto-update
```

### 2. Make it executable

```bash
chmod +x install-3xui-geo-updater.sh
```

### 3. Run the installer as root

```bash
sudo bash install-3xui-geo-updater.sh
```

After installation, the manager menu will start automatically.

### First Run
On the first run, the script will ask you to choose a language before entering the main menu. 
After that, the selected language is saved and reused automatically.

## Usage

**Open the manager menu:**

```bash
xgeo
```

or

```bash
3xui-geo
```

**Run an update check manually:**
Open the menu and choose: `Run update check now`

**Uninstall:**

```bash
xgeo uninstall
```

You can also uninstall from the manager menu.

## Menu Overview

- Configure or modify auto update
- Run update check now
- View logs
- View current configuration
- Switch language
- Remove scheduled task
- Swap management
- Uninstall script

## Scheduling Modes

The updater supports the following scheduling modes:

- **Daily:** Runs every day at 03:00
- **Weekly:** Runs once a week at 03:00 on the selected weekday
- **Every N Days:** Runs every N days at 03:00
- **Custom Cron:** For advanced users who want full scheduling control

## Scheduler Backend

This project supports two scheduler backends:

### 1. System cron
Used on standard systems.

If cron is missing, the installer will try to install and start it automatically.

### 2. Supercronic
Used only when needed on supported low-memory RHEL-like systems.

Currently, the installer checks the following systems for low-memory scheduler fallback:

- Anolis
- CentOS Stream
- Oracle Linux
- AlmaLinux
- Rocky Linux
- Alibaba Cloud Linux

When total memory is below **2 GiB**, the installer will first check whether a usable built-in system cron already exists.

- If a usable built-in system cron is found, the installer continues to use native system cron
- If no usable built-in system cron is found, the installer automatically switches to **Supercronic**

In Supercronic mode, the installer will:

- Download the standalone Supercronic binary
- Create a dedicated crontab file
- Create a systemd service
- Enable auto-start on boot
- Enable automatic restart on failure

## Logging

Default log file:

```bash
/var/log/3xui-geo-updater.log
```

View the last 50 lines:

```bash
tail -n 50 /var/log/3xui-geo-updater.log
```

Follow logs in real time:

```bash
tail -f /var/log/3xui-geo-updater.log
```

## Installed Components

## Installed Components

The installer creates the following files:

- `/usr/local/bin/3xui-geo-runner.sh`
- `/usr/local/bin/3xui-geo-manager.sh`
- `/usr/local/bin/3xui-geo-uninstall.sh`
- `/usr/local/bin/xgeo`
- `/usr/local/bin/3xui-geo`

Configuration file:
- `/etc/3xui-geo-updater.conf`

State directory:
- `/var/lib/3xui-geo-updater`

Log file:
- `/var/log/3xui-geo-updater.log`

When Supercronic mode is enabled, the installer also creates:

- `/usr/local/bin/supercronic`
- `/etc/3xui-geo-updater.cron`
- `/etc/systemd/system/3xui-geo-supercronic.service`


## Safety Behavior

This project includes several safety-oriented behaviors:

- File content comparison before replacement
- Restart only on actual file changes
- Locking to prevent concurrent runs
- Dependency checks before execution
- Automatic scheduler backend selection based on system environment
- Automatic cron installation and startup repair on standard systems
- Automatic Supercronic fallback on supported low-memory RHEL-like systems when no usable built-in cron is available
- Scheduled task de-duplication during reconfiguration
- Dedicated uninstall script
- Shell cache reminder after uninstall

## Deployment Notes

This project is intended for servers where 3x-ui is already installed and working correctly.
It does not install 3x-ui itself.

On standard Linux systems, the installer will automatically try to install and start cron if it is missing.

On supported low-memory RHEL-like systems, the installer first checks whether a usable built-in system cron already exists.

If it does, the native system cron will be used.

If it does not, the installer will automatically switch to Supercronic.

## Open Source Notice and Disclaimer

This project is an independent community tool.
It is not affiliated with, endorsed by, or officially supported by:

- 3x-ui
- Xray
- Supercronic
- Any upstream Geo rule maintainer
- Any hosting provider or service operator

### No Warranty
This software is provided "as is", without warranty of any kind, express or implied, including but not limited to: merchantability, fitness for a particular purpose, non-infringement, availability, and operational safety.
**Use it at your own risk.**

### User Responsibility
By using this project, you acknowledge that:

- You are responsible for reviewing the code before running it
- You are responsible for verifying that its use is lawful in your jurisdiction
- You are responsible for ensuring compliance with your server, network, provider, and service terms
- You are responsible for any configuration, downtime, or service impact caused by use of this tool

### Upstream Data and Third-Party Rights
This project may download rule files from third-party upstream sources.
Those files, naming conventions, update logic, and any associated rights belong to their respective maintainers or owners.
Users should review the licenses, terms, and usage conditions of any upstream data source they choose to enable.

### Security Recommendation
Do not run automation scripts from the internet blindly on production systems.
Always review the code, test in a safe environment first, and keep backups of important configurations and data.

### Legal Notice
This repository is intended for educational, operational, and administrative automation purposes only.
Nothing in this repository should be interpreted as legal advice, compliance advice, or a guarantee of lawful use in any country or environment.
If you have legal or regulatory concerns, consult a qualified professional.

## License

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

## Repository Structure

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

## Contributing

Issues and pull requests are welcome.
If you want to contribute, please:

- describe the problem clearly
- explain your environment
- include logs if relevant
- keep changes focused and easy to review

## Acknowledgements

Thanks to the maintainers of 3x-ui and the upstream Geo rule providers for their work.
If this project helps you, feel free to star the repository.
