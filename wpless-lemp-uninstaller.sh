#!/bin/bash

# ────────────────────────────────
# 🎨 UI Helpers
# ────────────────────────────────
print_success() { echo -e "\033[1;32m✔ $1\033[0m"; }
print_warning() { echo -e "\033[1;33m➜ $1\033[0m"; }
print_error()   { echo -e "\033[1;31m✖ $1\033[0m"; }
print_info()    { echo -e "\033[1;36m$1\033[0m"; }
divider()       { echo -e "\033[1;34m───────────────────────────────────────────────\033[0m"; }

show_banner() {
    clear
    echo -e "\033[1;35m"
    echo ' __        _______ ____                  _           _           _ '
    echo ' \ \      / / ____|  _ \   ___ _ __ ___ (_)_ __   __| | ___ _ __| |'
    echo '  \ \ /\ / /|  _| | |_) | / __|  _ ` _ \| |  _ \ / _` |/ _ \  __| |'
    echo '   \ V  V / | |___|  __/ | (__| | | | | | | | | | (_| |  __/ |  |_|'
    echo '    \_/\_/  |_____|_|     \___|_| |_| |_|_|_| |_|\__,_|\___|_|  (_)' 
    echo -e "\033[0m"
    divider
    echo -e "\033[1;36m      WPLess LEMP + WordPress Uninstaller\033[0m"
    divider
}

# ────────────────────────────────
# 🔥 Uninstaller Function
# ────────────────────────────────
uninstall_stack() {
    divider
    print_warning "⚠️  This will remove Nginx, MySQL, PHP, Certbot, all site files and logs!"
    read -p "Are you sure you want to uninstall everything and reset the system? (y/n): " CONFIRM
    CONFIRM=${CONFIRM,,} # convert to lowercase

    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "yes" ]]; then
        print_info "Stopping services..."
        systemctl stop nginx mysql php* >/dev/null 2>&1

        print_info "Removing packages..."
        apt purge --autoremove -y nginx mysql-server php* certbot python3-certbot-nginx >/dev/null

        print_info "Deleting configuration and data..."
        rm -rf /etc/nginx /etc/mysql /etc/php /etc/letsencrypt
        rm -rf /var/www/* /var/log/nginx /var/log/mysql /var/log/wpless-lemp-installer

        print_success "✅ LEMP stack, WordPress sites, and logs removed successfully!"
    else
        print_info "❌ Uninstallation cancelled."
    fi
}

# ────────────────────────────────
# 🚀 Run Script
# ────────────────────────────────
show_banner
uninstall_stack
