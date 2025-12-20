#!/bin/bash

TESTPASSWORD="H4rdL1ghtPr0gr3ss!"
AUTHORIZED_FILE="authorized_users.txt"
EXCEPTIONS_FILE="exceptions.txt"

# Safety Checks
if [ ! -f "$AUTHORIZED_FILE" ]; then
	echo "ERROR: $AUTHORIZED_FILE not found!"
	exit 1
fi

if [ ! -f "$EXCEPTIONS_FILE" ]; then
	echo "ERROR: $EXCEPTIONS_FILE not found!"
	exit 1
fi

echo "=== Starting User Management Process ==="
echo

# Convert authorized + exceptions into arrays
mapfile -t AUTHORIZED < "$AUTHORIZED_FILE"
mapfile -t EXCEPTIONS < "$EXCEPTIONS_FILE"

# Combine exceptions into whitelist for easy checking
WHITELIST=("${AUTHORIZED[@]}" "${EXCEPTIONS[@]}")


# Part 1 - Reset Passwords for Authorized Users

echo "=== Resetting Passwords for Authorized Users ==="

for user in "${AUTHORIZED[@]}"; do
	# Skip root
	if [ "$user" = "root" ]; then
		echo "Skipping root"
		continue
	fi

	#Ensure users exists
	if id "$user" >/dev/null 2>&1; then
		echo -e "$TESTPASSWORD\n$TESTPASSWORD" | sudo passwd "$user"
		echo "Password reset for authorized user: $user"
	else
		echo "Authorized user '$user' does NOT exist - ignoring."
	fi
done

echo

# Part 2 - Disable Users not in Whitelist


echo "=== Identifying unauthorized users to disable ==="

# Get all human-Login users (UID >= 1000)

ALL_USERS=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)

UNAUTHORIZED=()

for user in $ALL_USERS; do
	# Check whitelist membership
	if printf '%s\n' "${WHITELIST[@]}" | grep -qx "$user"; then
		echo "User '$user' is authorized or excepted - keeping."
	else
		echo "User '$user' is NOT authorized - marking for disablement."
		UNAUTHORIZED+=("$user")
	fi
done

echo

# Part 3 - Disable Unauthorized Users

if [ ${#UNAUTHORIZED[@]} -eq 0 ]; then
	echo "No unauthorized users detected."
	exit 0
fi

echo "The following users will be DISABLED:"
printf ' %s\n' "${UNAUTHORIZED[@]}"

read -p "Proceed with disablement? (yes/no): " yn
if [ "$yn" != "yes" ]; then
	echo "Aborting disable operations."
	exit 0
fi

for user in "${UNAUTHORIZED[@]}"; do
	echo "Disabling user: $user"
	sudo usermod -L "$user"
	sudo passwd -l "$user"
	sudo usermod -s /user/sbin/nologin "$user"
	sudo usermod -e 1 "$user"
	echo "User '$user' has been disabled. "
done

echo "All Unauthorized users disabled."
echo "=== User Management Complete ==="
