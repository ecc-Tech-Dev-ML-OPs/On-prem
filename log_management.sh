#!/bin/bash
###############################################################################
# Ubuntu Log Management Script — v3 (Interactive + Centralized + Dynamic)
# ─────────────────────────────────────────────────────────────────────────────
# • Shows WARNING before each section with exact impact
# • Asks "Continue? (y/N)" before executing
# • Centralized log collection for all services
# Usage : sudo bash log_management.sh
# Date  : 2026-02-27
###############################################################################

set -euo pipefail

# ─── Colors & Helpers ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/server.conf"
REPORT_FILE="/root/log_management_report_$(date +%Y%m%d_%H%M%S).txt"
SKIPPED_SECTIONS=()

# ─── Load Config ─────────────────────────────────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then log_error "Config not found: $CONFIG_FILE"; exit 1; fi
source "$CONFIG_FILE"

RETENTION="${LOG_RETENTION_DAYS}"
MAX_DISK="${LOG_MAX_DISK_GB}"
ALERT_THRESHOLD="${LOG_ALERT_THRESHOLD_MB}"
CENTRAL_DIR="${CENTRALIZED_LOG_DIR}"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then log_error "Must be run as root."; exit 1; fi

# ─── Confirmation Helper ────────────────────────────────────────────────────
confirm_section() {
    local section_name="$1" config_flag="$2"
    if [[ "${!config_flag}" != "yes" ]]; then
        echo -e "${DIM}  [SKIPPED by config: ${config_flag}=no]${NC}"
        SKIPPED_SECTIONS+=("$section_name (config)")
        return 1
    fi
    if [[ "${INTERACTIVE_MODE}" != "yes" ]]; then return 0; fi
    echo ""
    read -p "  ➤ Proceed with ${section_name}? (y/N): " ANSWER
    if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}  [SKIPPED by user]${NC}"
        SKIPPED_SECTIONS+=("$section_name (user)")
        return 1
    fi
    return 0
}

# ─── Master Warning ─────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  ${BOLD}📋 LOG MANAGEMENT — ${SERVER_NAME}${NC}${CYAN}                         ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║  This script will:                                          ║${NC}"
echo -e "${CYAN}║  • Create centralized log directory: ${CENTRAL_DIR}         ${NC}"
echo -e "${CYAN}║  • Configure journald: ${RETENTION}-day retention, ${MAX_DISK}GB max      ║${NC}"
echo -e "${CYAN}║  • Set up rsyslog forwarding to centralized dir             ║${NC}"
echo -e "${CYAN}║  • Configure Docker container log collection                ║${NC}"
echo -e "${CYAN}║  • Create logrotate rules (${RETENTION}-day rotation)       ║${NC}"
echo -e "${CYAN}║  • Install logwatch for daily summaries                     ║${NC}"
echo -e "${CYAN}║  • Install cron jobs for cleanup + monitoring               ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║  ${BOLD}⛔ NO existing log files are deleted${NC}${CYAN}                       ║${NC}"
echo -e "${CYAN}║  ${BOLD}⛔ Docker containers are NEVER touched${NC}${CYAN}                    ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║  Each section asks for confirmation before executing.        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "${INTERACTIVE_MODE}" == "yes" ]]; then
    read -p "Start log management setup? (y/N): " START
    if [[ ! "$START" =~ ^[Yy]$ ]]; then echo "Aborted."; exit 0; fi
fi

echo "Log Management Report — $(date)" > "$REPORT_FILE"
echo "Server: ${SERVER_NAME} | Retention: ${RETENTION}d" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# 1. CENTRALIZED LOG DIRECTORY
# ─────────────────────────────────────────────────────────────────────────────
log_section "1/8 — Centralized Log Directory"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Creates: ${CENTRAL_DIR}/"
echo "    • Subdirs: system/, docker/, services/, security/, applications/"
echo "    • Permissions: 750, owned by root:adm"
echo -e "${GREEN}  ✅ RISK: None — new directory only, nothing modified${NC}"

if confirm_section "Centralized Log Directory" "RUN_CENTRALIZED_DIR"; then
    mkdir -p "$CENTRAL_DIR"
    for subdir in system docker services security applications; do
        mkdir -p "$CENTRAL_DIR/$subdir"
        chmod 750 "$CENTRAL_DIR/$subdir"
        chown root:adm "$CENTRAL_DIR/$subdir"
    done
    chmod 750 "$CENTRAL_DIR"
    chown root:adm "$CENTRAL_DIR"
    log_info "✅ Centralized directory created: $CENTRAL_DIR"
    echo "[DONE] Centralized dir" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. JOURNALD
# ─────────────────────────────────────────────────────────────────────────────
log_section "2/8 — Journald Configuration"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • OVERWRITES: /etc/systemd/journald.conf"
echo "    • Retention: ${RETENTION} days"
echo "    • Max disk: ${MAX_DISK}GB"
echo "    • Storage: persistent (survives reboots)"
echo -e "${YELLOW}  ⚠ BACKUP:${NC} journald.conf.bak (same directory)"
echo -e "${YELLOW}  ⚠ SERVICES RESTARTED:${NC} systemd-journald (<1 sec)"
echo -e "${YELLOW}  ⚠ RISK:${NC} Medium — existing journald settings replaced"

if confirm_section "Journald" "RUN_JOURNALD"; then
    cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak 2>/dev/null || true
    cat > /etc/systemd/journald.conf <<EOF
[Journal]
# ${SERVER_NAME} — ${RETENTION}-day retention
Storage=persistent
Compress=yes
MaxRetentionSec=${RETENTION}day
SystemMaxUse=${MAX_DISK}G
SystemKeepFree=1G
SystemMaxFileSize=100M
RateLimitIntervalSec=30s
RateLimitBurst=10000
ForwardToSyslog=yes
EOF
    mkdir -p /var/log/journal
    systemd-tmpfiles --create --prefix /var/log/journal
    systemctl restart systemd-journald
    log_info "✅ Journald: ${RETENTION}-day, ${MAX_DISK}GB max"
    echo "[DONE] Journald" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. RSYSLOG — Centralized Collection
# ─────────────────────────────────────────────────────────────────────────────
log_section "3/8 — Rsyslog Centralized Forwarding"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Installs: rsyslog (if not present)"
echo "    • Creates: /etc/rsyslog.d/50-centralized.conf"
echo "    • Copies logs to: ${CENTRAL_DIR}/system/"
echo "    • Original log locations are NOT changed"
echo -e "${YELLOW}  ⚠ SERVICES RESTARTED:${NC} rsyslog (<1 sec)"
echo -e "${GREEN}  ✅ RISK: Low — adds copies, originals untouched${NC}"

if confirm_section "Rsyslog" "RUN_RSYSLOG"; then
    apt-get install -y rsyslog >> "$REPORT_FILE" 2>&1
    cat > /etc/rsyslog.d/50-centralized.conf <<EOF
# ${SERVER_NAME} — centralized logging
auth,authpriv.*    ${CENTRAL_DIR}/system/auth.log
kern.*             ${CENTRAL_DIR}/system/kern.log
cron.*             ${CENTRAL_DIR}/system/cron.log
mail.*             ${CENTRAL_DIR}/system/mail.log
daemon.*           ${CENTRAL_DIR}/system/daemon.log
*.warn             ${CENTRAL_DIR}/system/warnings.log
auth,authpriv.*    /var/log/auth.log
kern.*             /var/log/kern.log
cron.*             /var/log/cron.log
*.emerg            :omusrmsg:*
EOF
    systemctl restart rsyslog
    log_info "✅ Rsyslog forwarding to $CENTRAL_DIR/system/"
    echo "[DONE] Rsyslog" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. DOCKER LOG COLLECTION
# ─────────────────────────────────────────────────────────────────────────────
log_section "4/8 — Docker Container Log Collection"

if command -v docker &>/dev/null; then
    CONTAINER_COUNT=$(docker ps -a -q 2>/dev/null | wc -l)
    RUNNING_COUNT=$(docker ps -q 2>/dev/null | wc -l)
    echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
    echo "    • Updates: /etc/docker/daemon.json (log rotation settings)"
    echo "    • Creates: /usr/local/bin/collect-docker-logs.sh"
    echo "    • Docker containers found: ${RUNNING_COUNT} running / ${CONTAINER_COUNT} total"
    echo -e "${GREEN}  ✅ NO containers, images, or volumes are deleted${NC}"
    echo -e "${GREEN}  ✅ NO containers are stopped or restarted${NC}"
    echo "    • Adds: daily log rotation (50MB max per container, 5 files)"
    echo "    • Collects: container logs → ${CENTRAL_DIR}/docker/"
    echo -e "${YELLOW}  ⚠ NOTE:${NC} daemon.json changes apply to NEW container logs only"
    echo -e "${YELLOW}  ⚠ BACKUP:${NC} daemon.json.bak"

    if confirm_section "Docker Logs" "RUN_DOCKER_LOGS"; then
        DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"
        [ -f "$DOCKER_DAEMON_CONFIG" ] && cp "$DOCKER_DAEMON_CONFIG" "$DOCKER_DAEMON_CONFIG.bak"

        python3 -c "
import json, os
path = '$DOCKER_DAEMON_CONFIG'
config = {}
if os.path.exists(path):
    try:
        with open(path) as f: config = json.load(f)
    except: pass
config['log-driver'] = 'json-file'
config['log-opts'] = {'max-size': '50m', 'max-file': '5', 'tag': '{{.Name}}'}
with open(path, 'w') as f: json.dump(config, f, indent=2)
" 2>/dev/null || log_warn "Could not update daemon.json"

        cat > /usr/local/bin/collect-docker-logs.sh <<SCRIPT
#!/bin/bash
DOCKER_LOG_DIR="${CENTRAL_DIR}/docker"
mkdir -p "\$DOCKER_LOG_DIR"
for cid in \$(docker ps -a --format '{{.ID}}' 2>/dev/null); do
    cname=\$(docker inspect --format '{{.Name}}' "\$cid" 2>/dev/null | sed 's|^/||')
    [ -n "\$cname" ] && docker logs --since 24h "\$cid" > "\$DOCKER_LOG_DIR/\${cname}.log" 2>&1 || true
done
chmod 640 "\$DOCKER_LOG_DIR"/*.log 2>/dev/null || true
SCRIPT
        chmod 755 /usr/local/bin/collect-docker-logs.sh
        log_info "✅ Docker log collection configured"
        echo "[DONE] Docker logs" >> "$REPORT_FILE"
    fi
else
    log_info "Docker not installed — skipping."
    echo "[SKIP] Docker" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. SERVICE LOG SYMLINKS
# ─────────────────────────────────────────────────────────────────────────────
log_section "5/8 — Service Log Symlinks"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Creates symlinks in ${CENTRAL_DIR}/services/ for:"
echo "      grafana, prometheus, loki, alloy, alertmanager, trivy"
echo "    • Creates symlinks in ${CENTRAL_DIR}/security/ for:"
echo "      ufw.log, fail2ban.log, audit/"
echo "    • Creates missing log directories if needed"
echo -e "${GREEN}  ✅ RISK: None — symlinks only, no data moved${NC}"

if confirm_section "Service Symlinks" "RUN_SERVICE_SYMLINKS"; then
    SERVICES_DIR="$CENTRAL_DIR/services"
    SECURITY_DIR="$CENTRAL_DIR/security"

    declare -A SVC_LOGS=(
        ["grafana"]="/var/log/grafana"
        ["prometheus"]="/var/log/prometheus"
        ["loki"]="/var/log/loki"
        ["alloy"]="/var/log/alloy"
        ["alertmanager"]="/var/log/alertmanager"
        ["trivy"]="/var/log/trivy"
    )
    for custom in "${CUSTOM_LOG_PATHS[@]}"; do
        [ -d "$custom" ] && SVC_LOGS["$(basename "$custom")"]="$custom"
    done

    for name in "${!SVC_LOGS[@]}"; do
        src="${SVC_LOGS[$name]}"
        [ ! -d "$src" ] && mkdir -p "$src" && chmod 750 "$src"
        [ ! -L "$SERVICES_DIR/$name" ] && ln -sf "$src" "$SERVICES_DIR/$name"
        log_info "  → $name: $src"
    done

    for sec_log in ufw.log fail2ban.log; do
        [ -f "/var/log/$sec_log" ] && [ ! -L "$SECURITY_DIR/$sec_log" ] && ln -sf "/var/log/$sec_log" "$SECURITY_DIR/$sec_log"
    done
    [ -d "/var/log/audit" ] && [ ! -L "$SECURITY_DIR/audit" ] && ln -sf "/var/log/audit" "$SECURITY_DIR/audit"

    log_info "✅ Service symlinks created"
    echo "[DONE] Symlinks" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. LOGROTATE
# ─────────────────────────────────────────────────────────────────────────────
log_section "6/8 — Logrotate Configuration"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Creates 8 files in /etc/logrotate.d/"
echo "    • All set to: daily rotation, ${RETENTION}-day retention, compress"
echo "    • Categories: system, auth, security, audit, docker, services, apps, logwatch"
echo -e "${YELLOW}  ⚠ NOTE:${NC} May override existing logrotate configs for same log files"
echo -e "${GREEN}  ✅ RISK: Low — only affects how old logs are rotated${NC}"

if confirm_section "Logrotate" "RUN_LOGROTATE"; then
    # System logs
    cat > /etc/logrotate.d/01-system-${RETENTION}day <<EOF
/var/log/syslog /var/log/messages /var/log/kern.log /var/log/daemon.log
/var/log/user.log /var/log/debug ${CENTRAL_DIR}/system/*.log {
    daily
    rotate ${RETENTION}
    missingok
    notifempty
    compress
    delaycompress
    dateext
    dateformat -%Y%m%d
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate 2>/dev/null || true
    endscript
}
EOF
    cat > /etc/logrotate.d/02-auth-${RETENTION}day <<EOF
/var/log/auth.log ${CENTRAL_DIR}/system/auth.log {
    daily
    rotate ${RETENTION}
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 640 root adm
}
EOF
    cat > /etc/logrotate.d/03-security-${RETENTION}day <<EOF
/var/log/ufw.log /var/log/fail2ban.log {
    daily
    rotate ${RETENTION}
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 640 root adm
    postrotate
        fail2ban-client flushlogs >/dev/null 2>&1 || true
    endscript
}
EOF
    cat > /etc/logrotate.d/04-audit-${RETENTION}day <<EOF
/var/log/audit/audit.log {
    daily
    rotate ${RETENTION}
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 600 root root
    postrotate
        service auditd rotate >/dev/null 2>&1 || true
    endscript
}
EOF
    cat > /etc/logrotate.d/05-docker-${RETENTION}day <<EOF
${CENTRAL_DIR}/docker/*.log {
    daily
    rotate ${RETENTION}
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 640 root adm
}
EOF
    cat > /etc/logrotate.d/06-services-${RETENTION}day <<EOF
/var/log/grafana/*.log /var/log/prometheus/*.log /var/log/loki/*.log
/var/log/alloy/*.log /var/log/alertmanager/*.log /var/log/trivy/*.log
${CENTRAL_DIR}/services/*/*.log {
    daily
    rotate ${RETENTION}
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 640 root adm
}
EOF
    cat > /etc/logrotate.d/07-apps-${RETENTION}day <<EOF
${CENTRAL_DIR}/applications/*.log {
    daily
    rotate ${RETENTION}
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 640 root adm
}
EOF
    log_info "✅ 7 logrotate configs created (${RETENTION}-day)"
    echo "[DONE] Logrotate" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7. LOGWATCH
# ─────────────────────────────────────────────────────────────────────────────
log_section "7/8 — Logwatch Daily Reports"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Installs: logwatch package"
echo "    • Creates: /etc/logwatch/conf/logwatch.conf"
echo "    • Daily reports saved to: /var/log/logwatch/daily-report.log"
echo -e "${GREEN}  ✅ RISK: None — reporting only, no modifications${NC}"

if confirm_section "Logwatch" "RUN_LOGWATCH"; then
    apt-get install -y logwatch >> "$REPORT_FILE" 2>&1
    mkdir -p /var/cache/logwatch /var/log/logwatch /etc/logwatch/conf
    cat > /etc/logwatch/conf/logwatch.conf <<EOF
LogDir = /var/log
TmpDir = /var/cache/logwatch
MailTo = root
MailFrom = Logwatch-${SERVER_NAME}
Detail = Med
Range = yesterday
Service = All
Output = file
Filename = /var/log/logwatch/daily-report.log
Format = text
EOF
    cat > /etc/logrotate.d/08-logwatch-${RETENTION}day <<EOF
/var/log/logwatch/*.log {
    daily
    rotate ${RETENTION}
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 640 root adm
}
EOF
    log_info "✅ Logwatch daily reports configured"
    echo "[DONE] Logwatch" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 8. CRON JOBS
# ─────────────────────────────────────────────────────────────────────────────
log_section "8/8 — Automated Cron Jobs"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Creates: /etc/cron.daily/log-cleanup"
echo "      → Deletes .gz, .old, rotated logs OLDER than ${RETENTION} days"
echo "      → Runs journalctl --vacuum-time=${RETENTION}d"
echo "    • Creates: /etc/cron.daily/log-disk-monitor"
echo "      → Alerts if /var/log > ${ALERT_THRESHOLD}MB"
if command -v docker &>/dev/null; then
    echo "    • Creates: /etc/cron.daily/collect-docker-logs"
    echo "      → Collects container logs daily"
fi
echo ""
echo -e "${YELLOW}  FILES DELETED BY CRON (future, not now):${NC}"
echo "    • /var/log/*.gz older than ${RETENTION} days"
echo "    • /var/log/*.old older than ${RETENTION} days"
echo "    • /var/log/*.[0-9] older than ${RETENTION} days"
echo "    • /var/log/*.log-* older than ${RETENTION} days"
echo "    • ${CENTRAL_DIR}/*.log* older than ${RETENTION} days"
echo -e "${GREEN}  ✅ Active/current log files are NEVER deleted${NC}"

if confirm_section "Cron Jobs" "RUN_LOG_CRON"; then
    cat > /etc/cron.daily/log-cleanup <<EOF
#!/bin/bash
# ${SERVER_NAME} — daily log cleanup (>${RETENTION} days)
RETENTION=${RETENTION}
LOG="/var/log/log-cleanup.log"
echo "=== \$(date) ===" >> "\$LOG"
find /var/log -name "*.gz" -mtime +\$RETENTION -delete 2>/dev/null
find /var/log -name "*.old" -mtime +\$RETENTION -delete 2>/dev/null
find /var/log -name "*.[0-9]" -mtime +\$RETENTION -delete 2>/dev/null
find /var/log -name "*.[0-9].gz" -mtime +\$RETENTION -delete 2>/dev/null
find /var/log -name "*.log-*" -mtime +\$RETENTION -delete 2>/dev/null
find ${CENTRAL_DIR} -name "*.log*" -mtime +\$RETENTION -delete 2>/dev/null
find ${CENTRAL_DIR} -name "*.gz" -mtime +\$RETENTION -delete 2>/dev/null
journalctl --vacuum-time=\${RETENTION}d >> "\$LOG" 2>&1
echo "Disk: \$(du -sh /var/log/ 2>/dev/null | awk '{print \$1}')" >> "\$LOG"
EOF
    chmod 755 /etc/cron.daily/log-cleanup

    if command -v docker &>/dev/null; then
        cat > /etc/cron.daily/collect-docker-logs <<'EOF'
#!/bin/bash
/usr/local/bin/collect-docker-logs.sh
EOF
        chmod 755 /etc/cron.daily/collect-docker-logs
    fi

    cat > /etc/cron.daily/log-disk-monitor <<EOF
#!/bin/bash
THRESHOLD=${ALERT_THRESHOLD}
USAGE=\$(du -sm /var/log 2>/dev/null | awk '{print \$1}')
if [ "\$USAGE" -gt "\$THRESHOLD" ]; then
    echo "\$(date) — WARNING: /var/log=\${USAGE}MB (limit: \${THRESHOLD}MB)" >> /var/log/log-disk-alert.log
    logger -p user.warning "LOG ALERT: \${USAGE}MB exceeds \${THRESHOLD}MB"
fi
EOF
    chmod 755 /etc/cron.daily/log-disk-monitor

    log_info "✅ Cron jobs installed"
    echo "[DONE] Cron jobs" >> "$REPORT_FILE"
fi

# ─── SUMMARY ─────────────────────────────────────────────────────────────────
log_section "Log Management Complete — ${SERVER_NAME}"
echo ""
log_info "✅ Log management configured!"
log_info "📄 Report: $REPORT_FILE"
echo ""
echo -e "${CYAN}Architecture:${NC}"
echo "  ${CENTRAL_DIR}/"
echo "  ├── system/       ← auth, kern, cron, syslog"
echo "  ├── docker/       ← container logs (daily)"
echo "  ├── services/     ← grafana, prometheus, loki..."
echo "  ├── security/     ← ufw, fail2ban, audit"
echo "  └── applications/ ← your custom apps"
echo ""

if [ ${#SKIPPED_SECTIONS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped:${NC}"
    for s in "${SKIPPED_SECTIONS[@]}"; do echo "  • $s"; done
fi
echo ""
