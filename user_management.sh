#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)." 
   exit 1
fi

WHITELIST_FILE="/etc/managed_users.whitelist"
# Initialize or clear the whitelist
> "$WHITELIST_FILE"

# Pre-populate whitelist with 'root' to satisfy the exclusion requirement
echo "root" >> "$WHITELIST_FILE"

echo "=========================================="
echo "   User Account Management & Lockdown     "
echo "=========================================="

while true; do
    echo -e "\n--- STAGE 1: IDENTIFY ACTION ---"
    read -p "Do you want to (A)dd a new user or (U)pdate an existing one? [A/U]: " ACTION_TYPE

    TARGET_USER=""

    if [[ "$ACTION_TYPE" =~ ^[Aa]$ ]]; then
        read -p "Enter the name of the NEW user: " TARGET_USER
        if id "$TARGET_USER" &>/dev/null; then
            echo "[!] User already exists. Switching to Update mode."
        else
            sudo useradd -m -s /bin/bash "$TARGET_USER"
            echo "[+] User $TARGET_USER created."
        fi
    elif [[ "$ACTION_TYPE" =~ ^[Uu]$ ]]; then
        read -p "Enter the name of the EXISTING user to update: " TARGET_USER
        if ! id "$TARGET_USER" &>/dev/null; then
            echo "[!] User $TARGET_USER does not exist."
            continue
        fi
    else
        echo "[!] Invalid input. Please choose A or U."
        continue
    fi

    # STAGE 2: UPDATE PASSWORD
    echo -e "\n--- STAGE 2: PASSWORD UPDATE ---"
    if [[ "$TARGET_USER" == "root" ]]; then
        echo "[!] Security Policy: Root password should be managed via standard sudo passwd."
    else
        echo "Updating password for: $TARGET_USER"
        sudo passwd "$TARGET_USER"
        
        # Add to whitelist if successful
        if [[ $? -eq 0 ]]; then
            echo "$TARGET_USER" >> "$WHITELIST_FILE"
            echo "[+] $TARGET_USER added to whitelist."
        fi
    fi

    # STAGE 3: CHECK FINISHED
    echo -e "\n--- STAGE 3: STATUS CHECK ---"
    read -p "Are you finished updating accounts? [Y/N]: " FINISHED
    if [[ "$FINISHED" =~ ^[Yy]$ ]]; then
        break
    fi
done

# FINAL ACTION: LOCKDOWN UNMANAGED USERS
echo -e "\n--- FINAL STAGE: SYSTEM LOCKDOWN ---"
echo "[*] Identifying accounts not in whitelist..."

# Get all real users (UID >= 1000) plus root, excluding system service accounts
ALL_USERS=$(awk -F: '$3 == 0 || $3 >= 1000 {print $1}' /etc/passwd)

for USER in $ALL_USERS; do
    # Check if user is in whitelist
    if grep -Fxq "$USER" "$WHITELIST_FILE"; then
        echo "[SAFE] $USER is whitelisted."
    else
        echo "[LOCK] Disabling $USER and hashing password..."
        # The 'usermod -L' command prepends '!' or '#' to the shadow file hash
        sudo usermod -L "$USER"
        # Manual hash modification to ensure it begins with '#'
        sudo sed -i "s/^$USER:\([^:]*\):/$USER:#\1:/" /etc/shadow
    fi
done

echo -e "\n[SUCCESS] Managed users: $(tr '\n' ',' < "$WHITELIST_FILE")"
echo "[SUCCESS] All other accounts have been disabled with '#' hash prefix."
