#!/bin/bash
# NIST-Based Linux System Enumeration Script
# Gathers inventory, configuration, and security-relevant details for auditing.
 
# --- Configuration ---
LOG_FILE="./nist_enumeration_report_$(hostname)_$(date +%Y%m%d).txt"
DELIMITER="========================================================================="
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
 
# Redirect all output to the log file and also display on screen (tee)
exec > >(tee -i "$LOG_FILE") 2>&1
 
echo -e "${GREEN}--- NIST-BASED LINUX SYSTEM ENUMERATION REPORT ---${NC}"
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo $DELIMITER
 
# ==============================================================================
# 1. SYSTEM & SOFTWARE INVENTORY (NIST CM-8: Information System Component Inventory)
# ==============================================================================
echo -e "\n${YELLOW}### 1. SYSTEM INVENTORY (CM-8) ###${NC}"
echo $DELIMITER
 
# a. Operating System Details
echo "[1.a] Operating System / Distribution:"
cat /etc/os-release
echo ""
 
# b. Kernel Version and Architecture
echo "[1.b] Kernel Version and Architecture:"
uname -a
echo ""
 
# c. Installed Packages (Partial List - full list can be extremely long)
echo "[1.c] Top 20 Recently Installed Packages:"
if command -v dpkg &> /dev/null; then
    # Debian/Ubuntu
    echo "Using dpkg (Debian/Ubuntu)..."
    dpkg-query -W --showformat='${Installed-Time}\t${Package}\n' | sort -nr | head -n 20 | awk '{print strftime("%Y-%m-%d %H:%M:%S", $1), $2}'
elif command -v rpm &> /dev/null; then
    # Red Hat/CentOS/Fedora
    echo "Using rpm (RHEL/CentOS/Fedora)..."
    rpm -qa --queryformat '%{INSTALLTIME} %{NAME}\n' | sort -nr | head -n 20 | awk '{print strftime("%Y-%m-%d %H:%M:%S", $1), $2}'
else
    echo "Package manager not recognized (dpkg or rpm missing)."
fi
echo ""
 
# ==============================================================================
# 2. USER AND ACCOUNT MANAGEMENT (NIST AC-2: Account Management)
# ==============================================================================
echo -e "\n${YELLOW}### 2. USER & ACCOUNT MANAGEMENT (AC-2) ###${NC}"
echo $DELIMITER
 
# a. All User Accounts
echo "[2.a] All System and Local User Accounts (Username:UID:GID:HomeDir:Shell):"
# Filter out common service accounts (UID < 1000) for a cleaner list of human users
awk -F: '($3>=1000) {print $1 ":" $3 ":" $4 ":" $6 ":" $7}' /etc/passwd | column -t -s :
echo ""
 
# b. Sudoers (Users with elevated privileges)
echo "[2.b] Users with Sudo Permissions (via 'sudo -l -U' and /etc/group):"
# 1. Check common admin groups (wheel/sudo)
if grep -qE "^(sudo|wheel):" /etc/group; then
    # Determine the correct administrative group
    if grep -q "^sudo:" /etc/group; then
        ADMIN_GROUP="sudo"
    else
        ADMIN_GROUP="wheel"
    fi
    echo "Members of the '$ADMIN_GROUP' group:"
    getent group "$ADMIN_GROUP" | cut -d: -f4 | sed 's/,/\n/g'
else
    echo "No standard 'sudo' or 'wheel' group found."
fi
 
# 2. Check /etc/sudoers file for custom rules (using visudo -c to check syntax)
echo -e "\nCustom Sudoers Entries (from /etc/sudoers and /etc/sudoers.d/):"
# Attempt to safely read the sudoers file (requires root/sudo)
if [ -r "/etc/sudoers" ]; then
    grep -E '^(User_Alias|Cmnd_Alias|Defaults|[^#].*ALL)' /etc/sudoers /etc/sudoers.d/* 2>/dev/null
else
    echo "Cannot read /etc/sudoers (Requires root access)."
fi
echo ""
 
# ==============================================================================
# 3. NETWORK AND COMMUNICATIONS (NIST SC-7: Boundary Protection)
# ==============================================================================
echo -e "\n${YELLOW}### 3. NETWORK & COMMUNICATIONS (SC-7) ###${NC}"
echo $DELIMITER
 
# a. Active Listening Ports (Potential services/vulnerabilities)
echo "[3.a] Active Listening Ports (Protocol, Address, Program/User):"
if command -v ss &> /dev/null; then
    ss -tulnp
else
    netstat -tulnp
fi
echo ""
 
# b. Firewall Status
echo "[3.b] Firewall Status (iptables/nftables/firewalld):"
if command -v iptables &> /dev/null; then
    sudo iptables -L -n 
elif command -v firewall-cmd &> /dev/null; then
    sudo firewall-cmd --list-all
else
    echo "Firewall command (iptables/firewall-cmd) not found or requires root."
fi
echo ""
 
# ==============================================================================
# 4. LOGGING & AUDITING (NIST AU-3: Content of Audit Records)
# ==============================================================================
echo -e "\n${YELLOW}### 4. LOGGING & AUDITING (AU-3) ###${NC}"
echo $DELIMITER
 
# a. Log Configuration
echo "[4.a] System Log Configuration (rsyslog/journald):"
if [ -f "/etc/rsyslog.conf" ]; then
    grep -E '^\*\.(info|notice|warning|err|crit|emerg)' /etc/rsyslog.conf
elif command -v journalctl &> /dev/null; then
    echo "System uses systemd-journald."
fi
echo ""
 
# b. Auditd Status (if installed)
echo "[4.b] Auditd Status (Check for security auditing service):"
if systemctl is-active --quiet auditd; then
    echo "Auditd Service is Active. Key configuration files (e.g., /etc/audit/audit.rules) should be checked manually."
else
    echo "Auditd Service is NOT running."
fi
echo ""
 
 
# ==============================================================================
# 5. SCHEDULED TASKS / PERSISTENCE (NIST CM-6: Configuration Settings)
# ==============================================================================
echo -e "\n${YELLOW}### 5. SCHEDULED TASKS / PERSISTENCE (CM-6) ###${NC}"
echo $DELIMITER
 
# a. System-wide Crontabs
echo "[5.a] System-wide Crontab Entries (/etc/cron*):"
grep -vE '^(#|$)' /etc/crontab /etc/cron.d/* /etc/cron.{daily,hourly,weekly,monthly}/* 2>/dev/null
echo ""
 
# b. User Crontabs
echo "[5.b] Active User Crontabs (Requires root access to enumerate all):"
# This requires sudo/root access to check all user crontabs
for user in $(awk -F: '($3>=1000) {print $1}' /etc/passwd); do
    if sudo crontab -l -u "$user" 2>/dev/null; then
        echo "--- Crontab for user: $user ---"
        sudo crontab -l -u "$user"
    fi
done
 
echo $DELIMITER
echo -e "${GREEN}--- REPORT COMPLETE. Saved to $LOG_FILE ---${NC}"
