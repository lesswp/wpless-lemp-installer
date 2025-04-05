#!/bin/bash

set -e

function show_banner() {
cat << "EOF"

██     ██ ██████  ██      ███████ ███████ ███████ 
██     ██ ██   ██ ██      ██      ██      ██      
██  █  ██ ██████  ██      █████   ███████ ███████ 
██ ███ ██ ██      ██      ██           ██      ██ 
 ███ ███  ██      ███████ ███████ ███████ ███████ 

         🚀 WPLess WP Installer 🚀

EOF
}


# === Helper: show progress ===
function show_progress() {
  echo -ne "$1\r"
  sleep 0.5
}

# === Ask user for options ===
function ask_stack() {
  echo "Choose stack:"
  select opt in "LEMP (Nginx)" "LAMP (Apache)"; do
    case $REPLY in
      1) STACK="LEMP"; break ;;
      2) STACK="LAMP"; break ;;
    esac
  done
}

function ask_sql() {
  echo "Choose database:"
  select opt in "MySQL" "MariaDB"; do
    case $REPLY in
      1) SQL_SERVER="MySQL"; break ;;
      2) SQL_SERVER="MariaDB"; break ;;
    esac
  done
}

function ask_php_version() {
  echo "Choose PHP version:"
  select opt in "7.4" "8.0" "8.1" "8.2"; do
    PHP_VERSION="$opt"
    break
  done
}

function ask_upload_limits() {
  read -p "Enter upload_max_filesize (default 64M): " PHP_UPLOAD
  PHP_UPLOAD=${PHP_UPLOAD:-64M}
  read -p "Enter memory_limit (default 256M): " PHP_MEMORY
  PHP_MEMORY=${PHP_MEMORY:-256M}
}

function ask_domain() {
  read -p "Enter domain or subdomain (e.g. site.com or blog.site.com): " DOMAIN
  DOMAIN_DIR="/var/www/$DOMAIN"
  sudo mkdir -p "$DOMAIN_DIR"
}

# === Installation: Web server ===
function install_stack() {
  sudo apt update
  if [[ $STACK == "LEMP" ]]; then
    sudo apt install -y nginx
  else
    sudo apt install -y apache2
  fi
  show_progress "✅ Web server installed."
}

# === Installation: PHP ===
function install_php() {
  sudo apt install -y software-properties-common
  sudo add-apt-repository -y ppa:ondrej/php
  sudo apt update
  sudo apt install -y php$PHP_VERSION php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql
  show_progress "✅ PHP $PHP_VERSION installed."
}

function configure_php() {
  PHP_INI=$(php -i | grep 'Loaded Configuration File' | awk '{print $5}')
  sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = $PHP_UPLOAD/" "$PHP_INI"
  sudo sed -i "s/memory_limit = .*/memory_limit = $PHP_MEMORY/" "$PHP_INI"
  show_progress "✅ PHP limits configured."
}

# === Installation: Database ===
function install_mysql() {
  if [[ $SQL_SERVER == "MariaDB" ]]; then
    sudo apt install -y mariadb-server
  else
    sudo apt install -y mysql-server
  fi
  sudo systemctl enable mysql
  sudo systemctl start mysql
  show_progress "✅ Database installed."
}

function generate_db() {
  DB_NAME="wp_$(openssl rand -hex 3)"
  DB_USER="user_$(openssl rand -hex 2)"
  DB_PASS=$(openssl rand -hex 8)
  sudo mysql -e "CREATE DATABASE $DB_NAME;"
  sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
  show_progress "✅ DB: $DB_NAME, User: $DB_USER created."
}

# === WordPress Setup ===
function install_wordpress() {
  cd "$DOMAIN_DIR"
  sudo wget -q https://wordpress.org/latest.tar.gz
  sudo tar -xzf latest.tar.gz --strip-components=1
  sudo rm latest.tar.gz
  sudo cp wp-config-sample.php wp-config.php
  sudo sed -i "s/database_name_here/$DB_NAME/" wp-config.php
  sudo sed -i "s/username_here/$DB_USER/" wp-config.php
  sudo sed -i "s/password_here/$DB_PASS/" wp-config.php
  show_progress "✅ WordPress installed at $DOMAIN_DIR."
}

# === Nginx or Apache Configuration ===
function configure_vhost() {
  if [[ $STACK == "LEMP" ]]; then
    cat <<EOF | sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null
server {
  listen 80;
  server_name $DOMAIN;
  root $DOMAIN_DIR;

  index index.php index.html;
  location / {
    try_files \$uri \$uri/ /index.php?\$args;
  }

  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
  }

  location ~ /\.ht {
    deny all;
  }
}
EOF
    sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
  else
    cat <<EOF | sudo tee /etc/apache2/sites-available/$DOMAIN.conf > /dev/null
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $DOMAIN_DIR

    <Directory $DOMAIN_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOF
    sudo a2ensite $DOMAIN.conf
    sudo systemctl reload apache2
  fi
  show_progress "✅ Virtual host configured."
}

# === SSL with retry ===
function setup_ssl() {
  sudo apt install -y certbot python3-certbot-${STACK,,}
  if [[ $STACK == "LEMP" ]]; then
    sudo certbot --nginx -d $DOMAIN || retry_ssl
  else
    sudo certbot --apache -d $DOMAIN || retry_ssl
  fi
}

function retry_ssl() {
  read -p "⚠️ SSL failed. Retry? [y/n]: " retry
  if [[ "$retry" == "y" ]]; then
    setup_ssl
  else
    echo "⚠️ Skipping SSL."
  fi
}

# === Summary ===
function final_output() {
  echo ""
  echo "🎉 WordPress site installed!"
  echo "URL: http://$DOMAIN"
  echo "DB Name: $DB_NAME"
  echo "DB User: $DB_USER"
  echo "DB Pass: $DB_PASS"
  echo ""
}

# === Ask to Install Another ===
function ask_install_another() {
  read -p "Do you want to install another WordPress site? (y/n): " again
  if [[ "$again" == "y" ]]; then
    bash "$0"
    exit 0
  else
    echo "🚀 Done!"
    exit 0
  fi
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
