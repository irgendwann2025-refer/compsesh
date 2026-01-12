#!/bin/bash

# --- 1. Configuration Variables ---
# Replace these with you actual IPs
JUMPBOX_IP="192.168.1.50"
TRUSTED_SUBNET="192.168.40.0/24"
ADMIN_IP="192.168.20.10"

echo "Starting Firewall Configuration..."

# --- 2. Reset Rules ---
# Flush all existing rules to start clean
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t mangle -F

# Set default policies to ACCEPT temporarily (prevents lockout during script run)
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# --- 3. Basic Protection ---
# Allow loopback (localhost)
sudo iptables -A INPUT -i to -j ACCEPT

# Allow established connections (Critical for keeping current SSH Session alive)
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Drop Bogons / Invalid IPs
sudo iptables -A INPUT -s 224.0.0.0/4 -j DROP
sudo iptables -A INPUT -d 224.0.0.0/4 -j DROP
sudo iptables -A INPUT -s 240.0.0.0/5 -j DROP

# --- 4. Whitelisting ---
# Trust internal subnet and Jumpbox
sudo iptables -A INPUT -s $TRUSTED_SUBNET -j ACCEPT
sudo iptables -A INPUT -s $JUMPBOX_IP -j ACCEPT

# --- 5. Honeyport & Scanning ---
# Log and Drop Port Scanners (e.g., targeting port 139)
sudo iptables -A INPUT -p tcp --dport 139 -m recent --name portscan --set -j LOG --log-prefix "PortScan: "
sudo iptables -A INPUT -p tcp --dport 139 -m recent --name portscan --set -j DROP

# Check if IP is in the "portscan" list (banned for 24 hours)
sudo iptables -A INPUT -m recent --name portscan --rcheck --seconds 86400 -j DROP

# --- 6. Services (SSH, Web, DNS) ---
# Allow SSH only from specific IPs
sudo iptables -A INPUT -p tcp --dport 22 -s $JUMPBOX_IP -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -s $ADMIN_IP -j ACCEPT

# Allow Web
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# --- 7. Final Closure ---
# Log dropped packets (Optional, can fill logs quickly)
# sudo iptables -A INPUT -j LOG --log-prefix "Final Drop: "

# Set Default Policy to DROP (The "Wall")
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
# Usually keep OUTPUT ACCEPT unless high security is needed
sudo iptables -P OUTPUT ACCEPT

# --- 8. Save & Persist ---
echo "Saving rules..."
if command -v iptables-save &> /dev/null; then
	sudo iptables-save > /etc/iptables/rules.v4
	echo "Rules saved to desired folder"
fi

echo "Firewall configured successfully."

