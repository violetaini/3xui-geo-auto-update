#!/usr/bin/env bash
set -euo pipefail

RUNNER="/usr/local/bin/3xui-geo-runner.sh"
MANAGER="/usr/local/bin/3xui-geo-manager.sh"
UNINSTALLER="/usr/local/bin/3xui-geo-uninstall.sh"
WRAPPER_SHORT="/usr/local/bin/xgeo"
WRAPPER_ALT="/usr/local/bin/3xui-geo"

CONFIG="/etc/3xui-geo-updater.conf"
LOG_FILE="/var/log/3xui-geo-updater.log"
STATE_DIR="/var/lib/3xui-geo-updater"
CRON_MARK="# 3xui-geo-updater"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "请使用 root 用户运行安装脚本。"
    exit 1
  fi
}

require_cmd() {
  local c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "缺少依赖命令: $c"
      echo "请先安装后再执行。"
      exit 1
    fi
  done
}

get_os_info() {
  local id="" like=""
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    id="${ID:-}"
    like="${ID_LIKE:-}"
  fi
  printf '%s|%s\n' "$id" "$like"
}

is_anolis_os() {
  local os_info os_id
  os_info="$(get_os_info)"
  os_id="${os_info%%|*}"
  [[ "$os_id" == "anolis" ]]
}

detect_service_manager() {
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    echo "systemd"
    return 0
  fi
  if command -v rc-service >/dev/null 2>&1; then
    echo "openrc"
    return 0
  fi
  if command -v service >/dev/null 2>&1; then
    echo "sysv"
    return 0
  fi
  echo "unknown"
}

find_cron_service_name() {
  local candidates=("cron" "crond" "cronie" "dcron")
  local s

  for s in "${candidates[@]}"; do
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
      if systemctl cat "$s" >/dev/null 2>&1 || systemctl status "$s" >/dev/null 2>&1; then
        echo "$s"
        return 0
      fi
    fi

    if command -v service >/dev/null 2>&1; then
      if service "$s" status >/dev/null 2>&1; then
        echo "$s"
        return 0
      fi
    fi

    if command -v rc-service >/dev/null 2>&1; then
      if rc-service "$s" status >/dev/null 2>&1; then
        echo "$s"
        return 0
      fi
    fi

    if [[ -x "/etc/init.d/$s" ]]; then
      echo "$s"
      return 0
    fi

    if pgrep -x "$s" >/dev/null 2>&1; then
      echo "$s"
      return 0
    fi
  done

  return 1
}

get_mem_available_kb() {
  awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0
}

get_swap_free_kb() {
  awk '/SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0
}

get_root_free_gb() {
  df -Pk / 2>/dev/null | awk 'NR==2 {printf "%.0f", $4/1024/1024}'
}

need_swap_for_pkg_install() {
  local mem_kb swap_kb
  mem_kb="$(get_mem_available_kb)"
  swap_kb="$(get_swap_free_kb)"
  [[ "${mem_kb:-0}" -lt 393216 && "${swap_kb:-0}" -eq 0 ]]
}

prompt_yes_no() {
  local prompt="$1"
  local ans=""
  read -rp "$prompt" ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

prepare_anolis_swap_like_success_case() {
  local free_gb mem_kb swap_kb swap_total
  free_gb="$(get_root_free_gb)"
  mem_kb="$(get_mem_available_kb)"
  swap_kb="$(get_swap_free_kb)"

  free_gb="${free_gb:-0}"
  mem_kb="${mem_kb:-0}"
  swap_kb="${swap_kb:-0}"

  if ! is_anolis_os; then
    return 0
  fi

  if ! need_swap_for_pkg_install; then
    return 0
  fi

  echo "检测到当前系统为 Anolis，且内存较低。"
  echo "MemAvailable: ${mem_kb} KB"
  echo "SwapFree: ${swap_kb} KB"
  echo "根分区剩余空间: ${free_gb} GB"
  echo "当前环境下，yum/dnf 安装 cronie 容易因内存不足被 OOM killer 杀掉。"

  if [[ "$free_gb" -lt 5 ]]; then
    echo "错误: 根分区剩余空间不足 5GB，不建议自动创建 swap。"
    echo "请先清理磁盘空间，或手动创建 swap 后再运行本脚本。"
    exit 1
  fi

  if ! prompt_yes_no "是否现在按成功模式创建 3G /swapfile 并继续安装？[y/N]: "; then
    echo "已取消自动创建 swap。"
    exit 1
  fi

  echo "磁盘空间足够，继续执行脚本..."

  if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "/swapfile"; then
    echo "检测到 /swapfile 已启用，跳过创建。"
  else
    if [[ -f /swapfile ]]; then
      swapoff /swapfile >/dev/null 2>&1 || true
      rm -f /swapfile
    fi

    dd if=/dev/zero of=/swapfile bs=1M count=3072 status=progress
    ls -lh /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
  fi

  if ! grep -q '^/swapfile swap swap defaults 0 0$' /etc/fstab 2>/dev/null; then
    echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
  fi

  free -h || true
  grep '^/swapfile ' /etc/fstab || true
  echo "Swap 安装成功！"

  echo "swap 校验结果："
  swapon --show || true
  free -h || true
  grep -E 'SwapTotal|SwapFree' /proc/meminfo || true

  swap_total="$(awk '/SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "${swap_total:-0}" -le 0 ]]; then
    echo "错误: swap 创建后仍未生效，已停止继续安装。"
    exit 1
  fi
}

install_cronie_rhel_like() {
  if command -v yum >/dev/null 2>&1; then
    echo "执行 yum clean all ..."
    yum clean all >/dev/null 2>&1 || true
    echo "使用 yum 安装 cronie ..."
    yum -y --setopt=install_weak_deps=False --setopt=max_parallel_downloads=1 --noplugins install cronie
    return 0
  fi

  if command -v microdnf >/dev/null 2>&1; then
    echo "使用 microdnf 安装 cronie ..."
    microdnf install -y cronie
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    echo "执行 dnf clean all ..."
    dnf clean all >/dev/null 2>&1 || true
    echo "使用 dnf 安装 cronie ..."
    dnf -y --setopt=install_weak_deps=False --setopt=max_parallel_downloads=1 --noplugins install cronie
    return 0
  fi

  echo "错误: 未找到可用的包管理器（yum / microdnf / dnf）。"
  exit 1
}

install_cron_package() {
  local os_info os_id os_like
  os_info="$(get_os_info)"
  os_id="${os_info%%|*}"
  os_like="${os_info#*|}"

  if is_anolis_os; then
    prepare_anolis_swap_like_success_case
  fi

  case "$os_id" in
    debian|ubuntu)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y cron
      return 0
      ;;
    alpine)
      apk update
      apk add dcron || apk add cronie
      return 0
      ;;
    arch|manjaro|endeavouros)
      pacman -Sy --noconfirm cronie
      return 0
      ;;
    anolis|rhel|centos|rocky|almalinux|fedora|ol)
      install_cronie_rhel_like
      return 0
      ;;
  esac

  if [[ " $os_like " == *" rhel "* || " $os_like " == *" centos "* || " $os_like " == *" fedora "* ]]; then
    install_cronie_rhel_like
    return 0
  fi

  echo "错误: 当前发行版暂未内置自动修复 cron 逻辑。"
  echo "请手动安装 cron/cronie 后再运行本脚本。"
  exit 1
}

start_and_enable_cron_service() {
  local svc="$1"
  local sm
  sm="$(detect_service_manager)"

  case "$sm" in
    systemd)
      systemctl enable "$svc" >/dev/null 2>&1 || true
      systemctl start "$svc" >/dev/null 2>&1 || true
      systemctl is-active --quiet "$svc"
      return $?
      ;;
    openrc)
      rc-update add "$svc" default >/dev/null 2>&1 || true
      rc-service "$svc" start >/dev/null 2>&1 || true
      rc-service "$svc" status >/dev/null 2>&1
      return $?
      ;;
    sysv)
      service "$svc" start >/dev/null 2>&1 || true
      service "$svc" status >/dev/null 2>&1
      return $?
      ;;
    *)
      ;;
  esac

  if [[ -x "/etc/init.d/$svc" ]]; then
    "/etc/init.d/$svc" start >/dev/null 2>&1 || true
    "/etc/init.d/$svc" status >/dev/null 2>&1
    return $?
  fi

  return 1
}

ensure_cron_ready() {
  local svc=""

  if ! command -v crontab >/dev/null 2>&1; then
    echo "未检测到 crontab，正在尝试自动安装 cron ..."
    install_cron_package
  fi

  if ! command -v crontab >/dev/null 2>&1; then
    echo "错误: 自动安装后仍未检测到 crontab。"
    exit 1
  fi

  if ! svc="$(find_cron_service_name)"; then
    echo "未检测到 cron 服务，正在尝试安装/修复 ..."
    install_cron_package
    svc="$(find_cron_service_name || true)"
  fi

  if [[ -n "$svc" ]]; then
    start_and_enable_cron_service "$svc" >/dev/null 2>&1 || true
  fi
}

ensure_xui_installed() {
  if command -v x-ui >/dev/null 2>&1; then
    return 0
  fi

  if [[ -x /usr/local/x-ui/x-ui ]]; then
    return 0
  fi

  if [[ -f /etc/systemd/system/x-ui.service || -f /lib/systemd/system/x-ui.service ]]; then
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl status x-ui >/dev/null 2>&1 || systemctl list-unit-files 2>/dev/null | grep -q '^x-ui\.service'; then
      return 0
    fi
  fi

  echo "错误: 未检测到 3x-ui / x-ui。"
  echo "本脚本仅适用于已安装并可正常使用的 3x-ui 环境。"
  exit 1
}

print_swap_notice() {
  if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "/swapfile"; then
    echo
    echo "提示：当前系统已启用 swap：/swapfile"
    echo "如后续确认不再需要，可执行："
    echo "  swapoff /swapfile"
    echo "  sed -i '\\|^/swapfile |d' /etc/fstab"
    echo "  rm -f /swapfile"
  fi
}

need_root
require_cmd bash curl cmp install awk grep mktemp date xargs
ensure_cron_ready
ensure_xui_installed

cat > "$RUNNER" <<'RUNNER_EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/3xui-geo-updater.conf"
LOG_FILE="/var/log/3xui-geo-updater.log"
BASE_DIR="/usr/local/x-ui/bin"
STATE_DIR="/var/lib/3xui-geo-updater"
STATE_FILE="$STATE_DIR/last_interval_run"
LOCK_DIR="/tmp/3xui-geo-updater.lock"

FORCE_RUN=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE_RUN=1
fi

LANGUAGE=""
SOURCES="1"
MODE="daily"
CRON_SCHEDULE="0 3 * * *"
INTERVAL_DAYS=""
WEEKDAY="1"

if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG"
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
release_lock() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}
trap 'cleanup; release_lock' EXIT

t() {
  local key="$1"
  local lang="${LANGUAGE:-zh_CN}"
  case "${lang}:${key}" in
    zh_CN:cfg_missing) echo "配置文件不存在: $CONFIG" ;;
    zh_CN:dep_missing) echo "缺少依赖命令: %s" ;;
    zh_CN:lock_busy) echo "已有任务正在运行，本次跳过" ;;
    zh_CN:force_mode) echo "本次为手动强制执行模式" ;;
    zh_CN:skip_interval) echo "当前为“每 %s 天”模式，今天未到执行日期，跳过更新" ;;
    zh_CN:current_sources) echo "本次启用的规则源: %s" ;;
    zh_CN:current_mode) echo "当前调度模式: %s" ;;
    zh_CN:check_source) echo "开始检查规则源: %s" ;;
    zh_CN:download_failed_geosite) echo "下载失败: %s 的 geosite.dat" ;;
    zh_CN:download_failed_geoip) echo "下载失败: %s 的 geoip.dat" ;;
    zh_CN:file_updated) echo "%s 已更新" ;;
    zh_CN:file_unchanged) echo "%s 无变化" ;;
    zh_CN:changes_restart) echo "检测到 Geo 文件有更新，准备重启 x-ui" ;;
    zh_CN:restarted) echo "x-ui 已重启" ;;
    zh_CN:no_change) echo "未检测到任何 Geo 文件变化，本次不重启 x-ui" ;;
    zh_CN:partial_fail) echo "本次执行存在部分下载失败，请检查网络或上游仓库状态" ;;
    zh_CN:xui_not_found) echo "未检测到 x-ui，跳过重启。请确认 3x-ui 是否已安装。" ;;
    zh_CN:restart_failed) echo "x-ui 重启失败，请手动检查服务状态。" ;;

    en_US:cfg_missing) echo "Config file not found: $CONFIG" ;;
    en_US:dep_missing) echo "Missing required command: %s" ;;
    en_US:lock_busy) echo "Another task is already running. Skipping this run" ;;
    en_US:force_mode) echo "Forced manual run mode" ;;
    en_US:skip_interval) echo "Current mode is every %s day(s); not due today, skipping update" ;;
    en_US:current_sources) echo "Enabled sources this run: %s" ;;
    en_US:current_mode) echo "Current schedule mode: %s" ;;
    en_US:check_source) echo "Checking source: %s" ;;
    en_US:download_failed_geosite) echo "Download failed: %s geosite.dat" ;;
    en_US:download_failed_geoip) echo "Download failed: %s geoip.dat" ;;
    en_US:file_updated) echo "%s updated" ;;
    en_US:file_unchanged) echo "%s unchanged" ;;
    en_US:changes_restart) echo "Geo files changed, restarting x-ui" ;;
    en_US:restarted) echo "x-ui restarted" ;;
    en_US:no_change) echo "No Geo file changes detected, x-ui will not restart" ;;
    en_US:partial_fail) echo "Some downloads failed. Please check network or upstream repositories" ;;
    en_US:xui_not_found) echo "x-ui not found. Restart skipped. Please make sure 3x-ui is installed." ;;
    en_US:restart_failed) echo "Failed to restart x-ui. Please check the service status manually." ;;

    ru_RU:cfg_missing) echo "Файл конфигурации не найден: $CONFIG" ;;
    ru_RU:dep_missing) echo "Отсутствует обязательная команда: %s" ;;
    ru_RU:lock_busy) echo "Другая задача уже выполняется. Этот запуск пропущен" ;;
    ru_RU:force_mode) echo "Принудительный ручной запуск" ;;
    ru_RU:skip_interval) echo "Режим: каждые %s дн.; сегодня запуск не требуется, обновление пропущено" ;;
    ru_RU:current_sources) echo "Выбранные источники в этом запуске: %s" ;;
    ru_RU:current_mode) echo "Текущий режим расписания: %s" ;;
    ru_RU:check_source) echo "Проверка источника: %s" ;;
    ru_RU:download_failed_geosite) echo "Не удалось скачать geosite.dat для %s" ;;
    ru_RU:download_failed_geoip) echo "Не удалось скачать geoip.dat для %s" ;;
    ru_RU:file_updated) echo "%s обновлён" ;;
    ru_RU:file_unchanged) echo "%s без изменений" ;;
    ru_RU:changes_restart) echo "Обнаружены изменения Geo-файлов, выполняется перезапуск x-ui" ;;
    ru_RU:restarted) echo "x-ui перезапущен" ;;
    ru_RU:no_change) echo "Изменений Geo-файлов нет, x-ui не будет перезапущен" ;;
    ru_RU:partial_fail) echo "Некоторые загрузки завершились неудачно. Проверьте сеть или состояние репозиториев" ;;
    ru_RU:xui_not_found) echo "x-ui не найден. Перезапуск пропущен. Убедитесь, что 3x-ui установлен." ;;
    ru_RU:restart_failed) echo "Не удалось перезапустить x-ui. Проверьте состояние службы вручную." ;;

    fa_IR:cfg_missing) echo "فایل پیکربندی پیدا نشد: $CONFIG" ;;
    fa_IR:dep_missing) echo "دستور موردنیاز پیدا نشد: %s" ;;
    fa_IR:lock_busy) echo "یک فرایند دیگر در حال اجراست؛ این اجرا رد شد" ;;
    fa_IR:force_mode) echo "اجرای اجباری دستی فعال است" ;;
    fa_IR:skip_interval) echo "حالت فعلی هر %s روز یک‌بار است؛ امروز زمان اجرا نیست، بروزرسانی رد شد" ;;
    fa_IR:current_sources) echo "منابع فعال در این اجرا: %s" ;;
    fa_IR:current_mode) echo "حالت زمان‌بندی فعلی: %s" ;;
    fa_IR:check_source) echo "در حال بررسی منبع: %s" ;;
    fa_IR:download_failed_geosite) echo "دانلود geosite.dat برای %s ناموفق بود" ;;
    fa_IR:download_failed_geoip) echo "دانلود geoip.dat برای %s ناموفق بود" ;;
    fa_IR:file_updated) echo "%s بروزرسانی شد" ;;
    fa_IR:file_unchanged) echo "%s بدون تغییر است" ;;
    fa_IR:changes_restart) echo "تغییر در فایل‌های Geo شناسایی شد؛ x-ui در حال راه‌اندازی مجدد است" ;;
    fa_IR:restarted) echo "x-ui مجدداً راه‌اندازی شد" ;;
    fa_IR:no_change) echo "هیچ تغییری در فایل‌های Geo یافت نشد؛ x-ui ریستارت نمی‌شود" ;;
    fa_IR:partial_fail) echo "برخی دانلودها ناموفق بودند. شبکه یا مخازن بالادستی را بررسی کنید" ;;
    fa_IR:xui_not_found) echo "x-ui پیدا نشد؛ راه‌اندازی مجدد رد شد. لطفاً مطمئن شوید 3x-ui نصب است." ;;
    fa_IR:restart_failed) echo "راه‌اندازی مجدد x-ui ناموفق بود. لطفاً وضعیت سرویس را دستی بررسی کنید." ;;

    *) echo "$key" ;;
  esac
}

log() {
  local msg="$1"
  printf '[%s] %s\n' "$(date '+%F %T')" "$msg" | tee -a "$LOG_FILE"
}

require_cmd() {
  local c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "$(printf "$(t dep_missing)" "$c")"
      exit 1
    fi
  done
}

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "$(t lock_busy)"
    exit 0
  fi
}

download_file() {
  local url="$1"
  local out="$2"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 -o "$out" "$url"
}

file_changed() {
  local new_file="$1"
  local old_file="$2"

  if [[ ! -f "$old_file" ]]; then
    return 0
  fi

  if ! cmp -s "$new_file" "$old_file"; then
    return 0
  fi

  return 1
}

restart_xui() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl status x-ui >/dev/null 2>&1 || systemctl list-unit-files 2>/dev/null | grep -q '^x-ui\.service'; then
      systemctl restart x-ui
      return $?
    fi
  fi

  if command -v x-ui >/dev/null 2>&1; then
    x-ui restart
    return $?
  fi

  if [[ -x /usr/local/x-ui/x-ui ]]; then
    /usr/local/x-ui/x-ui restart
    return $?
  fi

  log "$(t xui_not_found)"
  return 1
}

should_run_now() {
  if [[ "$FORCE_RUN" -eq 1 ]]; then
    return 0
  fi

  if [[ "${MODE:-daily}" != "interval" ]]; then
    return 0
  fi

  local days="${INTERVAL_DAYS:-1}"
  mkdir -p "$STATE_DIR"

  if [[ ! -f "$STATE_FILE" ]]; then
    return 0
  fi

  local last_ts now_ts diff_days
  last_ts="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"
  now_ts="$(date +%s)"
  diff_days=$(( (now_ts - last_ts) / 86400 ))

  [[ "$diff_days" -ge "$days" ]]
}

mark_interval_run() {
  if [[ "${MODE:-daily}" == "interval" && "$FORCE_RUN" -eq 0 ]]; then
    mkdir -p "$STATE_DIR"
    date +%s > "$STATE_FILE"
  fi
}

CURRENT_SOURCE_CHANGED=0

update_source() {
  local source_name="$1"
  local repo="$2"
  local local_geosite="$3"
  local local_geoip="$4"

  local tmp_geosite="$TMP_DIR/$local_geosite"
  local tmp_geoip="$TMP_DIR/$local_geoip"
  local dst_geosite="$BASE_DIR/$local_geosite"
  local dst_geoip="$BASE_DIR/$local_geoip"

  CURRENT_SOURCE_CHANGED=0

  log "$(printf "$(t check_source)" "$source_name")"

  if ! download_file "https://github.com/${repo}/releases/latest/download/geosite.dat" "$tmp_geosite"; then
    log "$(printf "$(t download_failed_geosite)" "$source_name")"
    return 1
  fi

  if ! download_file "https://github.com/${repo}/releases/latest/download/geoip.dat" "$tmp_geoip"; then
    log "$(printf "$(t download_failed_geoip)" "$source_name")"
    return 1
  fi

  if file_changed "$tmp_geosite" "$dst_geosite"; then
    install -m 0644 "$tmp_geosite" "$dst_geosite"
    log "$(printf "$(t file_updated)" "$local_geosite")"
    CURRENT_SOURCE_CHANGED=1
  else
    log "$(printf "$(t file_unchanged)" "$local_geosite")"
  fi

  if file_changed "$tmp_geoip" "$dst_geoip"; then
    install -m 0644 "$tmp_geoip" "$dst_geoip"
    log "$(printf "$(t file_updated)" "$local_geoip")"
    CURRENT_SOURCE_CHANGED=1
  else
    log "$(printf "$(t file_unchanged)" "$local_geoip")"
  fi

  return 0
}

main() {
  require_cmd curl cmp install grep awk xargs date mktemp
  acquire_lock

  mkdir -p "$BASE_DIR"
  mkdir -p "$STATE_DIR"
  touch "$LOG_FILE"

  if [[ ! -f "$CONFIG" ]]; then
    echo "$(t cfg_missing)"
    exit 1
  fi

  if [[ "$FORCE_RUN" -eq 1 ]]; then
    log "$(t force_mode)"
  fi

  if ! should_run_now; then
    log "$(printf "$(t skip_interval)" "${INTERVAL_DAYS:-1}")"
    exit 0
  fi

  local changed_any=0
  local failed_any=0

  IFS=',' read -r -a selected_sources <<< "${SOURCES:-1}"

  log "$(printf "$(t current_sources)" "${SOURCES:-1}")"
  log "$(printf "$(t current_mode)" "${MODE:-daily}")"

  for src in "${selected_sources[@]}"; do
    src="$(echo "$src" | xargs)"

    case "$src" in
      1)
        if update_source \
          "Loyalsoldier" \
          "Loyalsoldier/v2ray-rules-dat" \
          "geosite.dat" \
          "geoip.dat"
        then
          [[ "$CURRENT_SOURCE_CHANGED" -eq 1 ]] && changed_any=1
        else
          failed_any=1
        fi
        ;;
      2)
        if update_source \
          "chocolate4u" \
          "chocolate4u/Iran-v2ray-rules" \
          "geosite_IR.dat" \
          "geoip_IR.dat"
        then
          [[ "$CURRENT_SOURCE_CHANGED" -eq 1 ]] && changed_any=1
        else
          failed_any=1
        fi
        ;;
      3)
        if update_source \
          "runetfreedom" \
          "runetfreedom/russia-v2ray-rules-dat" \
          "geosite_RU.dat" \
          "geoip_RU.dat"
        then
          [[ "$CURRENT_SOURCE_CHANGED" -eq 1 ]] && changed_any=1
        else
          failed_any=1
        fi
        ;;
      *)
        ;;
    esac
  done

  if [[ "$changed_any" -eq 1 ]]; then
    log "$(t changes_restart)"
    if restart_xui; then
      log "$(t restarted)"
    else
      log "$(t restart_failed)"
    fi
  else
    log "$(t no_change)"
  fi

  if [[ "$failed_any" -eq 0 ]]; then
    mark_interval_run
  else
    log "$(t partial_fail)"
    exit 1
  fi
}

main "$@"
RUNNER_EOF

cat > "$UNINSTALLER" <<'UNINSTALLER_EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/3xui-geo-updater.conf"
RUNNER="/usr/local/bin/3xui-geo-runner.sh"
MANAGER="/usr/local/bin/3xui-geo-manager.sh"
UNINSTALLER="/usr/local/bin/3xui-geo-uninstall.sh"
WRAPPER_SHORT="/usr/local/bin/xgeo"
WRAPPER_ALT="/usr/local/bin/3xui-geo"
LOG_FILE="/var/log/3xui-geo-updater.log"
STATE_DIR="/var/lib/3xui-geo-updater"
CRON_MARK="# 3xui-geo-updater"

LANGUAGE=""
if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG"
fi

t() {
  local key="$1"
  local lang="${LANGUAGE:-zh_CN}"
  case "${lang}:${key}" in
    zh_CN:need_root) echo "请使用 root 用户运行。" ;;
    zh_CN:dep_missing) echo "缺少依赖命令: %s" ;;
    zh_CN:confirm) echo "确认卸载 3xui Geo 自动更新脚本吗？[y/N]:" ;;
    zh_CN:cancel) echo "已取消卸载。" ;;
    zh_CN:done) echo "卸载完成。" ;;
    zh_CN:hash_tip) echo "当前 shell 可能仍缓存旧命令路径。若继续输入 xgeo 报错，请执行: hash -r，或重新打开终端。" ;;

    en_US:need_root) echo "Please run as root." ;;
    en_US:dep_missing) echo "Missing required command: %s" ;;
    en_US:confirm) echo "Are you sure you want to uninstall 3xui Geo updater? [y/N]:" ;;
    en_US:cancel) echo "Uninstall cancelled." ;;
    en_US:done) echo "Uninstall completed." ;;
    en_US:hash_tip) echo "Your current shell may still cache the old command path. If xgeo still errors, run: hash -r, or reopen the terminal." ;;

    ru_RU:need_root) echo "Пожалуйста, запустите от root." ;;
    ru_RU:dep_missing) echo "Отсутствует обязательная команда: %s" ;;
    ru_RU:confirm) echo "Вы уверены, что хотите удалить 3xui Geo updater? [y/N]:" ;;
    ru_RU:cancel) echo "Удаление отменено." ;;
    ru_RU:done) echo "Удаление завершено." ;;
    ru_RU:hash_tip) echo "Текущая оболочка может кэшировать старый путь команды. Если xgeo всё ещё вызывает ошибку, выполните: hash -r, либо откройте новый терминал." ;;

    fa_IR:need_root) echo "لطفاً با کاربر root اجرا کنید." ;;
    fa_IR:dep_missing) echo "دستور موردنیاز پیدا نشد: %s" ;;
    fa_IR:confirm) echo "آیا مطمئن هستید که می‌خواهید اسکریپت بروزرسانی Geo را حذف کنید؟ [y/N]:" ;;
    fa_IR:cancel) echo "حذف لغو شد." ;;
    fa_IR:done) echo "حذف کامل شد." ;;
    fa_IR:hash_tip) echo "ممکن است شل فعلی هنوز مسیر قدیمی دستور را در حافظه داشته باشد. اگر xgeo هنوز خطا داد، دستور hash -r را اجرا کنید یا ترمینال را دوباره باز کنید." ;;

    *) echo "$key" ;;
  esac
}

require_cmd() {
  local c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "$(printf "$(t dep_missing)" "$c")"
      exit 1
    fi
  done
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "$(t need_root)"
  exit 1
fi

require_cmd grep awk

read -rp "$(t confirm) " ans
case "$ans" in
  y|Y|yes|YES)
    ;;
  *)
    echo "$(t cancel)"
    exit 0
    ;;
esac

if command -v crontab >/dev/null 2>&1; then
  current="$(crontab -l 2>/dev/null || true)"
  printf '%s\n' "$current" \
    | grep -Fv "$CRON_MARK" \
    | grep -Fv "/usr/local/bin/3xui-geo-runner.sh" \
    | awk 'NF' \
    | crontab -
fi

rm -f "$RUNNER" "$MANAGER" "$UNINSTALLER" "$WRAPPER_SHORT" "$WRAPPER_ALT"
rm -f "$CONFIG" "$LOG_FILE"
rm -rf "$STATE_DIR"

echo "$(t done)"
echo "$(t hash_tip)"
UNINSTALLER_EOF

cat > "$MANAGER" <<'MANAGER_EOF'
#!/usr/bin/env bash
set -euo pipefail

RUNNER="/usr/local/bin/3xui-geo-runner.sh"
UNINSTALLER="/usr/local/bin/3xui-geo-uninstall.sh"
CONFIG="/etc/3xui-geo-updater.conf"
LOG_FILE="/var/log/3xui-geo-updater.log"
CRON_MARK="# 3xui-geo-updater"

LANGUAGE=""
SOURCES="1"
MODE="daily"
CRON_SCHEDULE="0 3 * * *"
INTERVAL_DAYS=""
WEEKDAY="1"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root."
    exit 1
  fi
}

require_cmd() {
  local c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "$(printf "$(t dep_missing)" "$c")"
      exit 1
    fi
  done
}

detect_service_manager() {
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    echo "systemd"
    return 0
  fi
  if command -v rc-service >/dev/null 2>&1; then
    echo "openrc"
    return 0
  fi
  if command -v service >/dev/null 2>&1; then
    echo "sysv"
    return 0
  fi
  echo "unknown"
}

find_cron_service_name() {
  local candidates=("cron" "crond" "cronie" "dcron")
  local s

  for s in "${candidates[@]}"; do
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
      if systemctl cat "$s" >/dev/null 2>&1 || systemctl status "$s" >/dev/null 2>&1; then
        echo "$s"
        return 0
      fi
    fi

    if command -v service >/dev/null 2>&1; then
      if service "$s" status >/dev/null 2>&1; then
        echo "$s"
        return 0
      fi
    fi

    if command -v rc-service >/dev/null 2>&1; then
      if rc-service "$s" status >/dev/null 2>&1; then
        echo "$s"
        return 0
      fi
    fi

    if [[ -x "/etc/init.d/$s" ]]; then
      echo "$s"
      return 0
    fi

    if pgrep -x "$s" >/dev/null 2>&1; then
      echo "$s"
      return 0
    fi
  done

  return 1
}

start_and_enable_cron_service() {
  local svc="$1"
  local sm
  sm="$(detect_service_manager)"

  case "$sm" in
    systemd)
      systemctl enable "$svc" >/dev/null 2>&1 || true
      systemctl start "$svc" >/dev/null 2>&1 || true
      systemctl is-active --quiet "$svc"
      return $?
      ;;
    openrc)
      rc-update add "$svc" default >/dev/null 2>&1 || true
      rc-service "$svc" start >/dev/null 2>&1 || true
      rc-service "$svc" status >/dev/null 2>&1
      return $?
      ;;
    sysv)
      service "$svc" start >/dev/null 2>&1 || true
      service "$svc" status >/dev/null 2>&1
      return $?
      ;;
    *)
      ;;
  esac

  if [[ -x "/etc/init.d/$svc" ]]; then
    "/etc/init.d/$svc" start >/dev/null 2>&1 || true
    "/etc/init.d/$svc" status >/dev/null 2>&1
    return $?
  fi

  return 1
}

load_config() {
  LANGUAGE=""
  SOURCES="1"
  MODE="daily"
  CRON_SCHEDULE="0 3 * * *"
  INTERVAL_DAYS=""
  WEEKDAY="1"

  if [[ -f "$CONFIG" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG"
  fi
}

save_config() {
  cat > "$CONFIG" <<EOF2
LANGUAGE="$LANGUAGE"
SOURCES="$SOURCES"
MODE="$MODE"
CRON_SCHEDULE="$CRON_SCHEDULE"
INTERVAL_DAYS="$INTERVAL_DAYS"
WEEKDAY="$WEEKDAY"
EOF2
}

bootstrap_choose_language() {
  local choice

  while true; do
    echo
    echo "========== Language / 语言 / Язык / زبان =========="
    echo "首次运行，请先选择语言："
    echo "1. 简体中文"
    echo "2. English"
    echo "3. Русский"
    echo "4. فارسی"
    echo
    read -rp "请选择 / Please choose / Выберите / انتخاب کنید: " choice

    case "$choice" in
      1) LANGUAGE="zh_CN"; break ;;
      2) LANGUAGE="en_US"; break ;;
      3) LANGUAGE="ru_RU"; break ;;
      4) LANGUAGE="fa_IR"; break ;;
      *) echo "输入无效 / Invalid input / Неверный ввод / ورودی نامعتبر" ;;
    esac
  done

  save_config
}

ensure_initial_language() {
  if [[ -z "${LANGUAGE:-}" ]]; then
    bootstrap_choose_language
  fi
}

t() {
  local key="$1"
  local lang="${LANGUAGE:-zh_CN}"
  case "${lang}:${key}" in
    zh_CN:dep_missing) echo "缺少依赖命令: %s" ;;
    zh_CN:main_title) echo "3xui Geo 自动更新管理" ;;
    zh_CN:menu_config) echo "配置或修改自动更新" ;;
    zh_CN:menu_run) echo "立即执行一次更新检查" ;;
    zh_CN:menu_logs) echo "查看日志" ;;
    zh_CN:menu_show_config) echo "查看当前配置" ;;
    zh_CN:menu_language) echo "切换语言" ;;
    zh_CN:menu_remove_task) echo "删除自动更新任务" ;;
    zh_CN:menu_uninstall) echo "一键卸载脚本" ;;
    zh_CN:menu_exit) echo "退出" ;;
    zh_CN:prompt_choice) echo "请输入选项" ;;
    zh_CN:invalid_input) echo "输入无效。" ;;
    zh_CN:current_config) echo "当前配置" ;;
    zh_CN:enabled_sources) echo "已启用规则源" ;;
    zh_CN:schedule_mode) echo "调度模式" ;;
    zh_CN:cron_actual) echo "实际 cron" ;;
    zh_CN:current_cron) echo "当前定时任务" ;;
    zh_CN:log_file) echo "日志文件" ;;
    zh_CN:not_set) echo "未设置" ;;
    zh_CN:current_language) echo "当前语言" ;;
    zh_CN:mode_daily) echo "每天 03:00" ;;
    zh_CN:mode_weekly) echo "每周 %s 03:00" ;;
    zh_CN:mode_interval) echo "每 %s 天 03:00" ;;
    zh_CN:mode_custom) echo "自定义 cron" ;;
    zh_CN:logs_title) echo "日志查看" ;;
    zh_CN:logs_50) echo "查看最后 50 行" ;;
    zh_CN:logs_100) echo "查看最后 100 行" ;;
    zh_CN:logs_follow) echo "实时追踪日志" ;;
    zh_CN:back) echo "返回上一级" ;;
    zh_CN:source_title) echo "选择自动更新的规则源" ;;
    zh_CN:source_list_intro) echo "可选规则源如下：" ;;
    zh_CN:source1_name) echo "Loyalsoldier" ;;
    zh_CN:source1_file) echo "对应文件: geoip.dat + geosite.dat" ;;
    zh_CN:source1_desc) echo "说明: 最基础、最常用的一套，普通使用通常选这个" ;;
    zh_CN:source2_name) echo "chocolate4u" ;;
    zh_CN:source2_file) echo "对应文件: geoip_IR.dat + geosite_IR.dat" ;;
    zh_CN:source2_desc) echo "说明: 偏伊朗地区相关规则" ;;
    zh_CN:source3_name) echo "runetfreedom" ;;
    zh_CN:source3_file) echo "对应文件: geoip_RU.dat + geosite_RU.dat" ;;
    zh_CN:source3_desc) echo "说明: 偏俄罗斯地区相关规则" ;;
    zh_CN:source4_name) echo "全选" ;;
    zh_CN:source4_desc) echo "等同于: 1,2,3" ;;
    zh_CN:source_help1) echo "只更新基础规则，输入: 1" ;;
    zh_CN:source_help2) echo "同时更新多个规则源，输入: 1,3" ;;
    zh_CN:source_help3) echo "更新全部规则源，输入: 4" ;;
    zh_CN:source_help4) echo "多个编号之间请使用英文逗号" ;;
    zh_CN:source_help5) echo "输入中的空格会被自动忽略" ;;
    zh_CN:source_prompt) echo "请输入要启用的规则源编号" ;;
    zh_CN:source_invalid) echo "输入格式不正确。正确示例: 1 / 1,3 / 4" ;;
    zh_CN:schedule_title) echo "设置自动更新频率" ;;
    zh_CN:schedule_daily) echo "每天" ;;
    zh_CN:schedule_daily_desc) echo "默认执行时间: 03:00" ;;
    zh_CN:schedule_weekly) echo "每周" ;;
    zh_CN:schedule_weekly_desc1) echo "默认执行时间: 03:00" ;;
    zh_CN:schedule_weekly_desc2) echo "默认星期: 周一" ;;
    zh_CN:schedule_interval) echo "每 N 天" ;;
    zh_CN:schedule_interval_desc) echo "默认执行时间: 03:00" ;;
    zh_CN:schedule_custom) echo "自定义 cron 表达式" ;;
    zh_CN:schedule_prompt) echo "请选择更新频率" ;;
    zh_CN:weekday_title) echo "请选择每周的执行日" ;;
    zh_CN:weekday_prompt) echo "请输入编号（默认 1，即周一）" ;;
    zh_CN:interval_prompt) echo "请输入 N（例如 3 表示每 3 天执行一次）" ;;
    zh_CN:interval_invalid) echo "请输入大于等于 1 的整数。" ;;
    zh_CN:cron_help_title) echo "cron 格式说明" ;;
    zh_CN:cron_help_format) echo "分 时 日 月 周" ;;
    zh_CN:cron_help_examples) echo "示例: 0 3 * * * 表示每天 03:00；0 3 * * 1 表示每周一 03:00" ;;
    zh_CN:cron_prompt) echo "请输入 5 段 cron 表达式" ;;
    zh_CN:cron_invalid) echo "cron 表达式格式不正确。" ;;
    zh_CN:saved) echo "配置已保存" ;;
    zh_CN:run_now_prompt) echo "是否立即执行一次更新检查？[y/N]" ;;
    zh_CN:run_skipped) echo "已跳过立即执行。" ;;
    zh_CN:language_title) echo "切换语言" ;;
    zh_CN:language_prompt) echo "请选择语言" ;;
    zh_CN:language_saved) echo "语言已保存。" ;;
    zh_CN:remove_task_done) echo "自动更新任务已删除。" ;;
    zh_CN:weekday_mon) echo "周一" ;;
    zh_CN:weekday_tue) echo "周二" ;;
    zh_CN:weekday_wed) echo "周三" ;;
    zh_CN:weekday_thu) echo "周四" ;;
    zh_CN:weekday_fri) echo "周五" ;;
    zh_CN:weekday_sat) echo "周六" ;;
    zh_CN:weekday_sun) echo "周日" ;;
    zh_CN:lang_zh) echo "简体中文" ;;
    zh_CN:lang_en) echo "English" ;;
    zh_CN:lang_ru) echo "Русский" ;;
    zh_CN:lang_fa) echo "فارسی" ;;

    en_US:dep_missing) echo "Missing required command: %s" ;;
    en_US:main_title) echo "3xui Geo Auto Update Manager" ;;
    en_US:menu_config) echo "Configure or modify auto update" ;;
    en_US:menu_run) echo "Run update check now" ;;
    en_US:menu_logs) echo "View logs" ;;
    en_US:menu_show_config) echo "View current config" ;;
    en_US:menu_language) echo "Switch language" ;;
    en_US:menu_remove_task) echo "Remove scheduled task" ;;
    en_US:menu_uninstall) echo "One-click uninstall" ;;
    en_US:menu_exit) echo "Exit" ;;
    en_US:prompt_choice) echo "Enter your choice" ;;
    en_US:invalid_input) echo "Invalid input." ;;
    en_US:current_config) echo "Current config" ;;
    en_US:enabled_sources) echo "Enabled sources" ;;
    en_US:schedule_mode) echo "Schedule mode" ;;
    en_US:cron_actual) echo "Actual cron" ;;
    en_US:current_cron) echo "Current cron task" ;;
    en_US:log_file) echo "Log file" ;;
    en_US:not_set) echo "Not set" ;;
    en_US:current_language) echo "Current language" ;;
    en_US:mode_daily) echo "Every day at 03:00" ;;
    en_US:mode_weekly) echo "Every %s at 03:00" ;;
    en_US:mode_interval) echo "Every %s day(s) at 03:00" ;;
    en_US:mode_custom) echo "Custom cron" ;;
    en_US:logs_title) echo "Log viewer" ;;
    en_US:logs_50) echo "View last 50 lines" ;;
    en_US:logs_100) echo "View last 100 lines" ;;
    en_US:logs_follow) echo "Follow log in real time" ;;
    en_US:back) echo "Back" ;;
    en_US:source_title) echo "Select sources for auto update" ;;
    en_US:source_list_intro) echo "Available sources:" ;;
    en_US:source1_name) echo "Loyalsoldier" ;;
    en_US:source1_file) echo "Files: geoip.dat + geosite.dat" ;;
    en_US:source1_desc) echo "Note: the most basic and common option for most users" ;;
    en_US:source2_name) echo "chocolate4u" ;;
    en_US:source2_file) echo "Files: geoip_IR.dat + geosite_IR.dat" ;;
    en_US:source2_desc) echo "Note: Iran-related rules" ;;
    en_US:source3_name) echo "runetfreedom" ;;
    en_US:source3_file) echo "Files: geoip_RU.dat + geosite_RU.dat" ;;
    en_US:source3_desc) echo "Note: Russia-related rules" ;;
    en_US:source4_name) echo "Select all" ;;
    en_US:source4_desc) echo "Equivalent to: 1,2,3" ;;
    en_US:source_help1) echo "Only basic rules: 1" ;;
    en_US:source_help2) echo "Multiple sources: 1,3" ;;
    en_US:source_help3) echo "All sources: 4" ;;
    en_US:source_help4) echo "Use English commas between numbers" ;;
    en_US:source_help5) echo "Spaces will be ignored automatically" ;;
    en_US:source_prompt) echo "Enter source numbers to enable" ;;
    en_US:source_invalid) echo "Invalid format. Examples: 1 / 1,3 / 4" ;;
    en_US:schedule_title) echo "Set auto update frequency" ;;
    en_US:schedule_daily) echo "Daily" ;;
    en_US:schedule_daily_desc) echo "Default time: 03:00" ;;
    en_US:schedule_weekly) echo "Weekly" ;;
    en_US:schedule_weekly_desc1) echo "Default time: 03:00" ;;
    en_US:schedule_weekly_desc2) echo "Default weekday: Monday" ;;
    en_US:schedule_interval) echo "Every N days" ;;
    en_US:schedule_interval_desc) echo "Default time: 03:00" ;;
    en_US:schedule_custom) echo "Custom cron expression" ;;
    en_US:schedule_prompt) echo "Choose update frequency" ;;
    en_US:weekday_title) echo "Choose weekday" ;;
    en_US:weekday_prompt) echo "Enter number (default 1 = Monday)" ;;
    en_US:interval_prompt) echo "Enter N (for example 3 means every 3 days)" ;;
    en_US:interval_invalid) echo "Please enter an integer greater than or equal to 1." ;;
    en_US:cron_help_title) echo "Cron format" ;;
    en_US:cron_help_format) echo "min hour day month weekday" ;;
    en_US:cron_help_examples) echo "Examples: 0 3 * * * = every day at 03:00; 0 3 * * 1 = every Monday at 03:00" ;;
    en_US:cron_prompt) echo "Enter 5-part cron expression" ;;
    en_US:cron_invalid) echo "Invalid cron expression." ;;
    en_US:saved) echo "Configuration saved" ;;
    en_US:run_now_prompt) echo "Run update check now? [y/N]" ;;
    en_US:run_skipped) echo "Skipped immediate run." ;;
    en_US:language_title) echo "Switch language" ;;
    en_US:language_prompt) echo "Choose language" ;;
    en_US:language_saved) echo "Language saved." ;;
    en_US:remove_task_done) echo "Scheduled task removed." ;;
    en_US:weekday_mon) echo "Monday" ;;
    en_US:weekday_tue) echo "Tuesday" ;;
    en_US:weekday_wed) echo "Wednesday" ;;
    en_US:weekday_thu) echo "Thursday" ;;
    en_US:weekday_fri) echo "Friday" ;;
    en_US:weekday_sat) echo "Saturday" ;;
    en_US:weekday_sun) echo "Sunday" ;;
    en_US:lang_zh) echo "简体中文" ;;
    en_US:lang_en) echo "English" ;;
    en_US:lang_ru) echo "Русский" ;;
    en_US:lang_fa) echo "فارسی" ;;

    ru_RU:dep_missing) echo "Отсутствует обязательная команда: %s" ;;
    ru_RU:main_title) echo "Менеджер автообновления 3xui Geo" ;;
    ru_RU:menu_config) echo "Настроить или изменить автообновление" ;;
    ru_RU:menu_run) echo "Запустить проверку обновлений сейчас" ;;
    ru_RU:menu_logs) echo "Просмотр логов" ;;
    ru_RU:menu_show_config) echo "Показать текущую конфигурацию" ;;
    ru_RU:menu_language) echo "Сменить язык" ;;
    ru_RU:menu_remove_task) echo "Удалить задачу автообновления" ;;
    ru_RU:menu_uninstall) echo "Удалить скрипт" ;;
    ru_RU:menu_exit) echo "Выход" ;;
    ru_RU:prompt_choice) echo "Введите номер пункта" ;;
    ru_RU:invalid_input) echo "Неверный ввод." ;;
    ru_RU:current_config) echo "Текущая конфигурация" ;;
    ru_RU:enabled_sources) echo "Включённые источники" ;;
    ru_RU:schedule_mode) echo "Режим расписания" ;;
    ru_RU:cron_actual) echo "Фактический cron" ;;
    ru_RU:current_cron) echo "Текущая cron-задача" ;;
    ru_RU:log_file) echo "Файл логов" ;;
    ru_RU:not_set) echo "Не задано" ;;
    ru_RU:current_language) echo "Текущий язык" ;;
    ru_RU:mode_daily) echo "Каждый день в 03:00" ;;
    ru_RU:mode_weekly) echo "Каждую %s в 03:00" ;;
    ru_RU:mode_interval) echo "Каждые %s дн. в 03:00" ;;
    ru_RU:mode_custom) echo "Пользовательский cron" ;;
    ru_RU:logs_title) echo "Просмотр логов" ;;
    ru_RU:logs_50) echo "Показать последние 50 строк" ;;
    ru_RU:logs_100) echo "Показать последние 100 строк" ;;
    ru_RU:logs_follow) echo "Отслеживать лог в реальном времени" ;;
    ru_RU:back) echo "Назад" ;;
    ru_RU:source_title) echo "Выбор источников для автообновления" ;;
    ru_RU:source_list_intro) echo "Доступные источники:" ;;
    ru_RU:source1_name) echo "Loyalsoldier" ;;
    ru_RU:source1_file) echo "Файлы: geoip.dat + geosite.dat" ;;
    ru_RU:source1_desc) echo "Примечание: базовый и самый популярный вариант" ;;
    ru_RU:source2_name) echo "chocolate4u" ;;
    ru_RU:source2_file) echo "Файлы: geoip_IR.dat + geosite_IR.dat" ;;
    ru_RU:source2_desc) echo "Примечание: правила, связанные с Ираном" ;;
    ru_RU:source3_name) echo "runetfreedom" ;;
    ru_RU:source3_file) echo "Файлы: geoip_RU.dat + geosite_RU.dat" ;;
    ru_RU:source3_desc) echo "Примечание: правила, связанные с Россией" ;;
    ru_RU:source4_name) echo "Выбрать все" ;;
    ru_RU:source4_desc) echo "Эквивалентно: 1,2,3" ;;
    ru_RU:source_help1) echo "Только базовые правила: 1" ;;
    ru_RU:source_help2) echo "Несколько источников: 1,3" ;;
    ru_RU:source_help3) echo "Все источники: 4" ;;
    ru_RU:source_help4) echo "Используйте английские запятые между числами" ;;
    ru_RU:source_help5) echo "Пробелы будут автоматически удалены" ;;
    ru_RU:source_prompt) echo "Введите номера источников для включения" ;;
    ru_RU:source_invalid) echo "Неверный формат. Примеры: 1 / 1,3 / 4" ;;
    ru_RU:schedule_title) echo "Настройка частоты автообновления" ;;
    ru_RU:schedule_daily) echo "Каждый день" ;;
    ru_RU:schedule_daily_desc) echo "Время по умолчанию: 03:00" ;;
    ru_RU:schedule_weekly) echo "Каждую неделю" ;;
    ru_RU:schedule_weekly_desc1) echo "Время по умолчанию: 03:00" ;;
    ru_RU:schedule_weekly_desc2) echo "День по умолчанию: понедельник" ;;
    ru_RU:schedule_interval) echo "Каждые N дней" ;;
    ru_RU:schedule_interval_desc) echo "Время по умолчанию: 03:00" ;;
    ru_RU:schedule_custom) echo "Пользовательское cron-выражение" ;;
    ru_RU:schedule_prompt) echo "Выберите частоту обновления" ;;
    ru_RU:weekday_title) echo "Выберите день недели" ;;
    ru_RU:weekday_prompt) echo "Введите номер (по умолчанию 1 = понедельник)" ;;
    ru_RU:interval_prompt) echo "Введите N (например, 3 = каждые 3 дня)" ;;
    ru_RU:interval_invalid) echo "Введите целое число больше или равное 1." ;;
    ru_RU:cron_help_title) echo "Формат cron" ;;
    ru_RU:cron_help_format) echo "мин час день месяц день_недели" ;;
    ru_RU:cron_help_examples) echo "Примеры: 0 3 * * * = каждый день в 03:00; 0 3 * * 1 = каждый понедельник в 03:00" ;;
    ru_RU:cron_prompt) echo "Введите cron-выражение из 5 частей" ;;
    ru_RU:cron_invalid) echo "Неверное cron-выражение." ;;
    ru_RU:saved) echo "Конфигурация сохранена" ;;
    ru_RU:run_now_prompt) echo "Запустить проверку обновлений сейчас? [y/N]" ;;
    ru_RU:run_skipped) echo "Немедленный запуск пропущен." ;;
    ru_RU:language_title) echo "Смена языка" ;;
    ru_RU:language_prompt) echo "Выберите язык" ;;
    ru_RU:language_saved) echo "Язык сохранён." ;;
    ru_RU:remove_task_done) echo "Задача автообновления удалена." ;;
    ru_RU:weekday_mon) echo "понедельник" ;;
    ru_RU:weekday_tue) echo "вторник" ;;
    ru_RU:weekday_wed) echo "среду" ;;
    ru_RU:weekday_thu) echo "четверг" ;;
    ru_RU:weekday_fri) echo "пятницу" ;;
    ru_RU:weekday_sat) echo "субботу" ;;
    ru_RU:weekday_sun) echo "воскресенье" ;;
    ru_RU:lang_zh) echo "简体中文" ;;
    ru_RU:lang_en) echo "English" ;;
    ru_RU:lang_ru) echo "Русский" ;;
    ru_RU:lang_fa) echo "فارسی" ;;

    fa_IR:dep_missing) echo "دستور موردنیاز پیدا نشد: %s" ;;
    fa_IR:main_title) echo "مدیریت بروزرسانی خودکار Geo برای 3xui" ;;
    fa_IR:menu_config) echo "پیکربندی یا ویرایش بروزرسانی خودکار" ;;
    fa_IR:menu_run) echo "اجرای فوری بررسی بروزرسانی" ;;
    fa_IR:menu_logs) echo "مشاهده گزارش‌ها" ;;
    fa_IR:menu_show_config) echo "نمایش تنظیمات فعلی" ;;
    fa_IR:menu_language) echo "تغییر زبان" ;;
    fa_IR:menu_remove_task) echo "حذف زمان‌بندی خودکار" ;;
    fa_IR:menu_uninstall) echo "حذف کامل اسکریپت" ;;
    fa_IR:menu_exit) echo "خروج" ;;
    fa_IR:prompt_choice) echo "گزینه را وارد کنید" ;;
    fa_IR:invalid_input) echo "ورودی نامعتبر است." ;;
    fa_IR:current_config) echo "تنظیمات فعلی" ;;
    fa_IR:enabled_sources) echo "منابع فعال" ;;
    fa_IR:schedule_mode) echo "حالت زمان‌بندی" ;;
    fa_IR:cron_actual) echo "cron واقعی" ;;
    fa_IR:current_cron) echo "وظیفه cron فعلی" ;;
    fa_IR:log_file) echo "فایل گزارش" ;;
    fa_IR:not_set) echo "تنظیم نشده" ;;
    fa_IR:current_language) echo "زبان فعلی" ;;
    fa_IR:mode_daily) echo "هر روز ساعت 03:00" ;;
    fa_IR:mode_weekly) echo "هر %s ساعت 03:00" ;;
    fa_IR:mode_interval) echo "هر %s روز ساعت 03:00" ;;
    fa_IR:mode_custom) echo "cron سفارشی" ;;
    fa_IR:logs_title) echo "مشاهده گزارش‌ها" ;;
    fa_IR:logs_50) echo "نمایش 50 خط آخر" ;;
    fa_IR:logs_100) echo "نمایش 100 خط آخر" ;;
    fa_IR:logs_follow) echo "دنبال کردن زنده گزارش" ;;
    fa_IR:back) echo "بازگشت" ;;
    fa_IR:source_title) echo "انتخاب منابع برای بروزرسانی خودکار" ;;
    fa_IR:source_list_intro) echo "منابع قابل انتخاب:" ;;
    fa_IR:source1_name) echo "Loyalsoldier" ;;
    fa_IR:source1_file) echo "فایل‌ها: geoip.dat + geosite.dat" ;;
    fa_IR:source1_desc) echo "توضیح: پایه‌ای‌ترین و رایج‌ترین گزینه برای بیشتر کاربران" ;;
    fa_IR:source2_name) echo "chocolate4u" ;;
    fa_IR:source2_file) echo "فایل‌ها: geoip_IR.dat + geosite_IR.dat" ;;
    fa_IR:source2_desc) echo "توضیح: قوانین مرتبط با ایران" ;;
    fa_IR:source3_name) echo "runetfreedom" ;;
    fa_IR:source3_file) echo "فایل‌ها: geoip_RU.dat + geosite_RU.dat" ;;
    fa_IR:source3_desc) echo "توضیح: قوانین مرتبط با روسیه" ;;
    fa_IR:source4_name) echo "انتخاب همه" ;;
    fa_IR:source4_desc) echo "معادل: 1,2,3" ;;
    fa_IR:source_help1) echo "فقط قوانین پایه: 1" ;;
    fa_IR:source_help2) echo "چند منبع: 1,3" ;;
    fa_IR:source_help3) echo "همه منابع: 4" ;;
    fa_IR:source_help4) echo "بین اعداد از ویرگول انگلیسی استفاده کنید" ;;
    fa_IR:source_help5) echo "فاصله‌ها به‌طور خودکار حذف می‌شوند" ;;
    fa_IR:source_prompt) echo "شماره منابع فعال را وارد کنید" ;;
    fa_IR:source_invalid) echo "فرمت نامعتبر است. نمونه صحیح: 1 / 1,3 / 4" ;;
    fa_IR:schedule_title) echo "تنظیم زمان‌بندی بروزرسانی خودکار" ;;
    fa_IR:schedule_daily) echo "روزانه" ;;
    fa_IR:schedule_daily_desc) echo "زمان پیش‌فرض: 03:00" ;;
    fa_IR:schedule_weekly) echo "هفتگی" ;;
    fa_IR:schedule_weekly_desc1) echo "زمان پیش‌فرض: 03:00" ;;
    fa_IR:schedule_weekly_desc2) echo "روز پیش‌فرض: دوشنبه" ;;
    fa_IR:schedule_interval) echo "هر N روز" ;;
    fa_IR:schedule_interval_desc) echo "زمان پیش‌فرض: 03:00" ;;
    fa_IR:schedule_custom) echo "عبارت cron سفارشی" ;;
    fa_IR:schedule_prompt) echo "نوع زمان‌بندی را انتخاب کنید" ;;
    fa_IR:weekday_title) echo "روز هفته را انتخاب کنید" ;;
    fa_IR:weekday_prompt) echo "شماره را وارد کنید (پیش‌فرض 1 = دوشنبه)" ;;
    fa_IR:interval_prompt) echo "عدد N را وارد کنید (مثلاً 3 یعنی هر 3 روز)" ;;
    fa_IR:interval_invalid) echo "لطفاً یک عدد صحیح بزرگ‌تر یا مساوی 1 وارد کنید." ;;
    fa_IR:cron_help_title) echo "راهنمای cron" ;;
    fa_IR:cron_help_format) echo "دقیقه ساعت روز ماه روزهفته" ;;
    fa_IR:cron_help_examples) echo "نمونه: 0 3 * * * یعنی هر روز ساعت 03:00؛ 0 3 * * 1 یعنی هر دوشنبه ساعت 03:00" ;;
    fa_IR:cron_prompt) echo "عبارت cron پنج‌بخشی را وارد کنید" ;;
    fa_IR:cron_invalid) echo "عبارت cron نامعتبر است." ;;
    fa_IR:saved) echo "تنظیمات ذخیره شد" ;;
    fa_IR:run_now_prompt) echo "همین حالا بررسی بروزرسانی اجرا شود؟ [y/N]" ;;
    fa_IR:run_skipped) echo "اجرای فوری رد شد." ;;
    fa_IR:language_title) echo "تغییر زبان" ;;
    fa_IR:language_prompt) echo "زبان را انتخاب کنید" ;;
    fa_IR:language_saved) echo "زبان ذخیره شد." ;;
    fa_IR:remove_task_done) echo "زمان‌بندی خودکار حذف شد." ;;
    fa_IR:weekday_mon) echo "دوشنبه" ;;
    fa_IR:weekday_tue) echo "سه‌شنبه" ;;
    fa_IR:weekday_wed) echo "چهارشنبه" ;;
    fa_IR:weekday_thu) echo "پنج‌شنبه" ;;
    fa_IR:weekday_fri) echo "جمعه" ;;
    fa_IR:weekday_sat) echo "شنبه" ;;
    fa_IR:weekday_sun) echo "یکشنبه" ;;
    fa_IR:lang_zh) echo "简体中文" ;;
    fa_IR:lang_en) echo "English" ;;
    fa_IR:lang_ru) echo "Русский" ;;
    fa_IR:lang_fa) echo "فارسی" ;;

    *) echo "$key" ;;
  esac
}

ensure_crontab_available() {
  if ! command -v crontab >/dev/null 2>&1; then
    echo "$(printf "$(t dep_missing)" "crontab")"
    echo "错误: 当前系统无法写入定时任务，因为缺少 crontab 命令。"
    return 1
  fi
  return 0
}

check_cron_ready() {
  local svc=""

  if ! command -v crontab >/dev/null 2>&1; then
    return 1
  fi

  svc="$(find_cron_service_name || true)"
  if [[ -n "$svc" ]]; then
    start_and_enable_cron_service "$svc" >/dev/null 2>&1 || true
  fi
  return 0
}

weekday_name_local() {
  case "$1" in
    1) echo "$(t weekday_mon)" ;;
    2) echo "$(t weekday_tue)" ;;
    3) echo "$(t weekday_wed)" ;;
    4) echo "$(t weekday_thu)" ;;
    5) echo "$(t weekday_fri)" ;;
    6) echo "$(t weekday_sat)" ;;
    0) echo "$(t weekday_sun)" ;;
    *) echo "$1" ;;
  esac
}

lang_name_local() {
  case "$1" in
    zh_CN) echo "$(t lang_zh)" ;;
    en_US) echo "$(t lang_en)" ;;
    ru_RU) echo "$(t lang_ru)" ;;
    fa_IR) echo "$(t lang_fa)" ;;
    *) echo "$1" ;;
  esac
}

show_selected_sources() {
  local raw="$1"
  IFS=',' read -r -a arr <<< "$raw"
  for x in "${arr[@]}"; do
    x="$(echo "$x" | xargs)"
    case "$x" in
      1) echo "  - Loyalsoldier（geoip.dat / geosite.dat）" ;;
      2) echo "  - chocolate4u（geoip_IR.dat / geosite_IR.dat）" ;;
      3) echo "  - runetfreedom（geoip_RU.dat / geosite_RU.dat）" ;;
    esac
  done
}

normalize_sources() {
  local raw="$1"
  raw="$(echo "$raw" | tr -d ' ')"

  if [[ "$raw" == "4" ]]; then
    echo "1,2,3"
    return 0
  fi

  if [[ ! "$raw" =~ ^[123](,[123])*$ ]]; then
    return 1
  fi

  echo "$raw" | awk -F',' '
    {
      for (i = 1; i <= NF; i++) {
        if (!seen[$i]++) {
          out = out ? out "," $i : $i
        }
      }
    }
    END { print out }
  '
}

install_cron() {
  local line="$CRON_SCHEDULE /usr/local/bin/3xui-geo-runner.sh $CRON_MARK"
  local current

  current="$(crontab -l 2>/dev/null || true)"
  current="$(printf '%s\n' "$current" \
    | grep -Fv "$CRON_MARK" \
    | grep -Fv "/usr/local/bin/3xui-geo-runner.sh" \
    || true)"

  {
    printf '%s\n' "$current"
    printf '%s\n' "$line"
  } | awk 'NF' | crontab -

  if ! crontab -l 2>/dev/null | grep -Fq "/usr/local/bin/3xui-geo-runner.sh"; then
    echo "错误: 定时任务写入失败。"
    return 1
  fi
}

remove_cron() {
  local current
  current="$(crontab -l 2>/dev/null || true)"
  printf '%s\n' "$current" \
    | grep -Fv "$CRON_MARK" \
    | grep -Fv "/usr/local/bin/3xui-geo-runner.sh" \
    | awk 'NF' \
    | crontab -
}

show_config() {
  echo
  echo "========== $(t current_config) =========="
  echo "$(t enabled_sources):"
  show_selected_sources "$SOURCES"
  echo
  echo "$(t schedule_mode):"
  case "$MODE" in
    daily)
      echo "  $(t mode_daily)"
      ;;
    weekly)
      printf "  $(t mode_weekly)\n" "$(weekday_name_local "$WEEKDAY")"
      ;;
    interval)
      printf "  $(t mode_interval)\n" "${INTERVAL_DAYS:-1}"
      ;;
    custom)
      echo "  $(t mode_custom)"
      ;;
    *)
      echo "  $MODE"
      ;;
  esac
  echo
  echo "$(t cron_actual):"
  echo "  ${CRON_SCHEDULE:-$(t not_set)}"
  echo
  echo "$(t current_language):"
  echo "  $(lang_name_local "$LANGUAGE")"
  echo
  echo "$(t current_cron):"
  if command -v crontab >/dev/null 2>&1; then
    crontab -l 2>/dev/null | grep -F "$CRON_MARK" || echo "  $(t not_set)"
  else
    echo "  $(t not_set)"
  fi
  echo
  echo "$(t log_file):"
  echo "  $LOG_FILE"
}

show_logs() {
  touch "$LOG_FILE"

  while true; do
    echo
    echo "========== $(t logs_title) =========="
    echo "1. $(t logs_50)"
    echo "2. $(t logs_100)"
    echo "3. $(t logs_follow)"
    echo "0. $(t back)"
    echo
    read -rp "$(t prompt_choice): " c

    case "$c" in
      1) tail -n 50 "$LOG_FILE" ;;
      2) tail -n 100 "$LOG_FILE" ;;
      3) tail -f "$LOG_FILE" ;;
      0) return 0 ;;
      *) echo "$(t invalid_input)" ;;
    esac
  done
}

choose_sources() {
  local src normalized

  while true; do
    echo
    echo "========== $(t source_title) =========="
    echo "$(t source_list_intro)"
    echo
    echo "  1. $(t source1_name)"
    echo "     $(t source1_file)"
    echo "     $(t source1_desc)"
    echo
    echo "  2. $(t source2_name)"
    echo "     $(t source2_file)"
    echo "     $(t source2_desc)"
    echo
    echo "  3. $(t source3_name)"
    echo "     $(t source3_file)"
    echo "     $(t source3_desc)"
    echo
    echo "  4. $(t source4_name)"
    echo "     $(t source4_desc)"
    echo
    echo "  - $(t source_help1)"
    echo "  - $(t source_help2)"
    echo "  - $(t source_help3)"
    echo "  - $(t source_help4)"
    echo "  - $(t source_help5)"
    echo

    read -rp "$(t source_prompt): " src

    if normalized="$(normalize_sources "$src")"; then
      SOURCES="$normalized"
      return 0
    fi

    echo "$(t source_invalid)"
  done
}

choose_schedule() {
  local freq custom n weekday

  while true; do
    echo
    echo "========== $(t schedule_title) =========="
    echo "1. $(t schedule_daily)"
    echo "   $(t schedule_daily_desc)"
    echo
    echo "2. $(t schedule_weekly)"
    echo "   $(t schedule_weekly_desc1)"
    echo "   $(t schedule_weekly_desc2)"
    echo
    echo "3. $(t schedule_interval)"
    echo "   $(t schedule_interval_desc)"
    echo
    echo "4. $(t schedule_custom)"
    echo
    read -rp "$(t schedule_prompt): " freq

    case "$freq" in
      1)
        MODE="daily"
        CRON_SCHEDULE="0 3 * * *"
        INTERVAL_DAYS=""
        WEEKDAY="1"
        return 0
        ;;
      2)
        echo
        echo "========== $(t weekday_title) =========="
        echo "1. $(t weekday_mon)"
        echo "2. $(t weekday_tue)"
        echo "3. $(t weekday_wed)"
        echo "4. $(t weekday_thu)"
        echo "5. $(t weekday_fri)"
        echo "6. $(t weekday_sat)"
        echo "7. $(t weekday_sun)"
        echo
        read -rp "$(t weekday_prompt): " weekday
        weekday="${weekday:-1}"

        case "$weekday" in
          1) weekday=1 ;;
          2) weekday=2 ;;
          3) weekday=3 ;;
          4) weekday=4 ;;
          5) weekday=5 ;;
          6) weekday=6 ;;
          7) weekday=0 ;;
          *)
            echo "$(t invalid_input)"
            continue
            ;;
        esac

        MODE="weekly"
        WEEKDAY="$weekday"
        CRON_SCHEDULE="0 3 * * $weekday"
        INTERVAL_DAYS=""
        return 0
        ;;
      3)
        echo
        read -rp "$(t interval_prompt): " n

        if [[ ! "$n" =~ ^[1-9][0-9]*$ ]]; then
          echo "$(t interval_invalid)"
          continue
        fi

        MODE="interval"
        INTERVAL_DAYS="$n"
        WEEKDAY="1"
        CRON_SCHEDULE="0 3 * * *"
        return 0
        ;;
      4)
        echo
        echo "========== $(t cron_help_title) =========="
        echo "  $(t cron_help_format)"
        echo
        echo "  $(t cron_help_examples)"
        echo
        read -rp "$(t cron_prompt): " custom

        if [[ "$custom" =~ ^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+$ ]]; then
          MODE="custom"
          CRON_SCHEDULE="$custom"
          INTERVAL_DAYS=""
          WEEKDAY="1"
          return 0
        fi

        echo "$(t cron_invalid)"
        ;;
      *)
        echo "$(t invalid_input)"
        ;;
    esac
  done
}

switch_language() {
  local choice

  echo
  echo "========== $(t language_title) =========="
  echo "1. 简体中文"
  echo "2. English"
  echo "3. Русский"
  echo "4. فارسی"
  echo

  read -rp "$(t language_prompt): " choice

  case "$choice" in
    1) LANGUAGE="zh_CN" ;;
    2) LANGUAGE="en_US" ;;
    3) LANGUAGE="ru_RU" ;;
    4) LANGUAGE="fa_IR" ;;
    *) echo "$(t invalid_input)"; return 1 ;;
  esac

  save_config
  echo "$(t language_saved)"
}

setup_task() {
  if ! ensure_crontab_available; then
    return 1
  fi

  check_cron_ready || true

  choose_sources
  choose_schedule
  save_config

  if ! install_cron; then
    return 1
  fi

  echo
  echo "========== $(t saved) =========="
  echo "$(t enabled_sources):"
  show_selected_sources "$SOURCES"
  echo
  echo "$(t schedule_mode):"
  case "$MODE" in
    daily)
      echo "  $(t mode_daily)"
      ;;
    weekly)
      printf "  $(t mode_weekly)\n" "$(weekday_name_local "$WEEKDAY")"
      ;;
    interval)
      printf "  $(t mode_interval)\n" "${INTERVAL_DAYS:-1}"
      ;;
    custom)
      echo "  $(t mode_custom)"
      ;;
  esac
  echo
  echo "$(t cron_actual):"
  echo "  $CRON_SCHEDULE"
  echo

  read -rp "$(t run_now_prompt): " runnow
  case "$runnow" in
    y|Y|yes|YES|1)
      "$RUNNER" --force
      ;;
    *)
      echo "$(t run_skipped)"
      ;;
  esac
}

main_menu() {
  while true; do
    echo
    echo "========== $(t main_title) =========="
    echo "1. $(t menu_config)"
    echo "2. $(t menu_run)"
    echo "3. $(t menu_logs)"
    echo "4. $(t menu_show_config)"
    echo "5. $(t menu_language)"
    echo "6. $(t menu_remove_task)"
    echo "7. $(t menu_uninstall)"
    echo "0. $(t menu_exit)"
    echo

    read -rp "$(t prompt_choice): " choice

    case "$choice" in
      1) setup_task ;;
      2) "$RUNNER" --force ;;
      3) show_logs ;;
      4) show_config ;;
      5) switch_language ;;
      6)
        if ensure_crontab_available; then
          remove_cron
          echo "$(t remove_task_done)"
        fi
        ;;
      7)
        bash "$UNINSTALLER"
        exit 0
        ;;
      0) exit 0 ;;
      *) echo "$(t invalid_input)" ;;
    esac
  done
}

load_config
require_root
require_cmd grep awk tail
ensure_initial_language
touch "$LOG_FILE"
main_menu
MANAGER_EOF

cat > "$WRAPPER_SHORT" <<'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "uninstall" || "${1:-}" == "--uninstall" || "${1:-}" == "remove" ]]; then
  exec /usr/local/bin/3xui-geo-uninstall.sh
else
  exec /usr/local/bin/3xui-geo-manager.sh "$@"
fi
WRAPPER_EOF

cat > "$WRAPPER_ALT" <<'WRAPPER2_EOF'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/3xui-geo-manager.sh "$@"
WRAPPER2_EOF

chmod +x "$RUNNER" "$MANAGER" "$UNINSTALLER" "$WRAPPER_SHORT" "$WRAPPER_ALT"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

echo "安装完成。"
echo "可用命令："
echo "  xgeo                打开管理菜单"
echo "  3xui-geo            打开管理菜单"
echo "  xgeo uninstall      一键卸载"
print_swap_notice
echo
echo "现在为你启动管理菜单..."
exec /usr/local/bin/3xui-geo-manager.sh
