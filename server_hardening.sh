#!/bin/bash
###############################################################################
# Ubuntu Server Hardening Script — v3 (Interactive + Fully Dynamic)
# ─────────────────────────────────────────────────────────────────────────────
# • Shows WARNING before each section with exact impact
# • Asks "Continue? (y/N)" before executing each section
# • Every setting read from server.conf — nothing hardcoded
# • Sections can be skipped via config or interactive prompt
# Usage : sudo bash server_hardening.sh
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
REPORT_FILE="/root/hardening_report_$(date +%Y%m%d_%H%M%S).txt"
BACKUP_DIR="/root/hardening_backup_$(date +%Y%m%d_%H%M%S)"
SKIPPED_SECTIONS=()

# ─── Load Config ─────────────────────────────────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi
source "$CONFIG_FILE"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)."
    exit 1
fi
if ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
    log_error "This script is designed for Ubuntu only."
    exit 1
fi

# ─── Confirmation Helper ────────────────────────────────────────────────────
confirm_section() {
    local section_name="$1"
    local config_flag="$2"

    # Check config flag first
    if [[ "${!config_flag}" != "yes" ]]; then
        echo -e "${DIM}  [SKIPPED by config: ${config_flag}=no]${NC}"
        SKIPPED_SECTIONS+=("$section_name (config)")
        return 1
    fi

    # If not interactive, auto-proceed
    if [[ "${INTERACTIVE_MODE}" != "yes" ]]; then
        return 0
    fi

    echo ""
    read -p "  ➤ Proceed with ${section_name}? (y/N): " ANSWER
    if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}  [SKIPPED by user]${NC}"
        SKIPPED_SECTIONS+=("$section_name (user)")
        return 1
    fi
    return 0
}

is_protected() {
    local svc="$1"
    for protected in "${PROTECTED_SERVICES[@]}"; do
        [[ "$svc" == "$protected" ]] && return 0
    done
    return 1
}

# ─── Master Warning Banner ──────────────────────────────────────────────────
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ${BOLD}⚠️  SERVER HARDENING — ${SERVER_NAME}${NC}${RED}                        ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  This script will make the following changes:               ║${NC}"
echo -e "${RED}║                                                              ║${NC}"
echo -e "${RED}║  • Upgrade ALL system packages                              ║${NC}"
echo -e "${RED}║  • Change SSH config (ports: ${SSH_PORTS})                   ${NC}"
echo -e "${RED}║  • Password auth: ${SSH_PASSWORD_AUTH}, Root login: ${SSH_PERMIT_ROOT}                ║${NC}"
echo -e "${RED}║  • RESET firewall, add ${#FIREWALL_RULES[@]} port rules               ║${NC}"
echo -e "${RED}║  • Install & configure Fail2Ban                             ║${NC}"
echo -e "${RED}║  • Apply kernel security parameters                         ║${NC}"
echo -e "${RED}║  • Enforce password policies (${PASS_MIN_LEN}-char, ${PASS_MAX_DAYS}-day)              ║${NC}"
echo -e "${RED}║  • Tighten file permissions                                 ║${NC}"
echo -e "${RED}║  • Disable: ${SERVICES_TO_DISABLE[*]}                       ${NC}"
echo -e "${RED}║  • Install audit framework (auditd)                         ║${NC}"
echo -e "${RED}║  • Set login warning banner                                 ║${NC}"
echo -e "${RED}║                                                              ║${NC}"
echo -e "${RED}║  📁 Backups saved to: /root/hardening_backup_*/             ║${NC}"
echo -e "${RED}║  📄 Report saved to: /root/hardening_report_*.txt           ║${NC}"
echo -e "${RED}║                                                              ║${NC}"
echo -e "${RED}║  ${BOLD}Each section will ask for confirmation before executing.${NC}${RED}    ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "${INTERACTIVE_MODE}" == "yes" ]]; then
    read -p "Start server hardening? (y/N): " START
    if [[ ! "$START" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Aborted by user.${NC}"
        exit 0
    fi
fi

mkdir -p "$BACKUP_DIR"
echo "Server Hardening Report — $(date)" > "$REPORT_FILE"
echo "Server: ${SERVER_NAME} | Mode: ${INTERACTIVE_MODE}" >> "$REPORT_FILE"
echo "========================================" >> "$REPORT_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# 1. SYSTEM UPDATES
# ─────────────────────────────────────────────────────────────────────────────
log_section "1/11 — System Updates"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Runs: apt-get update + upgrade (upgrades ALL packages)"
echo "    • Installs: unattended-upgrades"
echo "    • Creates: /etc/apt/apt.conf.d/20auto-upgrades"
echo -e "${YELLOW}  ⚠ RISK:${NC} Package updates could change versions of running software"
echo -e "${YELLOW}  ⚠ SERVICES RESTARTED:${NC} None immediately, some after reboot"

if confirm_section "System Updates" "RUN_SYSTEM_UPDATES"; then
    log_info "Updating package lists..."
    apt-get update -y >> "$REPORT_FILE" 2>&1
    log_info "Upgrading installed packages..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$REPORT_FILE" 2>&1
    apt-get install -y unattended-upgrades apt-listchanges >> "$REPORT_FILE" 2>&1
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
    log_info "✅ System updates & auto-upgrades configured."
    echo "[DONE] System updates" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. SSH HARDENING
# ─────────────────────────────────────────────────────────────────────────────
log_section "2/11 — SSH Hardening"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • MODIFIES: /etc/ssh/sshd_config"
echo "    • SSH Ports: ${SSH_PORTS}"
echo "    • Root Login: ${SSH_PERMIT_ROOT}"
echo "    • Password Auth: ${SSH_PASSWORD_AUTH}"
echo "    • PubKey Auth: ${SSH_PUBKEY_AUTH}"
echo "    • X11 Forwarding: ${SSH_X11_FORWARDING}"
echo "    • Max Auth Tries: ${SSH_MAX_AUTH_TRIES}"
echo "    • Idle Timeout: ${SSH_IDLE_TIMEOUT}s × ${SSH_IDLE_COUNT_MAX} = $((SSH_IDLE_TIMEOUT * SSH_IDLE_COUNT_MAX))s total"
echo "    • TCP Forwarding: ${SSH_ALLOW_TCP_FORWARDING}"
echo "    • Agent Forwarding: ${SSH_ALLOW_AGENT_FORWARDING}"
echo -e "${RED}  🔴 RISK: If SSH keys are NOT set up and password auth is disabled,"
echo -e "           you will be LOCKED OUT of the server!${NC}"
echo -e "${YELLOW}  ⚠ SERVICES RESTARTED:${NC} sshd"
echo -e "${YELLOW}  ⚠ BACKUP:${NC} /root/hardening_backup_*/sshd_config.bak"

if confirm_section "SSH Hardening" "RUN_SSH_HARDENING"; then
    SSHD_CONFIG="/etc/ssh/sshd_config"
    cp "$SSHD_CONFIG" "$BACKUP_DIR/sshd_config.bak"
    log_info "Backed up sshd_config"

    set_ssh_config() {
        local key="$1" value="$2"
        if grep -qE "^\s*#?\s*${key}\s" "$SSHD_CONFIG"; then
            sed -i "s|^\s*#\?\s*${key}\s.*|${key} ${value}|" "$SSHD_CONFIG"
        else
            echo "${key} ${value}" >> "$SSHD_CONFIG"
        fi
    }

    # All from config — fully dynamic
    set_ssh_config "PermitRootLogin"          "${SSH_PERMIT_ROOT}"
    set_ssh_config "PasswordAuthentication"   "${SSH_PASSWORD_AUTH}"
    set_ssh_config "PubkeyAuthentication"     "${SSH_PUBKEY_AUTH}"
    set_ssh_config "PermitEmptyPasswords"     "${SSH_PERMIT_EMPTY_PASSWORDS}"
    set_ssh_config "X11Forwarding"            "${SSH_X11_FORWARDING}"
    set_ssh_config "MaxAuthTries"             "${SSH_MAX_AUTH_TRIES}"
    set_ssh_config "ClientAliveInterval"      "${SSH_IDLE_TIMEOUT}"
    set_ssh_config "ClientAliveCountMax"      "${SSH_IDLE_COUNT_MAX}"
    set_ssh_config "LoginGraceTime"           "${SSH_LOGIN_GRACE_TIME}"
    set_ssh_config "AllowAgentForwarding"     "${SSH_ALLOW_AGENT_FORWARDING}"
    set_ssh_config "AllowTcpForwarding"       "${SSH_ALLOW_TCP_FORWARDING}"
    set_ssh_config "Protocol"                 "${SSH_PROTOCOL}"
    set_ssh_config "LogLevel"                 "${SSH_LOG_LEVEL}"

    # Dynamic SSH ports
    sed -i '/^\s*Port\s/d' "$SSHD_CONFIG"
    IFS=',' read -ra SSH_PORT_ARRAY <<< "$SSH_PORTS"
    for port in "${SSH_PORT_ARRAY[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        echo "Port $port" >> "$SSHD_CONFIG"
        log_info "SSH port: $port"
    done

    systemctl restart sshd || systemctl restart ssh
    log_info "✅ SSH hardened with all settings from server.conf"
    echo "[DONE] SSH hardening (ports: ${SSH_PORTS})" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. FIREWALL
# ─────────────────────────────────────────────────────────────────────────────
log_section "3/11 — Firewall (UFW)"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • RESETS all existing UFW rules"
echo "    • Default: DENY incoming, ALLOW outgoing"
echo "    • Adds ${#FIREWALL_RULES[@]} port rules:"
for rule in "${FIREWALL_RULES[@]}"; do
    IFS=':' read -r port_proto access comment <<< "$rule"
    echo "      ✓ ${port_proto} — ${comment} (${access})"
done
echo -e "${RED}  🔴 RISK: Any port NOT listed above will be BLOCKED!${NC}"
echo -e "${RED}  🔴 RISK: Brief disruption during reset (existing connections survive)${NC}"
echo -e "${YELLOW}  ⚠ SERVICES RESTARTED:${NC} ufw"

if confirm_section "Firewall" "RUN_FIREWALL"; then
    apt-get install -y ufw >> "$REPORT_FILE" 2>&1
    ufw --force reset >> "$REPORT_FILE" 2>&1
    ufw default deny incoming
    ufw default allow outgoing

    for rule in "${FIREWALL_RULES[@]}"; do
        IFS=':' read -r port_proto access comment <<< "$rule"
        if [[ "$access" == "any" ]]; then
            ufw allow "$port_proto" comment "$comment" >> "$REPORT_FILE" 2>&1
            log_info "  ✅ ${port_proto} (${comment}) — anywhere"
        elif [[ "$access" == "lan" ]]; then
            for network in "${TRUSTED_NETWORKS[@]}"; do
                port_num=$(echo "$port_proto" | cut -d'/' -f1)
                ufw allow from "$network" to any port "$port_num" comment "${comment}-${network}" >> "$REPORT_FILE" 2>&1
            done
            log_info "  ✅ ${port_proto} (${comment}) — LAN only"
        fi
    done

    echo "y" | ufw enable
    ufw reload
    log_info "✅ UFW configured with ${#FIREWALL_RULES[@]} rules."
    echo "[DONE] UFW firewall" >> "$REPORT_FILE"
    ufw status numbered >> "$REPORT_FILE" 2>&1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. FAIL2BAN
# ─────────────────────────────────────────────────────────────────────────────
log_section "4/11 — Fail2Ban"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Installs: fail2ban package"
echo "    • Creates/overwrites: /etc/fail2ban/jail.local"
echo "    • SSH ports monitored: ${SSH_PORTS}"
echo "    • Ban after ${SSH_MAX_AUTH_TRIES} failed attempts for 1 hour"
echo -e "${YELLOW}  ⚠ RISK:${NC} Wrong password ${SSH_MAX_AUTH_TRIES}x = your IP banned 1 hour"
echo -e "${YELLOW}  ⚠ SERVICES RESTARTED:${NC} fail2ban"

if confirm_section "Fail2Ban" "RUN_FAIL2BAN"; then
    apt-get install -y fail2ban >> "$REPORT_FILE" 2>&1
    IFS=',' read -ra SSH_PORT_ARRAY <<< "$SSH_PORTS"
    SSH_PORTS_CSV=$(IFS=','; echo "${SSH_PORT_ARRAY[*]}" | tr -d ' ')
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = ${SSH_MAX_AUTH_TRIES}
banaction = ufw

[sshd]
enabled  = true
port     = ${SSH_PORTS_CSV}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = ${SSH_MAX_AUTH_TRIES}
bantime  = 3600
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban
    log_info "✅ Fail2Ban protecting SSH on ports ${SSH_PORTS_CSV}"
    echo "[DONE] Fail2Ban" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. KERNEL SECURITY
# ─────────────────────────────────────────────────────────────────────────────
log_section "5/11 — Kernel & Network Security"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Creates: /etc/sysctl.d/99-hardening.conf"
echo "    • IP Forwarding: KEPT ${KEEP_IP_FORWARDING} (Docker needs this)"
echo "    • SYN Cookies: ${ENABLE_SYN_COOKIES}"
echo "    • ICMP Redirect Block: ${DISABLE_ICMP_REDIRECTS}"
echo "    • ASLR: ${ENABLE_ASLR}"
echo "    • Martian Logging: ${LOG_MARTIAN_PACKETS}"
echo -e "${YELLOW}  ⚠ BACKUP:${NC} /root/hardening_backup_*/sysctl.conf.bak"
echo -e "${YELLOW}  ⚠ RISK:${NC} Low — these are standard security parameters"

if confirm_section "Kernel Security" "RUN_KERNEL_SECURITY"; then
    cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.bak"
    if [[ "${KEEP_IP_FORWARDING}" == "yes" ]]; then
        IP_FWD=1
    else
        IP_FWD=0
    fi

    cat > /etc/sysctl.d/99-hardening.conf <<EOF
# Auto-generated — ${SERVER_NAME} — $(date)
net.ipv4.ip_forward = ${IP_FWD}
net.ipv6.conf.all.forwarding = 0
$(if [[ "${DISABLE_ICMP_REDIRECTS}" == "yes" ]]; then
echo "net.ipv4.conf.all.accept_redirects = 0"
echo "net.ipv4.conf.default.accept_redirects = 0"
echo "net.ipv4.conf.all.send_redirects = 0"
echo "net.ipv4.conf.default.send_redirects = 0"
echo "net.ipv6.conf.all.accept_redirects = 0"
echo "net.ipv6.conf.default.accept_redirects = 0"
fi)
$(if [[ "${ENABLE_SYN_COOKIES}" == "yes" ]]; then
echo "net.ipv4.tcp_syncookies = 1"
echo "net.ipv4.tcp_max_syn_backlog = 2048"
echo "net.ipv4.tcp_synack_retries = 2"
fi)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
$(if [[ "${LOG_MARTIAN_PACKETS}" == "yes" ]]; then
echo "net.ipv4.conf.all.log_martians = 1"
echo "net.ipv4.conf.default.log_martians = 1"
fi)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
fs.suid_dumpable = 0
$(if [[ "${ENABLE_ASLR}" == "yes" ]]; then
echo "kernel.randomize_va_space = 2"
fi)
EOF
    sysctl --system >> "$REPORT_FILE" 2>&1
    log_info "✅ Kernel security applied."
    echo "[DONE] Kernel hardening" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. PASSWORD POLICY
# ─────────────────────────────────────────────────────────────────────────────
log_section "6/11 — Password Policy"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • MODIFIES: /etc/login.defs"
echo "    • Max password age: ${PASS_MAX_DAYS} days"
echo "    • Min password age: ${PASS_MIN_DAYS} days"
echo "    • Warning before expiry: ${PASS_WARN_AGE} days"
echo "    • Min password length: ${PASS_MIN_LEN} characters"
echo "    • Installs: libpam-pwquality"
echo "    • MODIFIES: /etc/security/pwquality.conf"
echo "    • MODIFIES: /etc/pam.d/su (adds wheel restriction)"
echo "    • Locks new accounts after 30 days inactive"
echo -e "${YELLOW}  ⚠ RISK:${NC} Users must use ${PASS_MIN_LEN}-char passwords on next change"
echo -e "${YELLOW}  ⚠ BACKUP:${NC} login.defs.bak, pwquality.conf.bak"

if confirm_section "Password Policy" "RUN_PASSWORD_POLICY"; then
    cp /etc/login.defs "$BACKUP_DIR/login.defs.bak"
    sed -i "s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   ${PASS_MAX_DAYS}/"  /etc/login.defs
    sed -i "s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   ${PASS_MIN_DAYS}/"  /etc/login.defs
    sed -i "s/^PASS_WARN_AGE.*/PASS_WARN_AGE   ${PASS_WARN_AGE}/"  /etc/login.defs
    sed -i "s/^PASS_MIN_LEN.*/PASS_MIN_LEN    ${PASS_MIN_LEN}/"    /etc/login.defs
    apt-get install -y libpam-pwquality >> "$REPORT_FILE" 2>&1
    if [ -f /etc/security/pwquality.conf ]; then
        cp /etc/security/pwquality.conf "$BACKUP_DIR/pwquality.conf.bak"
        cat > /etc/security/pwquality.conf <<EOF
minlen = ${PASS_MIN_LEN}
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
maxrepeat = 3
reject_username
enforce_for_root
EOF
    fi
    if ! grep -q "pam_wheel.so" /etc/pam.d/su 2>/dev/null; then
        sed -i '/pam_rootok.so/a auth required pam_wheel.so use_uid group=sudo' /etc/pam.d/su
    fi
    useradd -D -f 30
    log_info "✅ Password policy enforced."
    echo "[DONE] Password policy" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7. FILE PERMISSIONS
# ─────────────────────────────────────────────────────────────────────────────
log_section "7/11 — File Permissions"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • /etc/passwd → 644 | /etc/shadow → 600"
echo "    • /etc/gshadow → 600 | /etc/group → 644"
echo "    • /root → 700 | /boot/grub/grub.cfg → 600"
echo "    • /etc/crontab → 600 | /etc/cron.* dirs → 700"
echo -e "${YELLOW}  ⚠ RISK:${NC} Low — standard CIS benchmark permissions"

if confirm_section "File Permissions" "RUN_FILE_PERMISSIONS"; then
    chmod 644 /etc/passwd
    chmod 600 /etc/shadow
    chmod 600 /etc/gshadow
    chmod 644 /etc/group
    chmod 700 /root
    chmod 600 /boot/grub/grub.cfg 2>/dev/null || true
    chmod 600 /etc/crontab
    chmod 700 /etc/cron.d
    chmod 700 /etc/cron.daily
    chmod 700 /etc/cron.weekly
    chmod 700 /etc/cron.monthly
    chmod 700 /etc/cron.hourly
    log_info "✅ File permissions secured."
    echo "[DONE] File permissions" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 8. DISABLE SERVICES
# ─────────────────────────────────────────────────────────────────────────────
log_section "8/11 — Disable Unnecessary Services"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Will STOP and DISABLE these services:"
for svc in "${SERVICES_TO_DISABLE[@]}"; do
    status=$(systemctl is-active "$svc" 2>/dev/null || echo "not found")
    echo "      • $svc (currently: $status)"
done
echo "    • Will BLACKLIST: usb-storage kernel module"
echo -e "${GREEN}  ✅ PROTECTED (never touched):${NC} ${PROTECTED_SERVICES[*]}"
echo -e "${YELLOW}  ⚠ RISK:${NC} Low — these services are not needed on servers"

if confirm_section "Disable Services" "RUN_DISABLE_SERVICES"; then
    for svc in "${SERVICES_TO_DISABLE[@]}"; do
        if is_protected "$svc"; then
            log_warn "SKIP: $svc is PROTECTED!"
            echo "[SKIP] $svc — protected" >> "$REPORT_FILE"
            continue
        fi
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl stop "$svc"
            systemctl disable "$svc"
            log_info "Disabled: $svc"
            echo "[DISABLED] $svc" >> "$REPORT_FILE"
        elif systemctl list-unit-files | grep -q "$svc" 2>/dev/null; then
            systemctl disable "$svc" 2>/dev/null || true
            log_info "Ensured disabled: $svc"
        else
            log_info "Not installed: $svc"
            echo "[SKIP] $svc — not installed" >> "$REPORT_FILE"
        fi
    done
    cat > /etc/modprobe.d/disable-usb-storage.conf <<'EOF'
blacklist usb-storage
install usb-storage /bin/true
EOF
    log_info "✅ Services disabled, USB storage blocked."
    echo "[DONE] Service disable" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 9. AUDIT FRAMEWORK
# ─────────────────────────────────────────────────────────────────────────────
log_section "9/11 — Audit Framework (auditd)"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Installs: auditd, audispd-plugins"
echo "    • Creates: /etc/audit/rules.d/hardening.rules"
echo "    • Monitors: passwd, shadow, sudoers, sshd_config, cron, Docker"
echo "    • Rules are IMMUTABLE after load (need reboot to change)"
echo -e "${YELLOW}  ⚠ RISK:${NC} Low — read-only monitoring, doesn't block anything"
echo -e "${YELLOW}  ⚠ SERVICES RESTARTED:${NC} auditd"

if confirm_section "Audit Framework" "RUN_AUDITD"; then
    apt-get install -y auditd audispd-plugins >> "$REPORT_FILE" 2>&1
    cat > /etc/audit/rules.d/hardening.rules <<'EOF'
-D
-b 8192
-w /etc/passwd     -p wa -k identity
-w /etc/shadow     -p wa -k identity
-w /etc/group      -p wa -k identity
-w /etc/gshadow    -p wa -k identity
-w /etc/sudoers    -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/crontab    -p wa -k cron
-w /etc/cron.d/    -p wa -k cron
-w /var/spool/cron -p wa -k cron
-w /var/log/auth.log   -p wa -k auth_log
-w /var/log/faillog    -p wa -k login_failures
-w /var/log/lastlog    -p wa -k login_records
-w /var/log/wtmp       -p wa -k session
-w /var/run/utmp       -p wa -k session
-w /etc/hosts       -p wa -k network_config
-w /etc/hostname    -p wa -k network_config
-w /etc/resolv.conf -p wa -k network_config
-w /etc/docker/               -p wa -k docker_config
-w /var/lib/docker/           -p wa -k docker_data
-w /usr/bin/docker            -p x  -k docker_cmd
-w /usr/bin/docker-compose    -p x  -k docker_cmd
-w /etc/ufw/                  -p wa -k firewall_config
-w /sbin/insmod   -p x -k modules
-w /sbin/rmmod    -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S open -S openat -F exit=-EACCES -k access_denied
-a always,exit -F arch=b64 -S open -S openat -F exit=-EPERM  -k access_denied
-e 2
EOF
    systemctl enable auditd
    systemctl restart auditd
    augenrules --load 2>/dev/null || true
    log_info "✅ Audit framework configured."
    echo "[DONE] auditd" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 10. LOGIN BANNER
# ─────────────────────────────────────────────────────────────────────────────
log_section "10/11 — Login Warning Banner"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Overwrites: /etc/issue, /etc/issue.net"
echo "    • Adds: Banner directive to sshd_config"
echo "    • Displays legal warning before login"
echo -e "${YELLOW}  ⚠ RISK:${NC} None — cosmetic change only"
echo -e "${YELLOW}  ⚠ SERVICES RESTARTED:${NC} sshd"

if confirm_section "Login Banner" "RUN_LOGIN_BANNER"; then
    cat > /etc/issue <<EOF
***************************************************************************
*                        AUTHORIZED ACCESS ONLY                           *
*         Server: ${SERVER_NAME}                                          *
*                                                                         *
*  Unauthorized access is prohibited. All activities are monitored.       *
*  By accessing this system, you consent to having your actions recorded. *
***************************************************************************
EOF
    cp /etc/issue /etc/issue.net

    SSHD_CONFIG="/etc/ssh/sshd_config"
    if grep -qE "^\s*#?\s*Banner\s" "$SSHD_CONFIG"; then
        sed -i "s|^\s*#\?\s*Banner\s.*|Banner /etc/issue.net|" "$SSHD_CONFIG"
    else
        echo "Banner /etc/issue.net" >> "$SSHD_CONFIG"
    fi
    systemctl restart sshd || systemctl restart ssh
    log_info "✅ Login banner set."
    echo "[DONE] Login banner" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 11. SHARED MEMORY
# ─────────────────────────────────────────────────────────────────────────────
log_section "11/11 — Secure Shared Memory"
echo -e "${YELLOW}  ⚠ IMPACT:${NC}"
echo "    • Adds line to /etc/fstab (if not present)"
echo "    • Mounts /run/shm with noexec,nosuid,nodev"
echo -e "${YELLOW}  ⚠ RISK:${NC} Low — prevents code execution in shared memory"

if confirm_section "Shared Memory" "RUN_SHARED_MEMORY"; then
    if ! grep -q '/run/shm' /etc/fstab; then
        echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
        log_info "✅ Shared memory secured."
    else
        log_info "Already configured."
    fi
    echo "[DONE] Shared memory" >> "$REPORT_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
log_section "Hardening Complete — ${SERVER_NAME}"

echo "" >> "$REPORT_FILE"
echo "Completed at: $(date)" >> "$REPORT_FILE"
echo "Backup: $BACKUP_DIR" >> "$REPORT_FILE"

echo ""
log_info "✅ Server hardening completed for ${SERVER_NAME}!"
log_info "📄 Report: $REPORT_FILE"
log_info "💾 Backups: $BACKUP_DIR"

if [ ${#SKIPPED_SECTIONS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Skipped sections:${NC}"
    for s in "${SKIPPED_SECTIONS[@]}"; do
        echo "  • $s"
    done
    echo "Skipped: ${SKIPPED_SECTIONS[*]}" >> "$REPORT_FILE"
fi
echo ""
log_warn "⚠️  Reboot recommended to apply kernel changes."
echo ""
