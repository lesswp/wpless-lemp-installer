#!/bin/bash

# Progress helper
progress() {
  echo -ne "$1"
  sleep 0.5
}

# Generate random database credentials
DB_NAME="wp_$(openssl rand -hex 4)"
DB_USER="user_$(openssl rand -hex 4)"
DB_PASS="$(openssl rand -base64 16)"
WP_DIR="/var/www/$DOMAIN"

# Root privilege check
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

clear
echo "=== LEMP + WordPress Installer ==="
read -p "Enter your domain name (e.g., example.com): " DOMAIN

echo -e "\nUpdating packages..."
progress "[###                     ]"
apt update -y >/dev/null && apt upgrade -y >/dev/null
progress "\r[###########             ]"

echo -e "\nInstalling Nginx..."
apt install nginx -y >/dev/null
progress "\r[###############         ]"

echo -e "\nInstalling MySQL..."
DEBIAN_FRONTEND=noninteractive apt install mysql-server -y >/dev/null
mysql_secure_installation <<EOF

y
n
y
y
y
EOF
progress "\r[###################     ]"

echo -e "\nInstalling PHP and modules..."
apt install php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip unzip curl -y >/dev/null
progress "\r[########################]"

echo -e "\nCreating MySQL Database & User..."
mysql -e "CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo -e "\nSetting up WordPress..."
mkdir -p $WP_DIR
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz
cp -a wordpress/. $WP_DIR
chown -R www-data:www-data $WP_DIR
chmod -R 755 $WP_DIR

cp $WP_DIR/wp-config-sample.php $WP_DIR/wp-config.php
sed -i "s/database_name_here/$DB_NAME/" $WP_DIR/wp-config.php
sed -i "s/username_here/$DB_USER/" $WP_DIR/wp-config.php
sed -i "s/password_here/$DB_PASS/" $WP_DIR/wp-config.php

# Add security keys
SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
echo "$SALT" | tee -a $WP_DIR/wp-config.php >/dev/null

echo -e "\nConfiguring Nginx for $DOMAIN..."
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
        fastcgi_pass unix:/run/php/php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

echo -e "\nInstalling Certbot SSL..."
apt install certbot python3-certbot-nginx -y >/dev/null
certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

echo -e "\nRestarting services..."
systemctl restart php*-fpm
systemctl restart nginx

echo -e "\n✅ WordPress has been successfully installed and configured!"
echo "👉 Visit: https://$DOMAIN"
echo "Complete the setup by entering your Site Title, Username, Email, and Password."
echo "🚀 Enjoy your WordPress site!"
