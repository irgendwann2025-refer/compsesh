#!/bin/bash

AUTHORIZED_FILE="authorized_users.txt"
EXCEPTIONS_FILE="exceptions.txt"

echo "=== Generating User Whitelists ==="

# -------------------------------
# Identify current user
# -------------------------------
CURRENT_USER=$(whoami)

# -------------------------------
# Generate authorized users list
# UID >= 1000 and < 65534 = human users
# Excludes system/service accounts
# -------------------------------
echo "Collecting authorized users..."

awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd \
	| sort -u > "$AUTHORIZED_FILE"

# -------------------------------
# Generate exceptions list
# -------------------------------
echo "Creating exceptions list..."

{
	echo "root"
	echo "$CURRENT_USER"
} | sort -u > "$EXCEPTIONS_FILE"

# -------------------------------
# Output results
# -------------------------------
echo
echo "Authorized users written to: $AUTHORIZED_FILE"
cat "$AUTHORIZED_FILE"

echo
echo "Exceptions written to: $EXCEPTIONS_FILE"
cat "$EXCEPTIONS_FILE"

echo
echo "=== Whitelist Generation Complete ==="
