#!/bin/bash

echo "🚨 This will uninstall LEMP, remove all WordPress sites installed via wpless-lemp-installer, and purge MySQL databases."
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
[[ "$CONFIRM" != "yes" ]] && echo "❌ Cancelled." && exit 1

# ─────────────────────────────
# 💀 Stop Services
# ─────────────────────────────
echo "🛑 Stopping services..."
systemctl stop nginx
systemctl stop mysql
systemctl stop php*-fpm

# ─────────────────────────────
# 🔥 Purge LEMP Packages
# ─────────────────────────────
echo "🧹 Purging LEMP stack..."
apt purge -y nginx nginx-common nginx-full mysql-server mysql-common php* certbot python3-certbot-nginx
apt autoremove -y
apt autoclean -y

# ─────────────────────────────
# 📁 Remove WordPress Sites
# ─────────────────────────────
echo "🗑 Removing WordPress site files..."
rm -rf /var/www/*

# ─────────────────────────────
# 🔌 Clean NGINX Configs
# ─────────────────────────────
echo "🧼 Removing NGINX site configs..."
rm -rf /etc/nginx/sites-available/*
rm -rf /etc/nginx/sites-enabled/*

# ─────────────────────────────
# 🗃 Drop MySQL Databases/Users
# ─────────────────────────────
echo "💣 Dropping MySQL databases and users created by WPLess..."

# Extract DB Names and Users from logs
LOG_PATH="/var/log/wpless-lemp-installer/sites.log"
if [[ -f "$LOG_PATH" ]]; then
    grep -oP '(?<=DB Name: ).*' "$LOG_PATH" | while read -r db; do
        mysql -e "DROP DATABASE IF EXISTS \`$db\`;"
        echo "🗑 Dropped database: $db"
    done

    grep -oP '(?<=DB User: ).*' "$LOG_PATH" | while read -r user; do
        mysql -e "DROP USER IF EXISTS '$user'@'localhost';"
        echo "🗑 Dropped user: $user"
    done
fi

# ─────────────────────────────
# 🧾 Clean WPLess Logs
# ─────────────────────────────
echo "🧽 Removing WPLess logs..."
rm -rf /var/log/wpless-lemp-installer

# ─────────────────────────────
# 🔄 Reload System Services
# ─────────────────────────────
echo "🔁 Reloading system services..."
systemctl daemon-reexec

# ─────────────────────────────
# ✅ Done
# ─────────────────────────────
echo "✅ Uninstall complete. Your Ubuntu is now LEMP-free and clean!"
