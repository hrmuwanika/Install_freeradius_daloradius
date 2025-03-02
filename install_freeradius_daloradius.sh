#!/bin/sh

# Set default values for variables


#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo "============= Update Server ================"
sudo apt update && sudo apt -y upgrade
sudo apt autoremove -y

#----------------------------------------------------
# Disabling password authentication
#----------------------------------------------------
echo "Disabling password authentication ... "
sudo sed -i 's/#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config 
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo service sshd restart

#--------------------------------------------------
# Install and configure Firewall
#--------------------------------------------------
sudo apt -y install ufw

sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 8000/tcp
sudo ufw allow 1812:1813/udp

sudo ufw enable 
sudo ufw reload

#--------------------------------------------------
# Set up the timezones
#--------------------------------------------------
# set the correct timezone on ubuntu
timedatectl set-timezone Africa/Kigali
timedatectl

# Install Apache
sudo apt -y install apache2
sudo systemctl start apache2.service
sudo systemctl enable apache2.service

# Install PHP
sudo apt -y install php libapache2-mod-php php-gd php-common php-mail php-mail-mime php-mysql php-pear php-db php-mbstring php-xml php-curl php-zip rsyslog

# Install MariaDB
sudo apt -y install mariadb-server mariadb-client
sudo systemctl start mariadb.service
sudo systemctl enable mariadb.service

# Configure Database for FreeRADIUS
# sudo mariadb-secure-installation

# Install FreeRADIUS
sudo apt policy freeradius -y
sudo apt -y install freeradius freeradius-mysql freeradius-utils

cd /etc/freeradius/3.0/mods-config/sql/main/mysql
# Create radius database, import the freeradius MySQL database schema with the following command:
sudo mariadb -u root -p << MYSQLCREOF
CREATE DATABASE raddb;
CREATE USER 'raduser'@'localhost' IDENTIFIED BY 'radpass';
GRANT ALL PRIVILEGES ON raddb.* TO 'raduser'@'localhost';
FLUSH PRIVILEGES;

use raddb;
\. /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
show tables;
EXIT;
MYSQLCREOF

sudo systemctl restart mariadb.service

# Create a soft link for sql module under
sudo ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/

# Run the following commands to create the Certificate Authority (CA) keys:
# cd /etc/ssl/certs/
# sudo openssl genrsa 2048 > ca-key.pem
# sudo openssl req -sha1 -new -x509 -nodes -days 3650 -key ca-key.pem > ca-cert.pem

# Make the following changes as per your database:
sudo nano /etc/freeradius/3.0/mods-enabled/sql

sed -Ei '/^[\t\s#]*tls\s+\{/, /[\t\s#]*\}/ s/^/#/' /etc/freeradius/3.0/mods-enabled/sql

# Set the proper permission
sudo chgrp -h freerad /etc/freeradius/3.0/mods-available/sql
sudo chown -R freerad:freerad /etc/freeradius/3.0/mods-enabled/sql

sudo systemctl enable freeradius.service
sudo systemctl restart freeradius.service

# Install daloradius
cd /var/www/
sudo apt -y install git
git clone https://github.com/lirantal/daloradius.git

# Configuring daloradius
cd /var/www/daloradius/contrib/db/
sudo mariadb -u root -p << MYSQLCREOF
use raddb;
\. /var/www/daloradius/contrib/db/fr3-mariadb-freeradius.sql
\. /var/www/daloradius/contrib/db/mariadb-daloradius.sql
show tables;
EXIT;
MYSQLCREOF

sudo chown -R www-data:www-data /var/www/daloradius/
sudo chmod -R 755 /var/www/daloradius/

cd /var/www/daloradius/app/common/includes/
sudo cp daloradius.conf.php.sample daloradius.conf.php
sudo chown www-data:www-data daloradius.conf.php

# Make the following changes that match your database:
sudo nano daloradius.conf.php 
sudo chmod -R 664 daloradius.conf.php

chown www-data:www-data /var/www/daloradius/contrib/scripts/dalo-crontab

chown -R www-data:www-data /var/log/syslog
cd /var/www/daloradius/
mkdir -p var/{log,backup}
chown -R www-data:www-data var  
chmod -R 775 var

sudo tee /etc/apache2/ports.conf<<EOF
    Listen 80
    Listen 8000

  <IfModule ssl_module>
    Listen 443
  </IfModule>

  <IfModule mod_gnutls.c>
     Listen 443
  </IfModule>
EOF

sudo tee /etc/apache2/sites-available/operators.conf<<EOF
<VirtualHost *:8000>
        ServerAdmin operators@localhost
        DocumentRoot /var/www/daloradius/app/operators

    <Directory /var/www/daloradius/app/operators>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Directory /var/www/daloradius>
        Require all denied
    </Directory>

        ErrorLog \${APACHE_LOG_DIR}/daloradius/operators/error.log
        CustomLog \${APACHE_LOG_DIR}/daloradius/operators/access.log combined
</VirtualHost>
EOF

sudo tee /etc/apache2/sites-available/users.conf<<EOF
<VirtualHost *:80>
        ServerAdmin users@localhost
        DocumentRoot /var/www/daloradius/app/users

    <Directory /var/www/daloradius/app/users>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Directory /var/www/daloradius>
        Require all denied
    </Directory>

        ErrorLog \${APACHE_LOG_DIR}/daloradius/users/error.log
        CustomLog \${APACHE_LOG_DIR}/daloradius/users/access.log combined
</VirtualHost>
EOF

sudo a2ensite users.conf 
sudo a2ensite operators.conf
sudo a2dissite 000-default.conf

sudo mkdir /var/log/apache2/daloradius/
sudo mkdir /var/log/apache2/daloradius/users
sudo mkdir /var/log/apache2/daloradius/operators

sudo systemctl restart freeradius.service 
sudo systemctl restart apache2.service

# Visit: 
echo "access via http://localhost:8000/login.php"
echo "Username: administrator"
echo "Password: radius"

