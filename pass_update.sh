#!/bin/bash

# Configuration
TESTPASSWORD="H4rdL1ghtPr0gr3ss!"
WHITELIST_FILE="/etc/managed_users.whitelist"
EXCEPTIONS_FILE="exceptions.txt"

# 1. Safety & Permission Checks
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (sudo)." 
   exit 1
fi

# Ensure files exist to avoid script failure
if [[ ! -f "$WHITELIST_FILE" ]]; then
    echo "ERROR: $WHITELIST_FILE not found! Run the TUI manager first."
    exit 1
fi

if [[ ! -f "$EXCEPTIONS_FILE" ]]; then
    # Create an empty exceptions file if missing to prevent mapfile error
    touch "$EXCEPTIONS_FILE"
fi

echo "=== Starting Optimized User Management Process ==="

# 2. Build Total Whitelist
# We read the managed users (from your TUI) and the static exceptions
mapfile -t MANAGED < "$WHITELIST_FILE"
mapfile -t EXCEPTIONS < "$EXCEPTIONS_FILE"
TOTAL_WHITELIST=("${MANAGED[@]}" "${EXCEPTIONS[@]}")

# 3. Part 1: Reset Passwords for Managed Users
echo -e "\n=== Resetting Passwords for Managed Users ==="

for user in "${MANAGED[@]}"; do
    # STRICT EXCEPTION: Never change root password via this script
    if [[ "$user" == "root" ]]; then
        echo "[SKIP] root user protected."
        continue
    fi

    if id "$user" &>/dev/null; then
        # Update password using chpasswd (more reliable for automation)
        echo "$user:$TESTPASSWORD" | chpasswd
        echo "[DONE] Password updated: $user"
    else
        echo "[WARN] User '$user' in whitelist but not found on system."
    fi
done

# 4. Part 2: Lockdown Unauthorized Accounts
echo -e "\n=== Identifying and Disabling Unauthorized Users ==="

# Fetch all human users (UID >= 1000)
ALL_SYSTEM_USERS=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)

for system_user in $ALL_SYSTEM_USERS; do
    # Check if system_user exists in the TOTAL_WHITELIST
    is_authorized=false
    for auth_user in "${TOTAL_WHITELIST[@]}"; do
        if [[ "$system_user" == "$auth_user" ]]; then
            is_authorized=true
            break
        fi
    done

    if [ "$is_authorized" = true ]; then
        echo "[SAFE] $system_user is authorized/excepted."
    else
        echo "[LOCK] Disabling Unauthorized User: $system_user"
        
        # Performance: Combine all lock actions into one command
        # -L (Lock), -s (Shell change), -e 1 (Expire account)
        usermod -L -s /usr/sbin/nologin -e 1 "$system_user"
        
        # Security: Physically invalidate the hash in /etc/shadow
        sed -i "s/^$system_user:\([^:]*\):/$system_user:#\1:/" /etc/shadow
        
        echo "[DONE] $system_user has been locked and shell disabled."
    fi
done

echo -e "\n=== User Management Complete ==="
