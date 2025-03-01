#!/bin/sh

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
sudo apt install -y ufw
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 8000/tcp
sudo ufw allow 1812/tcp
sudo ufw allow 1813/tcp
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
sudo apt -y install php libapache2-mod-php php-gd php-common php-mail php-mail-mime php-mysql php-pear php-db php-mbstring php-xml php-curl php-zip 

# Install MariaDB
sudo apt -y install mariadb-server mariadb-client
sudo systemctl start mariadb.service
sudo systemctl enable mariadb.service

# Configure Database for FreeRADIUS
# sudo mysql_secure_installation

sudo mysql -uroot --password="" -e "CREATE DATABASE radius;"
sudo mysql -uroot --password="" -e "CREATE USER 'radiususer'@'localhost' IDENTIFIED BY 'G@s%w&rJ';"
sudo mysql -uroot --password="" -e "GRANT ALL PRIVILEGES ON radius.* TO 'radiususer'@'localhost';"
sudo mysql -uroot --password="" -e "FLUSH PRIVILEGES;"
sudo mysqladmin -uroot --password="" reload 2>/dev/null

sudo systemctl restart mysql.service

# Install FreeRADIUS
sudo apt policy freeradius -y
sudo apt -y install freeradius freeradius-mysql freeradius-utils
sudo systemctl start freeradius
sudo systemctl enable freeradius

# Once installed, import the freeradius MySQL database schema with the following command:
sudo mysql -u root -p radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
sudo mysql -u root -p -e "use radius;show tables;"

# Create a soft link for sql module under
sudo ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/*/mods-enabled/

#Run the following commands to create the Certificate Authority (CA) keys:
cd /etc/ssl/certs/
#sudo openssl genrsa 2048 > ca-key.pem
#sudo openssl req -sha1 -new -x509 -nodes -days 3650 -key ca-key.pem > ca-cert.pem

#Make the following changes as per your database:
sudo nano /etc/freeradius/3.0/mods-enabled/sql

# Set the proper permission
sudo chgrp -h freerad /etc/freeradius/3.0/mods-available/sql
sudo chown -R freerad:freerad /etc/freeradius/3.0/mods-enabled/sql

sudo systemctl restart freeradius.service

# Install daloRADIUS
cd /usr/src/
sudo apt -y install git
git clone https://github.com/lirantal/daloradius.git

# Configuring daloradius
mysql -u root -p radius < daloradius/contrib/db/fr3-mariadb-freeradius.sql
mysql -u root -p radius < daloradius/contrib/db/mariadb-daloradius.sql

sudo mv daloradius /var/www/html/

sudo chown -R www-data:www-data /var/www/html/daloradius
sudo chmod -R 755 /var/www/html/daloradius

cd /var/www/html/daloradius/app/common/includes/
sudo cp daloradius.conf.php.sample daloradius.conf.php
sudo chown www-data:www-data daloradius.conf.php

#Make the following changes that match your database:
sudo tee -a /var/www/html/daloradius/library/daloradius.conf.php <<EOF

$configValues['CONFIG_DB_ENGINE'] = 'mysqli';
$configValues['CONFIG_DB_HOST'] = 'localhost';
$configValues['CONFIG_DB_PORT'] = '3306';
$configValues['CONFIG_DB_USER'] = 'radiususer';
$configValues['CONFIG_DB_PASS'] = 'G@s%w&rJ';
$configValues['CONFIG_DB_NAME'] = 'radius';
EOF

sudo chmod 664 /var/www/html/daloradius/library/daloradius.conf.php

cd /var/www/html/daloradius/
sudo mkdir -p var/{log,backup}
sudo chown -R www-data:www-data var

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
    DocumentRoot /var/www/html/daloradius/app/operators

    <Directory /var/www/html/daloradius/app/operators>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Directory /var/www/html/daloradius>
        Require all denied
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/daloradius/operators/error.log
    CustomLog \${APACHE_LOG_DIR}/daloradius/operators/access.log combined
</VirtualHost>
EOF

sudo tee /etc/apache2/sites-available/users.conf<<EOF
<VirtualHost *:80>
    ServerAdmin users@localhost
    DocumentRoot /var/www/html/daloradius/app/users

    <Directory /var/www/html/daloradius/app/users>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Directory /var/www/html/daloradius>
        Require all denied
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/daloradius/users/error.log
    CustomLog \${APACHE_LOG_DIR}/daloradius/users/access.log combined
</VirtualHost>
EOF

sudo a2ensite users.conf 
sudo a2ensite operators.conf
sudo a2dissite 000-default.conf
sudo mkdir /var/log/apache2/daloradius/users
sudo mkdir /var/log/apache2/daloradius/operators

sudo chown -R www-data:www-data /var/www/html/daloradius/
sudo systemctl restart freeradius.service 
sudo systemctl restart apache2.service

# Visit: 
clear
echo "access via http://localhost/daloradius/login.php"
echo "Username: administrator"
echo "Password: radius"

