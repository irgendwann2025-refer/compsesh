#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)." 
   exit 1
fi

WHITELIST_FILE="/etc/managed_users.whitelist"
# Initialize or clear the whitelist and ensure root is always excluded
echo "root" > "$WHITELIST_FILE"

echo "=========================================="
echo "   User Account Management & Lockdown     "
echo "=========================================="

# PRE-FLIGHT: Show all current human users
echo -e "\n--- CURRENT SYSTEM USERS (UID >= 1000 & Root) ---"
printf "%-15s %-10s %-20s\n" "USER" "UID" "STATUS"
echo "--------------------------------------------------"
awk -F: '$3 == 0 || $3 >= 1000 {print $1, $3}' /etc/passwd | while read UNAME USER_ID; do
    # Check if account is locked/disabled in shadow file
    STATUS="Enabled"
    if sudo grep "^$UNAME:" /etc/shadow | cut -d: -f2 | grep -qE "^[!#*]"; then
        STATUS="DISABLED"
    fi
    printf "%-15s %-10s %-20s\n" "$UNAME" "$UID" "$STATUS"
done

while true; do
    echo -e "\n--- STAGE 1: IDENTIFY ACTION ---"
    echo "Actions: [A]dd New | [U]pdate Password | [E]nable Account | [F]inished"
    read -p "Select an action: " ACTION_TYPE

    TARGET_USER=""

    case $ACTION_TYPE in
        [Aa]*) # ADD USER
            read -p "Enter the name of the NEW user: " TARGET_USER
            if id "$TARGET_USER" &>/dev/null; then
                echo "[!] User already exists."
            else
                sudo useradd -m -s /bin/bash "$TARGET_USER"
                echo "[+] User $TARGET_USER created. Please set a password."
                sudo passwd "$TARGET_USER" && echo "$TARGET_USER" >> "$WHITELIST_FILE"
            fi
            ;;

        [Uu]*) # UPDATE PASSWORD
            read -p "Enter the name of the EXISTING user to update: " TARGET_USER
            if ! id "$TARGET_USER" &>/dev/null; then
                echo "[!] User $TARGET_USER does not exist."
            else
                sudo passwd "$TARGET_USER" && echo "$TARGET_USER" >> "$WHITELIST_FILE"
            fi
            ;;

        [Ee]*) # ENABLE ACCOUNT
            read -p "Enter the name of the DISABLED user to enable: " TARGET_USER
            if ! id "$TARGET_USER" &>/dev/null; then
                echo "[!] User $TARGET_USER does not exist."
            else
                echo "[*] Removing '#' or '!' lock from $TARGET_USER..."
                # Remove the '#' or '!' prefix from the shadow file
                sudo sed -i "s/^$TARGET_USER:[#!]\{1,2\}/$TARGET_USER:/" /etc/shadow
                # Unlock via usermod for safety
                sudo usermod -U "$TARGET_USER" 2>/dev/null
                echo "$TARGET_USER" >> "$WHITELIST_FILE"
                echo "[+] $TARGET_USER is now enabled and whitelisted."
            fi
            ;;

        [Ff]*) # FINISH
            break
            ;;

        *)
            echo "[!] Invalid selection."
            ;;
    esac
done

# FINAL STAGE: LOCKDOWN
echo -e "\n--- FINAL STAGE: SYSTEM LOCKDOWN ---"
echo "[*] Ensuring all non-whitelisted accounts are disabled..."

# Identify all human users
ALL_USERS=$(awk -F: '$3 == 0 || $3 >= 1000 {print $1}' /etc/passwd)



for USER in $ALL_USERS; do
    # Check if user is in whitelist
    if grep -Fxq "$USER" "$WHITELIST_FILE"; then
        echo "[SAFE] $USER is whitelisted."
    else
        # Only lock if not already locked to avoid double '#'
        if ! sudo grep "^$USER:" /etc/shadow | cut -d: -f2 | grep -q "^#"; then
            echo "[LOCK] Disabling $USER and prepending '#' to hash..."
            sudo sed -i "s/^$USER:\([^:]*\):/$USER:#\1:/" /etc/shadow
        else
            echo "[INFO] $USER is already locked."
        fi
    fi
done

echo -e "\n[DONE] Managed/Enabled Users: $(tr '\n' ',' < "$WHITELIST_FILE" | sed 's/,$//')"
echo "[DONE] Lockdown complete."
