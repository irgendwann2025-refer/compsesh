#!/bin/bash
# =========================================================
# Script Name: secure_mysql.sh
# Purpose: Secure MySQL Database with best practices
# OS: Ubuntu / Debian
# =========================================================

set -e

echo "==========================================="
echo " MySQL Security Hardening Script"
echo "==========================================="

# -------------------------------
# Variables
# -------------------------------
MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"
BACKUP_DIR="/var/backups/mysql"
TIMESTAMP=$(date +"%F_%H-%M-%S")

# -------------------------------
# Prompt for MySQL root password
# -------------------------------
echo
read -s -p "Enter current MySQL root password: " MYSQL_ROOT_PASS
echo
read -s -p "Enter NEW MySQL root password: " MYSQL_NEW_ROOT_PASS
echo
read -s -p "Confirm NEW MySQL root password: " MYSQL_NEW_ROOT_PASS_CONFIRM
echo

if [[ "$MYSQL_NEW_ROOT_PASS" != "$MYSQL_NEW_ROOT_PASS_CONFIRM" ]]; then
  echo "❌ Passwords do not match. Exiting."
  exit 1
fi

# -------------------------------
# Update MySQL to latest version
# -------------------------------
echo "🔄 Updating MySQL packages..."
apt update
apt install -y mysql-server

# -------------------------------
# Remove unnecessary users
# -------------------------------
echo "🧹 Removing anonymous and remote root users..."
mysql -u root -p"$MYSQL_ROOT_PASS" <<EOF
USE mysql;
DELETE FROM user WHERE User='';
DELETE FROM user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;
EOF

# -------------------------------
# Set strong root password
# -------------------------------
echo "🔐 Setting strong MySQL root password..."
mysql -u root -p"$MYSQL_ROOT_PASS" <<EOF
ALTER USER 'root'@'localhost'
IDENTIFIED WITH caching_sha2_password
BY '${MYSQL_NEW_ROOT_PASS}';
FLUSH PRIVILEGES;
EOF

# -------------------------------
# Limit network access
# -------------------------------
echo "🌐 Restricting MySQL network access..."
sed -i "s/^bind-address.*/bind-address = 127.0.0.1/" "$MYSQL_CONF"

if ! grep -q "^skip-networking" "$MYSQL_CONF"; then
  echo "skip-networking" >> "$MYSQL_CONF"
fi

# -------------------------------
# Enable SSL/TLS
# -------------------------------
echo "🔒 Enabling SSL/TLS configuration..."
cat <<EOF >> "$MYSQL_CONF"

# SSL Configuration
ssl-ca=/etc/mysql/ssl/ca.pem
ssl-cert=/etc/mysql/ssl/server-cert.pem
ssl-key=/etc/mysql/ssl/server-key.pem
EOF

# -------------------------------
# Enable auditing and logging
# -------------------------------
echo "📝 Enabling MySQL logging..."
cat <<EOF >> "$MYSQL_CONF"

# Logging
general_log = 1
general_log_file = /var/log/mysql/mysql.log
log_error = /var/log/mysql/error.log
EOF

# -------------------------------
# Restart MySQL
# -------------------------------
echo "🔁 Restarting MySQL service..."
systemctl restart mysql

# -------------------------------
# Backup all databases
# -------------------------------
echo "💾 Creating MySQL backup..."
mkdir -p "$BACKUP_DIR"
mysqldump -u root -p"$MYSQL_NEW_ROOT_PASS" --all-databases \
  > "$BACKUP_DIR/mysql_backup_$TIMESTAMP.sql"

# Verify backup integrity
if [[ -s "$BACKUP_DIR/mysql_backup_$TIMESTAMP.sql" ]]; then
  echo "✅ Backup successful and verified."
else
  echo "❌ Backup failed or empty."
  exit 1
fi

# -------------------------------
# Configure Firewall (UFW)
# -------------------------------
echo "🔥 Configuring firewall..."
ufw allow ssh
ufw allow from 127.0.0.1 to any port 3306
ufw --force enable

# -------------------------------
# Monitoring Information
# -------------------------------
echo
echo "📊 Monitoring Commands:"
echo "  MySQL Activity Log:  tail -f /var/log/mysql/mysql.log"
echo "  MySQL Error Log:     tail -f /var/log/mysql/error.log"

echo
echo "==========================================="
echo " ✅ MySQL security hardening completed"
echo "==========================================="
