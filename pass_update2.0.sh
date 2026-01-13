#!/bin/bash

AUTHORIZED_FILE="authorized_users.txt"
EXCEPTIONS_FILE="exceptions.txt"

LOG_DIR="/var/log/user_mgmt"
USER_LOG_DIR="$LOG_DIR/users"
EXEC_LOG="$LOG_DIR/execution.log"
SUMMARY_LOG="$LOG_DIR/summary.log"

DRY_RUN=false

# -------------------------------
# Dry-run flag handling
# -------------------------------
if [[ "$1" == "-n" || "$1" == "--dry-run" ]]; then
	DRY_RUN=true
	echo "[DRY-RUN MODE ENABLED]"
fi

# -------------------------------
# Setup logging
# -------------------------------
sudo mkdir -p "$USER_LOG_DIR"
sudo touch "$EXEC_LOG" "$SUMMARY_LOG"
sudo chmod 750 "$LOG_DIR"
sudo chmod 640 "$EXEC_LOG" "$SUMMARY_LOG"

log_exec() {
	echo "$(date '+%F %T') | $1" | tee -a "$EXEC_LOG"
}

log_summary() {
	echo "$(date '+%F %T') | $1" | tee -a "$SUMMARY_LOG"
}

log_user() {
	local user="$1"
	local msg="$2"
	echo "$(date '+%F %T') | $msg" | sudo tee -a "$USER_LOG_DIR/$user.log" >/dev/null
}

# -------------------------------
# Safety Checks
# -------------------------------
for file in "$AUTHORIZED_FILE" "$EXCEPTIONS_FILE"; do
	if [ ! -f "$file" ]; then
		log_exec "ERROR: Missing file $file"
		exit 1
	fi
done

log_exec "=== User Management Script Started ==="

# -------------------------------
# Prompt for password (unless dry-run)
# -------------------------------
if [ "$DRY_RUN" = false ]; then
	read -s -p "Enter NEW password for authorized users: " NEW_PASSWORD
	echo
	read -s -p "Confirm NEW password: " CONFIRM_PASSWORD
	echo

	if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
		log_exec "ERROR: Password mismatch"
		exit 1
	fi
else
	NEW_PASSWORD="DRYRUN"
fi

# -------------------------------
# Load user lists
# -------------------------------
mapfile -t AUTHORIZED < "$AUTHORIZED_FILE"
mapfile -t EXCEPTIONS < "$EXCEPTIONS_FILE"
WHITELIST=("${AUTHORIZED[@]}" "${EXCEPTIONS[@]}")

# -------------------------------
# Reset passwords for authorized users
# -------------------------------
log_exec "Resetting passwords for authorized users"

for user in "${AUTHORIZED[@]}"; do
	if [ "$user" = "root" ]; then
		log_user "$user" "Skipped (root account)"
		continue
	fi

	if id "$user" >/dev/null 2>&1; then
		if [ "$DRY_RUN" = true ]; then
			log_user "$user" "DRY-RUN: Password would be reset"
		else
			echo -e "$NEW_PASSWORD\n$NEW_PASSWORD" | sudo passwd "$user" >/dev/null
			log_user "$user" "Password reset successfully"
		fi
	else
		log_user "$user" "User does not exist"
	fi
done

# -------------------------------
# Identify active users
# -------------------------------
log_exec "Identifying active users"

ACTIVE_USERS=()

while IFS=: read -r user _ uid _ _ _ shell; do
	if (( uid >= 1000 && uid < 65534 )); then
		if [[ ! "$shell" =~ (nologin|false)$ ]]; then
			if passwd -S "$user" 2>/dev/null | grep -q "P"; then
				ACTIVE_USERS+=("$user")
				log_user "$user" "Account is active"
			fi
		fi
	fi
done < /etc/passwd

# -------------------------------
# Identify unauthorized users
# -------------------------------
UNAUTHORIZED=()

for user in "${ACTIVE_USERS[@]}"; do
	if printf '%s\n' "${WHITELIST[@]}" | grep -qx "$user"; then
		log_user "$user" "Authorized or excepted"
	else
		UNAUTHORIZED+=("$user")
		log_user "$user" "Unauthorized – marked for disablement"
	fi
done

# -------------------------------
# Disable unauthorized users
# -------------------------------
if [ ${#UNAUTHORIZED[@]} -eq 0 ]; then
	log_summary "No unauthorized users detected"
	exit 0
fi

log_summary "Unauthorized users detected:"
printf ' - %s\n' "${UNAUTHORIZED[@]}" | tee -a "$SUMMARY_LOG"

if [ "$DRY_RUN" = true ]; then
	log_summary "DRY-RUN: No users were disabled"
	exit 0
fi

read -p "Proceed with disablement? (yes/no): " yn
if [ "$yn" != "yes" ]; then
	log_summary "Disablement aborted by administrator"
	exit 0
fi

for user in "${UNAUTHORIZED[@]}"; do
	sudo usermod -L "$user"
	sudo passwd -l "$user"
	sudo usermod -s /usr/sbin/nologin "$user"
	sudo usermod -e 1 "$user"
	log_user "$user" "Account disabled"
done

log_exec "All unauthorized users disabled"
log_summary "User management process completed"
