#!/bin/bash

# === Styled Output ===
print_success() { echo -e "\033[1;32m✔ $1\033[0m"; }
print_warning() { echo -e "\033[1;33m➜ $1\033[0m"; }
print_error()   { echo -e "\033[1;31m✖ $1\033[0m"; }
print_info()    { echo -e "\033[1;36m$1\033[0m"; }
divider()       { echo -e "\033[1;34m───────────────────────────────────────────────\033[0m"; }

# === Banner ===
show_banner() {
  echo -e "\033[1;35m"
  cat << "EOF"
██     ██ ██████  ██      ███████ ███████ ███████ 
██     ██ ██   ██ ██      ██      ██      ██      
██  █  ██ ██████  ██      █████   ███████ ███████ 
██ ███ ██ ██      ██      ██           ██      ██ 
 ███ ███  ██      ███████ ███████ ███████ ███████ 
EOF
  echo -e "\033[1;36m         🚀 WPLess WP Installer 🚀\033[0m"
  divider
}

# === Prompt Functions ===
ask_stack() {
  echo "Choose your stack:"
  select stack in "LEMP (Nginx)" "LAMP (Apache)"; do
    case $REPLY in
      1) STACK="lemp"; break;;
      2) STACK="lamp"; break;;
      *) print_warning "Invalid option.";;
    esac
  done
}

ask_sql() {
  echo "Choose your database engine:"
  select sql in "MySQL" "MariaDB"; do
    case $REPLY in
      1) SQL="mysql"; break;;
      2) SQL="mariadb"; break;;
      *) print_warning "Invalid option.";;
    esac
  done
}

ask_php_version() {
  echo "Choose PHP version:"
  select php in "8.2" "8.1" "8.0"; do
    PHP_VERSION=$php
    break
  done
}

ask_upload_limits() {
  read -p "Set PHP upload_max_filesize (e.g., 256M): " PHP_UPLOAD
  read -p "Set PHP memory_limit (e.g., 256M): " PHP_MEMORY
}

ask_domain() {
  read -p "Enter your domain (e.g., example.com): " DOMAIN
  SITE_DIR="/var/www/$DOMAIN"
}

# === Installation Functions ===
install_stack() {
  print_info "Installing packages..."
  apt update
  if [ "$STACK" == "lemp" ]; then
    apt install -y nginx
  else
    apt install -y apache2
  fi
}

install_php() {
  add-apt-repository ppa:ondrej/php -y && apt update
  apt install -y php$PHP_VERSION php$PHP_VERSION-{fpm,mysql,cli,common,xml,gd,curl,mbstring,zip}
}

configure_php() {
  ini_file=$(php -i | grep "Loaded Configuration File" | awk '{print $5}')
  sed -i "s/upload_max_filesize = .*/upload_max_filesize = $PHP_UPLOAD/" $ini_file
  sed -i "s/memory_limit = .*/memory_limit = $PHP_MEMORY/" $ini_file
  print_success "PHP limits configured."
}

install_mysql() {
  if [ "$SQL" == "mysql" ]; then
    apt install -y mysql-server
  else
    apt install -y mariadb-server
  fi
  systemctl start mysql
  systemctl enable mysql
}

generate_db() {
  DB_NAME=$(openssl rand -hex 4)
  DB_USER=$(openssl rand -hex 4)
  DB_PASS=$(openssl rand -hex 8)
  mysql -e "CREATE DATABASE $DB_NAME;"
  mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
  mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"
  print_success "Database created: $DB_NAME"
}

install_wordpress() {
  mkdir -p $SITE_DIR
  cd /tmp && curl -O https://wordpress.org/latest.tar.gz
  tar -xzf latest.tar.gz
  cp -r wordpress/* $SITE_DIR
  chown -R www-data:www-data $SITE_DIR
  cp $SITE_DIR/wp-config-sample.php $SITE_DIR/wp-config.php
  sed -i "s/database_name_here/$DB_NAME/" $SITE_DIR/wp-config.php
  sed -i "s/username_here/$DB_USER/" $SITE_DIR/wp-config.php
  sed -i "s/password_here/$DB_PASS/" $SITE_DIR/wp-config.php
  print_success "WordPress installed at $SITE_DIR"
}

configure_vhost() {
  if [ "$STACK" == "lemp" ]; then
    cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
  listen 80;
  server_name $DOMAIN;
  root $SITE_DIR;
  index index.php index.html;

  location / {
    try_files \$uri \$uri/ /index.php?$args;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
  }

  location ~ /\.ht {
    deny all;
  }
}
EOF
    ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
  else
    cat > /etc/apache2/sites-available/$DOMAIN.conf <<EOF
<VirtualHost *:80>
  ServerName $DOMAIN
  DocumentRoot $SITE_DIR
  <Directory $SITE_DIR>
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF
    a2ensite $DOMAIN.conf
    a2enmod rewrite
    systemctl reload apache2
  fi
  print_success "Vhost configured."
}

setup_ssl() {
  if ! command -v certbot >/dev/null; then apt install -y certbot python3-certbot-${STACK}; fi
  certbot --$STACK -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN || {
    print_error "SSL failed. Retry? (y/n)"
    read retry
    [ "$retry" == "y" ] && certbot --$STACK -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
  }
}

final_output() {
  divider
  print_success "WordPress site installed at: http://$DOMAIN"
  print_info "DB Name: $DB_NAME"
  print_info "DB User: $DB_USER"
  print_info "DB Pass: $DB_PASS"
  divider
}

ask_install_another() {
  read -p "Install another site? (y/n): " again
  [ "$again" == "y" ] && exec $0
}

# === MAIN ===
show_banner
ask_stack
ask_sql
ask_php_version
ask_upload_limits
ask_domain

install_stack
install_php
configure_php
install_mysql
generate_db
install_wordpress
configure_vhost
setup_ssl
final_output
ask_install_another
