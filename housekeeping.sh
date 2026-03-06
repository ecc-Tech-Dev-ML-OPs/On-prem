#!/bin/bash
###############################################################################
# Ubuntu Housekeeping Script — v3 (Interactive + Docker-Safe + Dynamic)
# ─────────────────────────────────────────────────────────────────────────────
# • Shows WARNING before each section
# • Asks confirmation before executing
# • Docker is NEVER touched (read-only status only)
# Usage : sudo bash housekeeping.sh
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
REPORT_FILE="/root/housekeeping_report_$(date +%Y%m%d_%H%M%S).txt"
SKIPPED_SECTIONS=()

# ─── Load Config ─────────────────────────────────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then log_error "Config not found: $CONFIG_FILE"; exit 1; fi
source "$CONFIG_FILE"

TEMP_AGE="${TEMP_FILE_MAX_AGE_DAYS}"
CRASH_AGE="${CRASH_REPORT_MAX_AGE_DAYS}"
RETENTION="${LOG_RETENTION_DAYS}"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then log_error "Must be root."; exit 1; fi

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
echo -e "${CYAN}║  ${BOLD}🧹 HOUSEKEEPING — ${SERVER_NAME}${NC}${CYAN}                            ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║  This script will clean:                                    ║${NC}"
echo -e "${CYAN}║  • Orphaned packages (apt autoremove)                       ║${NC}"
echo -e "${CYAN}║  • Temp files older than ${TEMP_AGE} days                   ║${NC}"
echo -e "${CYAN}║  • APT, pip, thumbnail caches                               ║${NC}"
echo -e "${CYAN}║  • Journal entries older than ${RETENTION} days             ║${NC}"
echo -e "${CYAN}║  • Old kernel versions (keeps current + latest)             ║${NC}"
echo -e "${CYAN}║  • Crash reports & core dumps older than ${CRASH_AGE} days  ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║  ${BOLD}⛔ DOCKER: NEVER touched — read-only status only${NC}${CYAN}          ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║  Each section asks for confirmation before executing.        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "${INTERACTIVE_MODE}" == "yes" ]]; then
    read -p "Start housekeeping? (y/N): " START
    if [[ ! "$START" =~ ^[Yy]$ ]]; then echo "Aborted."; exit 0; fi
fi

echo "Housekeeping Report — $(date)" > "$REPORT_FILE"
echo "Server: ${SERVER_NAME}" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"
DISK_BEFORE=$(df -h / | awk 'NR==2 {print $4}')
echo "Disk free BEFORE: $DISK_BEFORE" >> "$REPORT_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# 1. PACKAGE CLEANUP
# ─────────────────────────────────────────────────────────────────────────────
log_section "1/10 — Package Cleanup"
RESIDUAL_COUNT=$(dpkg -l | awk '/^rc/ {print $2}' 2>/dev/null | wc -l || echo "0")
AUTOREMOVE_COUNT=$(apt-get autoremove --dry-run 2>/dev/null | grep "^Remv" | wc -l || echo "0")
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • apt autoremove: ~${AUTOREMOVE_COUNT} orphaned packages to remove"
echo "    • apt autoclean: clears downloaded .deb files"
echo "    • Residual configs: ${RESIDUAL_COUNT} to purge"
echo -e "${YELLOW}  ⚠ DELETES:${NC} Unused dependency packages + cached .deb files"
echo -e "${GREEN}  ✅ Safe: only removes packages no longer needed${NC}"

if confirm_section "Package Cleanup" "RUN_PACKAGE_CLEANUP"; then
    apt-get autoremove -y >> "$REPORT_FILE" 2>&1
    apt-get autoclean -y >> "$REPORT_FILE" 2>&1
    apt-get clean >> "$REPORT_FILE" 2>&1
    RESIDUAL=$(dpkg -l | awk '/^rc/ {print $2}' 2>/dev/null || true)
    if [ -n "$RESIDUAL" ]; then
        echo "$RESIDUAL" | xargs dpkg --purge >> "$REPORT_FILE" 2>&1
    fi
    log_info "✅ Package cleanup done"
    echo "[DONE] Packages" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. TEMP FILES
# ─────────────────────────────────────────────────────────────────────────────
log_section "2/10 — Temporary Files"
TMP_SIZE=$(du -sm /tmp 2>/dev/null | awk '{print $1}')
TMP_OLD=$(find /tmp -type f -atime +${TEMP_AGE} 2>/dev/null | wc -l || echo "0")
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • /tmp current size: ${TMP_SIZE}MB"
echo "    • Files older than ${TEMP_AGE} days: ~${TMP_OLD}"
echo "    • Also cleans: /var/tmp (>${TEMP_AGE} days)"
echo "    • Removes: empty directories in /tmp"
echo -e "${YELLOW}  ⚠ DELETES:${NC} Old temp files only — active files untouched"

if confirm_section "Temp Cleanup" "RUN_TEMP_CLEANUP"; then
    TMP_BEFORE=$(du -sm /tmp 2>/dev/null | awk '{print $1}')
    find /tmp -type f -atime +${TEMP_AGE} -delete 2>/dev/null || true
    find /var/tmp -type f -atime +${TEMP_AGE} -delete 2>/dev/null || true
    find /tmp -type d -empty -delete 2>/dev/null || true
    TMP_AFTER=$(du -sm /tmp 2>/dev/null | awk '{print $1}')
    FREED=$((TMP_BEFORE - TMP_AFTER))
    log_info "✅ Freed ~${FREED}MB from /tmp"
    echo "[DONE] Temp: freed ${FREED}MB" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. CACHE CLEANUP
# ─────────────────────────────────────────────────────────────────────────────
log_section "3/10 — Cache Cleanup"
APT_CACHE=$(du -sm /var/cache/apt 2>/dev/null | awk '{print $1}')
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • APT cache: ${APT_CACHE}MB → will be cleared"
echo "    • pip cache: /root/.cache/pip, /home/*/.cache/pip → deleted"
echo "    • Thumbnails: old PNGs (>30 days) + thumbnail dirs → deleted"
echo -e "${YELLOW}  ⚠ DELETES:${NC} Cache files (all re-downloadable)"
echo -e "${GREEN}  ✅ Safe: caches auto-regenerate when needed${NC}"

if confirm_section "Cache Cleanup" "RUN_CACHE_CLEANUP"; then
    apt-get clean
    find /home -type d -name ".cache" -exec find {} -name "*.png" -mtime +30 -delete \; 2>/dev/null || true
    find /home -type d -name "thumbnails" -exec rm -rf {} \; 2>/dev/null || true
    find /root -path "*/.cache/pip" -exec rm -rf {} \; 2>/dev/null || true
    find /home -path "*/.cache/pip" -exec rm -rf {} \; 2>/dev/null || true
    log_info "✅ Caches cleared (was ${APT_CACHE}MB APT)"
    echo "[DONE] Cache" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. JOURNAL VACUUM
# ─────────────────────────────────────────────────────────────────────────────
log_section "4/10 — Journal Vacuum"
JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+[MG]' || echo "unknown")
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Current journal size: ${JOURNAL_SIZE}"
echo "    • Will vacuum to: max ${RETENTION} days / ${LOG_MAX_DISK_GB}GB"
echo -e "${YELLOW}  ⚠ DELETES:${NC} Journal entries older than ${RETENTION} days"

if confirm_section "Journal Vacuum" "RUN_JOURNAL_VACUUM"; then
    journalctl --vacuum-time=${RETENTION}d >> "$REPORT_FILE" 2>&1
    journalctl --vacuum-size=${LOG_MAX_DISK_GB}G >> "$REPORT_FILE" 2>&1
    JOURNAL_AFTER=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+[MG]' || echo "unknown")
    log_info "✅ Journal: ${JOURNAL_SIZE} → ${JOURNAL_AFTER}"
    echo "[DONE] Journal: ${JOURNAL_SIZE} → ${JOURNAL_AFTER}" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. OLD KERNELS
# ─────────────────────────────────────────────────────────────────────────────
log_section "5/10 — Old Kernel Removal"
CURRENT_KERNEL=$(uname -r)
OLD_KERNELS=$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ {print $2}' | grep -v "$CURRENT_KERNEL" | grep -v 'linux-image-generic' | head -n -1 || true)
OLD_COUNT=$(echo "$OLD_KERNELS" | grep -c "linux" 2>/dev/null || echo "0")
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Current kernel (KEPT): $CURRENT_KERNEL"
echo "    • Old kernels to remove: ${OLD_COUNT}"
if [ -n "$OLD_KERNELS" ]; then
    echo "$OLD_KERNELS" | while read k; do echo "      • $k"; done
fi
echo "    • Runs: update-grub after removal"
echo -e "${GREEN}  ✅ Safe: current running kernel is NEVER removed${NC}"

if confirm_section "Kernel Cleanup" "RUN_KERNEL_CLEANUP"; then
    if [ -n "$OLD_KERNELS" ]; then
        echo "$OLD_KERNELS" | xargs apt-get purge -y >> "$REPORT_FILE" 2>&1
        update-grub >> "$REPORT_FILE" 2>&1
        log_info "✅ ${OLD_COUNT} old kernels removed"
    else
        log_info "No old kernels to remove."
    fi
    echo "[DONE] Kernels" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. DOCKER STATUS (READ-ONLY)
# ─────────────────────────────────────────────────────────────────────────────
log_section "6/10 — Docker Status (READ-ONLY)"

if command -v docker &>/dev/null; then
    RUNNING=$(docker ps -q 2>/dev/null | wc -l)
    TOTAL=$(docker ps -aq 2>/dev/null | wc -l)
    echo -e "${GREEN}  ═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ DOCKER: READ-ONLY — NOTHING WILL BE DELETED     ${NC}"
    echo -e "${GREEN}  ✅ NO containers stopped, removed, or modified     ${NC}"
    echo -e "${GREEN}  ✅ NO images, volumes, or networks deleted          ${NC}"
    echo -e "${GREEN}  ═══════════════════════════════════════════════════${NC}"
    echo ""
    echo "    Containers: ${RUNNING} running / ${TOTAL} total"
    echo ""
    echo "    Container List:"
    docker ps -a --format '      • {{.Names}} ({{.Status}})' 2>/dev/null
    echo ""
    echo "    Disk Usage:"
    docker system df 2>/dev/null | sed 's/^/      /'
    echo ""
    echo "[DOCKER STATUS] ${RUNNING} running / ${TOTAL} total" >> "$REPORT_FILE"
    docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' >> "$REPORT_FILE" 2>&1
else
    log_info "Docker not installed."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7. SNAP CLEANUP
# ─────────────────────────────────────────────────────────────────────────────
log_section "7/10 — Snap Cleanup"
if command -v snap &>/dev/null; then
    DISABLED_SNAPS=$(snap list --all 2>/dev/null | awk '/disabled/{print $1}' | wc -l || echo "0")
    echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
    echo "    • Disabled snap revisions to remove: ${DISABLED_SNAPS}"
    echo -e "${GREEN}  ✅ Safe: only removes already-disabled old revisions${NC}"

    if confirm_section "Snap Cleanup" "RUN_SNAP_CLEANUP"; then
        snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read snapname revision; do
            snap remove "$snapname" --revision="$revision" 2>/dev/null || true
        done
        log_info "✅ Snap cleanup done"
        echo "[DONE] Snap" >> "$REPORT_FILE"
    fi
else
    log_info "Snap not installed — skipping."
fi

# ─────────────────────────────────────────────────────────────────────────────
# 8. ZOMBIE PROCESSES
# ─────────────────────────────────────────────────────────────────────────────
log_section "8/10 — Zombie Process Detection"
echo -e "${YELLOW}  ⚠ IMPACT:${NC} Read-only scan — reports only, does not kill anything"

if confirm_section "Zombie Check" "RUN_ZOMBIE_CHECK"; then
    ZOMBIES=$(ps aux | awk '{if($8=="Z") print}' 2>/dev/null || true)
    ZOMBIE_COUNT=$(echo "$ZOMBIES" | grep -c "Z" 2>/dev/null || echo "0")
    if [ "$ZOMBIE_COUNT" -gt 0 ]; then
        log_warn "Found $ZOMBIE_COUNT zombie(s):"
        echo "$ZOMBIES"
    else
        log_info "✅ No zombies found"
    fi
    echo "[DONE] Zombies: $ZOMBIE_COUNT" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 9. STALE FILES
# ─────────────────────────────────────────────────────────────────────────────
log_section "9/10 — Stale Files Cleanup"
CRASH_COUNT=$(find /var/crash -type f -mtime +${CRASH_AGE} 2>/dev/null | wc -l || echo "0")
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Crash reports (>${CRASH_AGE} days): ${CRASH_COUNT} files"
echo "    • Core dumps (>${CRASH_AGE} days): scanned in top 3 dir levels"
echo "    • Empty mail spool files: removed"
echo -e "${YELLOW}  ⚠ DELETES:${NC} Old crash reports and core dump files"

if confirm_section "Stale Cleanup" "RUN_STALE_CLEANUP"; then
    find /var/crash -type f -mtime +${CRASH_AGE} -delete 2>/dev/null || true
    find / -maxdepth 3 -name "core" -type f -mtime +${CRASH_AGE} -delete 2>/dev/null || true
    find / -maxdepth 3 -name "core.*" -type f -mtime +${CRASH_AGE} -delete 2>/dev/null || true
    find /var/mail -type f -size 0 -delete 2>/dev/null || true
    log_info "✅ Stale files cleaned"
    echo "[DONE] Stale" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 10. DISK REPORT + WEEKLY CRON
# ─────────────────────────────────────────────────────────────────────────────
log_section "10/10 — Disk Report & Weekly Cron"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Generates disk usage report in /root/"
echo "    • Installs weekly cron: /etc/cron.weekly/housekeeping"
echo -e "${GREEN}  ✅ RISK: None — reporting + scheduling only${NC}"

if confirm_section "Disk Report" "RUN_DISK_REPORT"; then
    DISK_AFTER=$(df -h / | awk 'NR==2 {print $4}')

    echo "" >> "$REPORT_FILE"
    echo "── Disk Summary ──" >> "$REPORT_FILE"
    echo "Free BEFORE: $DISK_BEFORE | Free AFTER: $DISK_AFTER" >> "$REPORT_FILE"
    df -hT >> "$REPORT_FILE" 2>&1
    echo "" >> "$REPORT_FILE"
    echo "── Top 15 Dirs ──" >> "$REPORT_FILE"
    du -hx --max-depth=2 / 2>/dev/null | sort -rh | head -15 >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "── System Health ──" >> "$REPORT_FILE"
    echo "Uptime: $(uptime)" >> "$REPORT_FILE"
    free -h >> "$REPORT_FILE" 2>&1

    # Install weekly cron
    SCRIPT_PATH="$(realpath "$0")"
    cat > /etc/cron.weekly/housekeeping <<EOF
#!/bin/bash
# Weekly — ${SERVER_NAME} (non-interactive)
INTERACTIVE_MODE=no $SCRIPT_PATH >> /var/log/housekeeping.log 2>&1
EOF
    chmod 755 /etc/cron.weekly/housekeeping
    cat > /etc/logrotate.d/09-housekeeping <<'EOF'
/var/log/housekeeping.log {
    weekly
    rotate 8
    missingok
    notifempty
    compress
    delaycompress
    create 640 root adm
}
EOF

    log_info "✅ Report generated, weekly cron installed"
    log_info "Disk: $DISK_BEFORE → $DISK_AFTER"
    echo "[DONE] Disk + Cron" >> "$REPORT_FILE"
fi

# ─── SUMMARY ─────────────────────────────────────────────────────────────────
log_section "Housekeeping Complete — ${SERVER_NAME}"
echo ""
log_info "✅ Housekeeping done!"
log_info "📄 Report: $REPORT_FILE"

if [ ${#SKIPPED_SECTIONS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Skipped:${NC}"
    for s in "${SKIPPED_SECTIONS[@]}"; do echo "  • $s"; done
fi
echo ""
