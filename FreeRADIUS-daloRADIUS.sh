#!/bin/sh

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo "============= Update Server ================"
sudo apt update && sudo apt upgrade -y
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
sudo ufw enable 
sudo ufw reload

#--------------------------------------------------
# Set up the timezones
#--------------------------------------------------
# set the correct timezone on ubuntu
timedatectl set-timezone Africa/Kigali
timedatectl

# Install Apache
sudo apt -y install apache2 libapache2-mod-php
sudo systemctl start apache2.service
sudo systemctl enable apache2.service

# Install PHP
sudo apt -y install php php-gd php-common php-mail php-mail-mime php-mysql php-pear php-db php-mbstring php-xml php-curl

# Install MariaDB
sudo apt -y install mariadb-server mariadb-client
sudo systemctl start mariadb.service
sudo systemctl enable mariadb.service

# Configure Database for FreeRADIUS
sudo mysql_secure_installation

sudo mysql -uroot --password="" -e "CREATE DATABASE radius CHARACTER SET UTF8 COLLATE UTF8_BIN;"
sudo mysql -uroot --password="" -e "CREATE USER 'radiususer'@'%' IDENTIFIED BY 'G@s%w&rJ';"
sudo mysql -uroot --password="" -e "GRANT ALL PRIVILEGES ON radius.* TO 'radiususer'@'%';"
sudo mysql -uroot --password="" -e "FLUSH PRIVILEGES;"
sudo mysqladmin -uroot --password="" reload 2>/dev/null

sudo systemctl restart mysql.service

# Install FreeRADIUS
sudo apt policy freeradius -y
sudo apt -y install freeradius freeradius-mysql freeradius-utils

# Once installed, import the freeradius MySQL database schema with the following command:
sudo su -
sudo mysql -u root -p radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
sudo mysql -u root -p -e "use radius;show tables;"

# Create a soft link for sql module under
sudo ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/

#Run the following commands to create the Certificate Authority (CA) keys:
cd /etc/ssl/certs/
sudo openssl genrsa 2048 > ca-key.pem
sudo openssl req -sha1 -new -x509 -nodes -days 3650 -key ca-key.pem > ca-cert.pem

#Make the following changes as per your database:
sudo cat <<EOF > /etc/freeradius/3.0/mods-enabled/sql

sql {
driver = "rlm_sql_mysql"
dialect = "mysql"

        mysql {
                # If any of the files below are set, TLS encryption is enabled
                tls {
                        ca_file = "/etc/ssl/certs/ca-cert.pem"
                        ca_path = "/etc/ssl/certs/"
                        #certificate_file = "/etc/ssl/certs/private/client.crt"
                        #private_key_file = "/etc/ssl/certs/private/client.key"
                        cipher = "DHE-RSA-AES256-SHA:AES128-SHA"

                        tls_required = no
                        tls_check_cert = no
                        tls_check_cert_cn = no
                }

# Connection info:
server = "localhost"
port = 3306
login = "radius"
password = "G@s%w&rJ"

# Database table configuration for everything except Oracle
radius_db = "radius"
}

read_clients = yes
client_table = "nas"
EOF

# Set the proper permission
sudo chgrp -h freerad /etc/freeradius/3.0/mods-available/sql
sudo chown -R freerad:freerad /etc/freeradius/3.0/mods-enabled/sql

sudo systemctl restart freeradius
sudo systemctl status freeradius

# Install daloRADIUS
sudo apt -y install wget unzip
wget https://github.com/lirantal/daloradius/archive/master.zip
unzip master.zip
mv daloradius-master daloradius
cd daloradius


#Configuring daloradius
sudo mysql -u root -p radius < contrib/db/fr2-mysql-daloradius-and-freeradius.sql 
sudo mysql -u root -p radius < contrib/db/mysql-daloradius.sql

cd ..
sudo mv daloradius /var/www/html/

sudo chown -R www-data:www-data /var/www/html/daloradius/
sudo cp /var/www/html/daloradius/library/daloradius.conf.php.sample /var/www/html/daloradius/library/daloradius.conf.php
sudo chmod 664 /var/www/html/daloradius/library/daloradius.conf.php

sudo nano /var/www/html/daloradius/library/daloradius.conf.php

#Make the following changes that match your database:
sudo tee -a /var/www/html/daloradius/library/daloradius.conf.php <<EOF

$configValues['CONFIG_DB_HOST'] = 'localhost';
$configValues['CONFIG_DB_PORT'] = '3306';
$configValues['CONFIG_DB_USER'] = 'radius';
$configValues['CONFIG_DB_PASS'] = 'G@s%w&rJ';
$configValues['CONFIG_DB_NAME'] = 'radius';
EOF

# Import the daloRAIUS MySQL tables to the FreeRADIUS database
cd /var/www/html/daloradius/
sudo mysql -u root -p radius < /var/www/html/daloradius/contrib/db/fr2-mysql-daloradius-and-freeradius.sql
sudo mysql -u root -p radius < /var/www/html/daloradius/contrib/db/mysql-daloradius.sql

sudo chown -R www-data:www-data /var/www/html/daloradius/
sudo systemctl restart freeradius.service apache2

# Visit: 
clear
echo "access via http://localhost/daloradius/login.php"
echo "Username: administrator"
echo "Password: radius"

