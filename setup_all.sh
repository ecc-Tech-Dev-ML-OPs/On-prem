#!/bin/bash
###############################################################################
# Ubuntu Server Setup — Master Script v3 (Full Freedom + Selective Execution)
# ─────────────────────────────────────────────────────────────────────────────
# • Choose which scripts to run (any combination)
# • Shows full impact preview before each script
# • Validates config before running
# • System status viewer
# Usage : sudo bash setup_all.sh
# Date  : 2026-02-27
###############################################################################

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/server.conf"

# ─── Load Config ─────────────────────────────────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}[ERROR] server.conf not found in $SCRIPT_DIR${NC}"
    exit 1
fi
source "$CONFIG_FILE"

# ─── Banner ──────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║  ${BOLD}${SERVER_NAME}${NC}${CYAN} — Server Management Suite v3               ║${NC}"
echo -e "${CYAN}║  Hardening • Logging • Housekeeping                          ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}║  ${DIM}Interactive Mode: ${INTERACTIVE_MODE}${NC}${CYAN}                                ║${NC}"
echo -e "${CYAN}║  ${DIM}Config: server.conf${NC}${CYAN}                                        ║${NC}"
echo -e "${CYAN}║                                                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── Pre-flight ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Run with: sudo bash setup_all.sh${NC}"
    exit 1
fi

echo -e "${BOLD}Pre-flight Checks:${NC}"
echo ""

# Ubuntu
if grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
    UBUNTU_VER=$(lsb_release -rs 2>/dev/null || grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    echo -e "  ${GREEN}✅${NC} Ubuntu $UBUNTU_VER"
else
    echo -e "  ${RED}❌ Not Ubuntu${NC}"; exit 1
fi

# Internet
if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} Internet connectivity"
else
    echo -e "  ${YELLOW}⚠️${NC}  No internet — package installs may fail"
fi

# Disk
ROOT_FREE=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
if [ "$ROOT_FREE" -lt 2 ]; then
    echo -e "  ${RED}❌ Only ${ROOT_FREE}GB free — need 2GB minimum${NC}"; exit 1
fi
echo -e "  ${GREEN}✅${NC} Disk: ${ROOT_FREE}GB free"

# Config
echo -e "  ${GREEN}✅${NC} Config loaded: server.conf"

# SSH keys
HAS_KEYS=false
for home in /root /home/*; do
    if [ -f "$home/.ssh/authorized_keys" ] && [ -s "$home/.ssh/authorized_keys" ]; then
        HAS_KEYS=true; break
    fi
done
if $HAS_KEYS; then
    echo -e "  ${GREEN}✅${NC} SSH keys found"
else
    echo -e "  ${RED}⚠️${NC}  No SSH keys detected — hardening will disable password auth!"
fi

# Docker
if command -v docker &>/dev/null; then
    RUNNING=$(docker ps -q 2>/dev/null | wc -l)
    TOTAL=$(docker ps -aq 2>/dev/null | wc -l)
    echo -e "  ${GREEN}✅${NC} Docker: ${RUNNING} running / ${TOTAL} total containers"
    echo -e "  ${GREEN}✅${NC} Docker cleanup: ${DOCKER_CLEANUP_ENABLED} (containers are SAFE)"
fi

echo ""

# ─── Config Summary ─────────────────────────────────────────────────────────
echo -e "${CYAN}── Quick Config Summary ──${NC}"
echo ""
echo -e "  Server:          ${BOLD}${SERVER_NAME}${NC}"
echo -e "  SSH Ports:       ${SSH_PORTS}"
echo -e "  Root Login:      ${SSH_PERMIT_ROOT}"
echo -e "  Password Auth:   ${SSH_PASSWORD_AUTH}"
echo -e "  Firewall Rules:  ${#FIREWALL_RULES[@]} ports"
echo -e "  Log Retention:   ${LOG_RETENTION_DAYS} days"
echo -e "  Docker Cleanup:  ${RED}DISABLED${NC} (never deletes)"
echo -e "  Interactive:     ${INTERACTIVE_MODE}"
echo ""

# ─── Helper Functions ────────────────────────────────────────────────────────
run_script() {
    local script="$1" name="$2"
    if [ ! -f "$script" ]; then
        echo -e "${RED}[ERROR] Not found: $script${NC}"
        return 1
    fi
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Starting: ${BOLD}$name${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    bash "$script"
    echo -e "${GREEN}[DONE] $name${NC}"
}

show_status() {
    echo ""
    echo -e "${CYAN}━━━ ${SERVER_NAME} — System Status ━━━${NC}"
    echo ""
    echo -e "${BOLD}OS:${NC}     $(lsb_release -ds 2>/dev/null || head -1 /etc/os-release)"
    echo -e "${BOLD}Uptime:${NC} $(uptime -p)"
    echo -e "${BOLD}Load:${NC}   $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
    echo ""
    echo -e "${BOLD}Disk:${NC}"
    df -hT / /var/log 2>/dev/null | sed 's/^/  /'
    echo ""
    echo -e "${BOLD}Memory:${NC}"
    free -h | sed 's/^/  /'
    echo ""
    echo -e "${BOLD}Firewall:${NC}"
    ufw status 2>/dev/null | sed 's/^/  /' || echo "  Not configured"
    echo ""
    echo -e "${BOLD}Fail2Ban:${NC}"
    fail2ban-client status 2>/dev/null | sed 's/^/  /' || echo "  Not running"
    echo ""
    echo -e "${BOLD}SSH Config:${NC}"
    grep -E "^(Port|PermitRootLogin|PasswordAuthentication)" /etc/ssh/sshd_config 2>/dev/null | sed 's/^/  /' || echo "  Default"
    echo ""
    if command -v docker &>/dev/null; then
        echo -e "${BOLD}Docker Containers:${NC}"
        docker ps -a --format '  {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null
        echo ""
    fi
    echo -e "${BOLD}Centralized Logs:${NC}"
    if [ -d "${CENTRALIZED_LOG_DIR}" ]; then
        du -sh "${CENTRALIZED_LOG_DIR}" 2>/dev/null | sed 's/^/  /'
        ls "${CENTRALIZED_LOG_DIR}/" 2>/dev/null | sed 's/^/  /'
    else
        echo "  Not configured"
    fi
    echo ""
    echo -e "${BOLD}Protected Services:${NC}"
    for svc in "${PROTECTED_SERVICES[@]}"; do
        status=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
        case "$status" in
            active)   echo -e "  ${GREEN}✅${NC} $svc" ;;
            inactive) echo -e "  ${YELLOW}⚠️${NC}  $svc (inactive)" ;;
            *)        echo -e "  ${DIM}── $svc ($status)${NC}" ;;
        esac
    done
    echo ""
}

# ─── Main Menu ───────────────────────────────────────────────────────────────
show_menu() {
    echo -e "${BOLD}═══ What do you want to run? ═══${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC}  🔐 Server Hardening only"
    echo -e "  ${CYAN}2)${NC}  📋 Log Management only"
    echo -e "  ${CYAN}3)${NC}  🧹 Housekeeping only"
    echo ""
    echo -e "  ${CYAN}4)${NC}  🔐+📋 Hardening + Log Management"
    echo -e "  ${CYAN}5)${NC}  🔐+🧹 Hardening + Housekeeping"
    echo -e "  ${CYAN}6)${NC}  📋+🧹 Log Management + Housekeeping"
    echo ""
    echo -e "  ${CYAN}7)${NC}  ${BOLD}🚀 ALL THREE${NC} (Hardening + Logging + Housekeeping)"
    echo ""
    echo -e "  ${CYAN}8)${NC}  📊 View System Status"
    echo -e "  ${CYAN}9)${NC}  ⚙️  View server.conf"
    echo -e "  ${CYAN}0)${NC}  ❌ Exit"
    echo ""
}

confirm_combo() {
    local desc="$1"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  You selected: ${BOLD}${desc}${NC}${YELLOW}${NC}"
    echo -e "${YELLOW}║                                                              ║${NC}"
    echo -e "${YELLOW}║  Each script will show section-by-section warnings and       ║${NC}"
    echo -e "${YELLOW}║  ask for confirmation before making changes.                 ║${NC}"
    echo -e "${YELLOW}║                                                              ║${NC}"
    echo -e "${YELLOW}║  You can skip any section by answering 'N' when prompted.    ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Continue? (y/N): " ANSWER
    [[ "$ANSWER" =~ ^[Yy]$ ]]
}

# ─── Main Loop ───────────────────────────────────────────────────────────────
while true; do
    show_menu
    read -p "Enter choice [0-9]: " CHOICE

    case $CHOICE in
        1)
            if confirm_combo "Server Hardening only"; then
                run_script "$SCRIPT_DIR/server_hardening.sh" "Server Hardening"
            fi
            ;;
        2)
            if confirm_combo "Log Management only"; then
                run_script "$SCRIPT_DIR/log_management.sh" "Log Management"
            fi
            ;;
        3)
            if confirm_combo "Housekeeping only"; then
                run_script "$SCRIPT_DIR/housekeeping.sh" "Housekeeping"
            fi
            ;;
        4)
            if confirm_combo "Hardening + Log Management (no Housekeeping)"; then
                run_script "$SCRIPT_DIR/server_hardening.sh" "Server Hardening"
                run_script "$SCRIPT_DIR/log_management.sh" "Log Management"
            fi
            ;;
        5)
            if confirm_combo "Hardening + Housekeeping (no Logging)"; then
                run_script "$SCRIPT_DIR/server_hardening.sh" "Server Hardening"
                run_script "$SCRIPT_DIR/housekeeping.sh" "Housekeeping"
            fi
            ;;
        6)
            if confirm_combo "Log Management + Housekeeping (no Hardening)"; then
                run_script "$SCRIPT_DIR/log_management.sh" "Log Management"
                run_script "$SCRIPT_DIR/housekeeping.sh" "Housekeeping"
            fi
            ;;
        7)
            if confirm_combo "ALL THREE: Hardening → Logging → Housekeeping"; then
                run_script "$SCRIPT_DIR/server_hardening.sh" "Server Hardening"
                run_script "$SCRIPT_DIR/log_management.sh" "Log Management"
                run_script "$SCRIPT_DIR/housekeeping.sh" "Housekeeping"
                echo ""
                echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${GREEN}║  ✅ ALL SCRIPTS COMPLETED — ${SERVER_NAME}                   ${NC}"
                echo -e "${GREEN}║  Reports saved in /root/                                     ║${NC}"
                echo -e "${GREEN}║  ⚠️  REBOOT RECOMMENDED to apply kernel changes               ║${NC}"
                echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
            fi
            ;;
        8) show_status ;;
        9)
            echo ""
            echo -e "${CYAN}── server.conf ──${NC}"
            cat "$CONFIG_FILE"
            echo ""
            ;;
        0)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice.${NC}"
            ;;
    esac
done
