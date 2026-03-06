# 🔐 Ubuntu Server Hardening, Log Management & Housekeeping

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20|%2022.04%20|%2024.04-orange?logo=ubuntu)](https://ubuntu.com)
[![Shell](https://img.shields.io/badge/Shell-Bash-blue?logo=gnu-bash)](https://www.gnu.org/software/bash/)

**Interactive, config-driven Bash scripts** for hardening, centralized log management, and automated housekeeping on Ubuntu on-premises servers.

- ✅ **One config file** (`server.conf`) — no script editing required
- ✅ **Per-section warnings** — shows exact impact before each change
- ✅ **User confirmation** — nothing runs without your approval
- ✅ **Docker-safe** — never deletes containers, images, or volumes
- ✅ **Selective execution** — run any script or section independently

---

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Project Structure](#-project-structure)
- [How It Works](#-how-it-works)
- [Configuration](#-configuration)
- [Scripts Overview](#-scripts-overview)
- [Service Inventory](#-service-inventory)
- [Centralized Logging](#-centralized-log-architecture)
- [Pre-Run Checklist](#-pre-run-checklist)
- [Verification](#-verification)
- [Rollback](#-rollback)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/<your-org>/ubuntu-server-scripts.git

# Copy to your server
scp -r ubuntu-server-scripts/ admin@your-server:~/

# SSH into the server
ssh admin@your-server

# Edit config for your environment
cd ~/ubuntu-server-scripts
nano server.conf

# Run
chmod +x *.sh
sudo bash setup_all.sh
```

---

## 📁 Project Structure

```
ubuntu-server-scripts/
├── server.conf            # Central config — ALL settings here
├── setup_all.sh           # Interactive menu (10 options)
├── server_hardening.sh    # Security hardening (11 sections)
├── log_management.sh      # Centralized logging (8 sections)
├── housekeeping.sh        # Cleanup & maintenance (10 sections)
├── README.md              # This file
├── LICENSE                # MIT License
└── .gitignore             # Git exclusions
```

---

## ⚙️ How It Works

### Three Levels of Control

| Level | How | Example |
|-------|-----|---------|
| **Config toggle** | Set `RUN_*="no"` in `server.conf` | `RUN_SSH_HARDENING="no"` → SSH section skipped |
| **Script selection** | Choose option 1–7 in `setup_all.sh` | Option 6 → Log Management + Housekeeping only |
| **Per-section prompt** | Answer `y/N` at each section | Skip firewall, keep SSH hardening |

### Menu Options (`setup_all.sh`)

| # | Runs |
|---|------|
| 1 | 🔐 Hardening only |
| 2 | 📋 Log Management only |
| 3 | 🧹 Housekeeping only |
| 4 | 🔐+📋 Hardening + Logging |
| 5 | 🔐+🧹 Hardening + Housekeeping |
| 6 | 📋+🧹 Logging + Housekeeping |
| 7 | 🚀 All three |
| 8 | 📊 System status |
| 9 | ⚙️ View config |
| 0 | ❌ Exit |

### Interactive Warnings

Every section shows exact impact before executing:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  3/11 — Firewall (UFW)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚠ IMPACT:
    • RESETS all existing UFW rules
    • Adds 14 port rules from server.conf
  🔴 RISK: Any port NOT listed will be BLOCKED!
  ⚠ SERVICES RESTARTED: ufw

  ➤ Proceed with Firewall? (y/N):
```

Set `INTERACTIVE_MODE="no"` in `server.conf` for automated/cron runs.

---

## ⚙️ Configuration

All settings live in **`server.conf`**. Key sections:

### SSH (Fully Dynamic)
```bash
SSH_PORTS="22,2222"
SSH_PERMIT_ROOT="no"
SSH_PASSWORD_AUTH="no"
SSH_MAX_AUTH_TRIES=3
SSH_IDLE_TIMEOUT=300
SSH_ALLOW_TCP_FORWARDING="no"
```

### Firewall Rules
```bash
FIREWALL_RULES=(
    "22/tcp:any:SSH"
    "3000/tcp:any:Grafana"
    "9090/tcp:any:Prometheus"
    "445/tcp:lan:Samba"         # LAN only
)
```

### Protected Services
```bash
PROTECTED_SERVICES=(
    "docker" "docker.socket" "containerd"
    "sshd" "grafana-server" "prometheus"
)
```

### Section Toggles
```bash
RUN_SYSTEM_UPDATES="yes"
RUN_SSH_HARDENING="yes"
RUN_FIREWALL="yes"
# Set any to "no" to skip
```

---

## 📜 Scripts Overview

### `server_hardening.sh` (11 Sections)

| # | Section | Key Changes |
|---|---------|-------------|
| 1 | System Updates | `apt upgrade`, unattended-upgrades |
| 2 | SSH Hardening | Ports, key-only auth, idle timeout |
| 3 | Firewall (UFW) | Dynamic rules from config |
| 4 | Fail2Ban | SSH brute-force protection |
| 5 | Kernel Security | sysctl hardening (IP forwarding kept for Docker) |
| 6 | Password Policy | Min length, complexity, aging |
| 7 | File Permissions | CIS-benchmark standard |
| 8 | Disable Services | avahi, cups, bluetooth |
| 9 | Audit Framework | auditd with comprehensive rules |
| 10 | Login Banner | Legal warning |
| 11 | Shared Memory | noexec mount |

### `log_management.sh` (8 Sections)

| # | Section | Key Changes |
|---|---------|-------------|
| 1 | Centralized Directory | `/var/log/centralized/` tree |
| 2 | Journald | 30-day retention, 2GB max |
| 3 | Rsyslog | Forward copies to centralized dir |
| 4 | Docker Logs | Auto-collect all container logs daily |
| 5 | Service Symlinks | Link grafana, prometheus, etc. |
| 6 | Logrotate | Dynamic rotation for all categories |
| 7 | Logwatch | Daily summary reports |
| 8 | Cron Jobs | Cleanup, collection, disk monitor |

### `housekeeping.sh` (10 Sections)

| # | Section | Key Changes |
|---|---------|-------------|
| 1 | Package Cleanup | autoremove, autoclean |
| 2 | Temp Files | `/tmp` files >7 days |
| 3 | Cache Cleanup | APT, pip, thumbnails |
| 4 | Journal Vacuum | Enforce 30-day limit |
| 5 | Old Kernels | Remove old, keep current |
| 6 | Docker Status | **READ-ONLY** — nothing deleted |
| 7 | Snap Cleanup | Old disabled revisions |
| 8 | Zombie Detection | Report only |
| 9 | Stale Files | Crash reports, core dumps |
| 10 | Disk Report + Cron | Usage report, weekly scheduling |

---

## 🔐 Service Inventory

| Port | Service | Firewall | Docker Cleanup |
|------|---------|----------|----------------|
| 22, 2222 | SSH | ✅ Open | N/A |
| 80, 443 | HTTP/HTTPS | ✅ Open | N/A |
| 3000 | Grafana | ✅ Open | ⛔ Never deleted |
| 3100 | Loki | ✅ Open | ⛔ Never deleted |
| 4954 | Trivy | ✅ Open | ⛔ Never deleted |
| 8000, 9000 | Docker VAPT | ✅ Open | ⛔ Never deleted |
| 9090 | Prometheus | ✅ Open | ⛔ Never deleted |
| 9093 | Alert Manager | ✅ Open | ⛔ Never deleted |
| 11434 | Ollama | ✅ Open | ⛔ Never deleted |
| 12345 | Alloy | ✅ Open | ⛔ Never deleted |
| 445 | Samba | ✅ LAN only | N/A |

---

## 📂 Centralized Log Architecture

```
/var/log/centralized/
├── system/        ← syslog, auth, kern, cron (rsyslog)
├── docker/        ← container logs (daily cron)
├── services/      ← grafana, prometheus, loki (symlinks)
├── security/      ← ufw, fail2ban, audit (symlinks)
└── applications/  ← custom app logs
```

---

## 🔴 Pre-Run Checklist

| # | Check | Command |
|---|-------|---------|
| 1 | SSH keys exist | `ls ~/.ssh/authorized_keys` |
| 2 | List running services | `sudo ss -tlnp` |
| 3 | List Docker containers | `docker ps -a` |
| 4 | Take VM snapshot | Before any changes |
| 5 | Console access ready | In case SSH breaks |
| 6 | Review server.conf | Verify all settings |

---

## ✅ Verification

```bash
sudo ufw status verbose                 # Firewall
sudo fail2ban-client status sshd        # Brute-force protection
sudo sshd -T | grep -E 'port|permit'   # SSH config
docker ps -a                             # Containers (untouched)
ls /var/log/centralized/                # Centralized logs
journalctl --disk-usage                 # Journal size
ls /etc/cron.daily/ /etc/cron.weekly/   # Automated jobs
```

---

## 🔄 Rollback

Backups are saved to `/root/hardening_backup_<timestamp>/`:

```bash
# Restore SSH config
cp /root/hardening_backup_*/sshd_config.bak /etc/ssh/sshd_config
systemctl restart sshd

# Disable firewall
sudo ufw disable

# Restore kernel params
cp /root/hardening_backup_*/sysctl.conf.bak /etc/sysctl.conf
rm /etc/sysctl.d/99-hardening.conf && sysctl --system
```

---

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/new-section`)
3. Edit `server.conf` for new settings — don't hardcode values in scripts
4. Test on a staging VM first
5. Submit a Pull Request

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
