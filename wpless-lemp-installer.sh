#!/bin/bash

LOG_FILE="/var/log/wpless-lemp-installer/sites.log"
INSTALL_LOG="/tmp/wpless-install.log"
export DEBIAN_FRONTEND=noninteractive

# ─────────────── UI HELPERS ───────────────
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

# ─────────────── LEMP INSTALL ───────────────
choose_php_version() {
    echo ""
    print_info "Choose PHP version:"
    select version in "8.0" "8.1" "8.2" "8.3" "Quit"; do
        case $version in
            8.*)
                PHP_VERSION=$version
                break
                ;;
            Quit)
                exit 0
                ;;
            *)
                print_warning "Invalid choice. Try again."
                ;;
        esac
    done
}

install_lemp_stack() {
    print_info "Installing LEMP Stack..."
    apt update -y >> "$INSTALL_LOG" 2>&1
    apt upgrade -y >> "$INSTALL_LOG" 2>&1

    choose_php_version

    apt install -y software-properties-common >> "$INSTALL_LOG" 2>&1
    add-apt-repository ppa:ondrej/php -y >> "$INSTALL_LOG" 2>&1
    apt update -y >> "$INSTALL_LOG" 2>&1

    apt install -y nginx mysql-server >> "$INSTALL_LOG" 2>&1

    apt install -y php$PHP_VERSION php$PHP_VERSION-fpm php$PHP_VERSION-mysql \
        php$PHP_VERSION-curl php$PHP_VERSION-gd php$PHP_VERSION-mbstring \
        php$PHP_VERSION-xml php$PHP_VERSION-xmlrpc php$PHP_VERSION-soap \
        php$PHP_VERSION-intl php$PHP_VERSION-zip unzip curl >> "$INSTALL_LOG" 2>&1

    apt install -y certbot python3-certbot-nginx >> "$INSTALL_LOG" 2>&1

    configure_php_ini
    print_success "LEMP Stack installed with PHP $PHP_VERSION"
}

configure_php_ini() {
    echo ""
    print_info "Set PHP limits (leave blank for defaults):"
    read -p "upload_max_filesize (default 256M): " upload_max
    read -p "post_max_size (default 256M): " post_max
    read -p "memory_limit (default 512M): " mem_limit
    read -p "max_execution_time (default 180): " exec_time

    upload_max=${upload_max:-256M}
    post_max=${post_max:-256M}
    mem_limit=${mem_limit:-512M}
    exec_time=${exec_time:-180}

    for ini in /etc/php/$PHP_VERSION/{cli,fpm}/php.ini; do
        sed -i "s/^upload_max_filesize = .*/upload_max_filesize = $upload_max/" "$ini"
        sed -i "s/^post_max_size = .*/post_max_size = $post_max/" "$ini"
        sed -i "s/^memory_limit = .*/memory_limit = $mem_limit/" "$ini"
        sed -i "s/^max_execution_time = .*/max_execution_time = $exec_time/" "$ini"
    done

    systemctl restart php$PHP_VERSION-fpm
}

# ─────────────── SITE SETUP ───────────────
install_site() {
    read -p "Enter domain name (e.g. example.com): " DOMAIN
    WP_DIR="/var/www/$DOMAIN"
    DB_NAME="wp_$(openssl rand -hex 4)"
    DB_USER="user_$(openssl rand -hex 4)"
    DB_PASS="$(openssl rand -base64 16)"

    # Create DB
    mysql -e "CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
    mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    print_success "MySQL Database and User created."

    # Download WordPress
    mkdir -p $WP_DIR
    cd /tmp && curl -sO https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    cp -a wordpress/. $WP_DIR
    cp $WP_DIR/wp-config-sample.php $WP_DIR/wp-config.php
    sed -i "s/database_name_here/$DB_NAME/" $WP_DIR/wp-config.php
    sed -i "s/username_here/$DB_USER/" $WP_DIR/wp-config.php
    sed -i "s/password_here/$DB_PASS/" $WP_DIR/wp-config.php
    SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    echo "$SALT" >> $WP_DIR/wp-config.php
    chown -R www-data:www-data $WP_DIR
    chmod -R 755 $WP_DIR

    # NGINX Config
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
    print_success "NGINX configured."

    # DNS Check
    check_dns || return

    # SSL Cert
    certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"
    [[ $? -eq 0 ]] && print_success "SSL installed!" || print_warning "SSL failed. Run: certbot --nginx -d $DOMAIN"

    # Log
    mkdir -p "$(dirname "$LOG_FILE")"
    {
        echo "Domain: $DOMAIN"
        echo "Directory: $WP_DIR"
        echo "DB Name: $DB_NAME"
        echo "DB User: $DB_USER"
        echo "Date: $(date)"
        echo "-----------------------------"
    } >> "$LOG_FILE"

    print_success "🎉 $DOMAIN is ready!"
    print_info "Visit: https://$DOMAIN to finish setup."
}

check_dns() {
    print_info "Checking DNS for $DOMAIN..."
    SERVER_IP=$(curl -s https://api.ipify.org)
    DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)

    if [[ "$DOMAIN_IP" == "$SERVER_IP" ]]; then
        print_success "$DOMAIN points to this server."
        return 0
    else
        print_warning "$DOMAIN does not point to this server (expected: $SERVER_IP, got: $DOMAIN_IP)"
        read -p "Continue anyway without SSL? (y/n): " CONT
        [[ "$CONT" != "y" ]] && return 1
    fi
}

# ─────────────── MAIN LOOP ───────────────
main() {
    show_banner
    install_lemp_stack

    while true; do
        divider
        install_site
        echo ""
        read -p "Install another site? (y/n): " AGAIN
        [[ "$AGAIN" != "y" ]] && break
    done

    print_info "📝 Site list: $LOG_FILE"
    print_success "🚀 All done!"
}

main
