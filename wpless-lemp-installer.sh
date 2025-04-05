#!/bin/bash

LOG_FILE="/var/log/wpless-lemp-installer/sites.log"

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
    echo -e "\033[1;36m         WPLess LEMP + WordPress Installer\033[0m"
    divider
}

# ────────────────────────────────
# 🔧 Install LEMP Stack
# ────────────────────────────────
install_lemp_stack() {
    print_info "Updating and installing LEMP stack..."
    
    apt update -y >/dev/null && apt upgrade -y >/dev/null

    read -p "Enter desired PHP version (e.g. 8.1, 8.2): " PHP_VERSION
    apt install -y software-properties-common >/dev/null
    add-apt-repository ppa:ondrej/php -y >/dev/null
    apt update -y >/dev/null

    apt install nginx mysql-server -y >/dev/null
    apt install -y php$PHP_VERSION php$PHP_VERSION-fpm php$PHP_VERSION-mysql php$PHP_VERSION-curl php$PHP_VERSION-gd php$PHP_VERSION-mbstring php$PHP_VERSION-xml php$PHP_VERSION-xmlrpc php$PHP_VERSION-soap php$PHP_VERSION-intl php$PHP_VERSION-zip unzip curl >/dev/null
    apt install -y certbot python3-certbot-nginx >/dev/null

    configure_php_ini

    print_success "LEMP stack installed with PHP $PHP_VERSION."
}

configure_php_ini() {
    echo ""
    print_info "Configure PHP settings (recommended shown in brackets):"

    read -p "upload_max_filesize (256M): " upload_max
    read -p "post_max_size (256M): " post_max
    read -p "memory_limit (512M): " mem_limit
    read -p "max_execution_time (180): " exec_time

    upload_max=${upload_max:-256M}
    post_max=${post_max:-256M}
    mem_limit=${mem_limit:-512M}
    exec_time=${exec_time:-180}

    for INI in /etc/php/$PHP_VERSION/{cli,fpm}/php.ini; do
        sed -i "s/^upload_max_filesize = .*/upload_max_filesize = $upload_max/" "$INI"
        sed -i "s/^post_max_size = .*/post_max_size = $post_max/" "$INI"
        sed -i "s/^memory_limit = .*/memory_limit = $mem_limit/" "$INI"
        sed -i "s/^max_execution_time = .*/max_execution_time = $exec_time/" "$INI"
    done

    systemctl restart php$PHP_VERSION-fpm
    print_success "PHP settings updated for CLI and FPM."
}

# ────────────────────────────────
# 🐬 Database Setup
# ────────────────────────────────
generate_db_creds() {
    DB_NAME="wp_$(openssl rand -hex 4)"
    DB_USER="user_$(openssl rand -hex 4)"
    DB_PASS="$(openssl rand -base64 16)"
}

create_database() {
    mysql -e "CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
    mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}

# ────────────────────────────────
# 🌐 NGINX Config
# ────────────────────────────────
configure_nginx() {
    cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    root $WP_DIR;

    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/ 2>/dev/null
    nginx -t && systemctl reload nginx
    print_success "Nginx configured for $DOMAIN"
}

# ────────────────────────────────
# ⚙️ WordPress Setup
# ────────────────────────────────
install_wordpress() {
    mkdir -p $WP_DIR
    cd /tmp
    curl -s -O https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    cp -a wordpress/. $WP_DIR
    chown -R www-data:www-data $WP_DIR
    chmod -R 755 $WP_DIR

    cp $WP_DIR/wp-config-sample.php $WP_DIR/wp-config.php
    sed -i "s/database_name_here/$DB_NAME/" $WP_DIR/wp-config.php
    sed -i "s/username_here/$DB_USER/" $WP_DIR/wp-config.php
    sed -i "s/password_here/$DB_PASS/" $WP_DIR/wp-config.php

    SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    echo "$SALT" >> $WP_DIR/wp-config.php

    print_success "WordPress downloaded and configured."
}

# ────────────────────────────────
# 🔎 DNS Check
# ────────────────────────────────
check_dns() {
    print_info "Checking DNS for $DOMAIN..."
    SERVER_IP=$(curl -s https://api.ipify.org)
    DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)

    if [[ "$DOMAIN_IP" == "$SERVER_IP" ]]; then
        print_success "$DOMAIN is pointing to this server [$SERVER_IP]"
    else
        print_warning "$DOMAIN does not point to this server!"
        print_info "→ Your server IP is: $SERVER_IP"
        print_info "⚠️  Please update DNS A record before SSL generation."
        read -p "Continue anyway? (y/n): " DNS_CONT
        [[ "$DNS_CONT" != "y" ]] && return 1
    fi
}

# ────────────────────────────────
# 🔐 SSL Setup
# ────────────────────────────────
generate_ssl() {
    print_info "Attempting SSL certificate installation for $DOMAIN..."
    
    certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"
    
    if [[ $? -ne 0 ]]; then
        print_warning "SSL installation failed for $DOMAIN"
        echo "❗ Domain verification failed. Most likely due to missing or incorrect DNS records."

        read -p "Would you like to retry SSL installation (after fixing DNS)? (y/n): " RETRY_SSL
        if [[ "$RETRY_SSL" == "y" ]]; then
            certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"
            [[ $? -ne 0 ]] && print_error "❌ SSL failed again. Try manually: certbot --nginx -d $DOMAIN" || print_success "✅ SSL reinstalled."
        else
            print_warning "⚠️ Skipping SSL installation. You can run this later: certbot --nginx -d $DOMAIN"
        fi
    else
        print_success "✅ SSL certificate installed for $DOMAIN"
    fi
}

# ────────────────────────────────
# 📝 Log Site Details
# ────────────────────────────────
log_site_config() {
    mkdir -p "$(dirname "$LOG_FILE")"
    {
        echo "Site: $DOMAIN"
        echo "Directory: $WP_DIR"
        echo "Database Name: $DB_NAME"
        echo "Database User: $DB_USER"
        echo "Date: $(date)"
        echo "----------------------------"
    } >> "$LOG_FILE"
}

# ────────────────────────────────
# 🚀 Install One Site
# ────────────────────────────────
install_site() {
    read -p "Enter domain name (e.g. example.com): " DOMAIN
    WP_DIR="/var/www/$DOMAIN"
    generate_db_creds
    create_database
    install_wordpress
    configure_nginx

    if ! check_dns; then
        print_error "Aborting install for $DOMAIN due to DNS mismatch."
        return
    fi

    generate_ssl
    log_site_config

    echo ""
    print_success "✅ WordPress site installed!"
    print_info "👉 Visit: https://$DOMAIN to complete installation in browser."
}

# ────────────────────────────────
# 🔁 Loop for Multiple Installs
# ────────────────────────────────
main() {
    show_banner
    install_lemp_stack

    while true; do
        divider
        install_site
        echo ""
        read -p "Would you like to install another site? (y/n): " CHOICE
        [[ "$CHOICE" != "y" ]] && break
    done

    print_info "📝 All installed sites logged at: $LOG_FILE"
    print_success "🎉 Done! Enjoy your new WordPress setup!"
}

main
