#!/bin/bash

# Dừng chương trình ngay lập tức nếu có lỗi xảy ra
set -e

# Cập nhật và cài đặt các gói phần mềm cần thiết
echo "Updating and installing necessary packages..."
sudo apt update && sudo apt upgrade -y && \
    sudo apt install -y apt-utils apache2 mariadb-server php mariadb-client php-mysql php-mysqli php-gd \
    libapache2-mod-php nano apt-transport-https gnupg2 g++ flex bison curl apache2-dev doxygen libyajl-dev ssdeep \
    lua5.2 liblua5.2-dev lua-posix lua-socket libgeoip-dev libtool dh-autoreconf libcurl4-gnutls-dev libxml2 libpcre++-dev \
    libpcre2-dev libxml2-dev libjansson-dev git wget tar autoconf automake pkg-config clamav clamav-daemon logrotate libssl-dev \
    zlib1g-dev build-essential libmaxminddb-dev luajit libluajit-5.1-dev perl libperl-dev checkinstall cmake valgrind \
    libbz2-dev libjson-c-dev libboost-all-dev libpcre3-dev libsqlite3-dev libprotobuf-dev libzmq3-dev 


# Thêm GPG key và repo của Elasticsearch để cài đặt Filebeat và Packetbeat
echo "Adding Elasticsearch GPG key and repository..."
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
sudo apt install -y filebeat packetbeat libpcap0.8

# Clone và xây dựng ModSecurity
echo "Cloning and building ModSecurity..."
git clone https://github.com/owasp-modsecurity/ModSecurity.git
cd ModSecurity
git submodule init
git submodule update --recursive
chmod +x build.sh
./build.sh
./configure
make
sudo make install
cd ..

# Cài đặt ModSecurity-Apache Connector
echo "Cloning and building ModSecurity-Apache connector..."
git clone https://github.com/SpiderLabs/ModSecurity-apache.git
cd ModSecurity-apache
chmod +x autogen.sh
./autogen.sh
./configure --with-libmodsecurity=/usr/local/modsecurity/
make
sudo make install

# Load ModSecurity vào Apache
echo "Loading ModSecurity module into Apache..."
echo "LoadModule security3_module /usr/lib/apache2/modules/mod_security3.so" | sudo tee -a /etc/apache2/apache2.conf
cd ..

# Cấu hình ModSecurity
echo "Configuring ModSecurity..."
sudo mkdir /etc/apache2/modsecurity.d
sudo cp ModSecurity/modsecurity.conf-recommended /etc/apache2/modsecurity.d/modsecurity.conf
sudo cp ModSecurity/unicode.mapping /etc/apache2/modsecurity.d/
sudo sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/apache2/modsecurity.d/modsecurity.conf

# Cài đặt và cấu hình OWASP CRS
echo "Installing OWASP CRS..."
git clone https://github.com/coreruleset/coreruleset.git /etc/apache2/modsecurity.d/owasp-crs
sudo cp /etc/apache2/modsecurity.d/owasp-crs/crs-setup.conf.example /etc/apache2/modsecurity.d/owasp-crs/crs-setup.conf

# Cập nhật file cấu hình Apache và ModSecurity
echo "Updating Apache and ModSecurity configuration files..."
sudo mv /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/000-default.conf.old
sudo cp ./confModsecurity/000-default.conf /etc/apache2/sites-available/
sudo cp ./confModsecurity/modsec_rules.conf /etc/apache2/modsecurity.d/

#copy source web
sudo cp -r ./src/WEB/* /var/www/html/
sudo cp -r ./src/web2/ /var/www/html/
sudo rm -rf /var/www/html/index.html
sudo chown -R www-data:www-data /var/www/html/*

# Cài đặt phpMyAdmin
echo "Installing phpMyAdmin..."
sudo apt install -y phpmyadmin

# Cấu hình phpMyAdmin với Apache
echo "Configuring phpMyAdmin for Apache..."
# Tạo liên kết tượng trưng cho phpMyAdmin trong thư mục /var/www/html
sudo ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin

# Cấu hình phpMyAdmin sử dụng MariaDB
echo "Configuring phpMyAdmin with MariaDB..."
# Sửa file cấu hình phpMyAdmin để nó sử dụng MariaDB
sudo sed -i "s/\$cfg\['Servers'\]\[\$i\]\['host'\] = 'localhost';/\$cfg\['Servers'\]\[\$i\]\['host'\] = '127.0.0.1';/" /etc/phpmyadmin/config.inc.php
# Thêm quyền cho apache để truy cập thư mục phpMyAdmin
sudo chown -R www-data:www-data /var/www/html/phpmyadmin
sudo systemctl restart apache2

#stop clamav-freshclam
sudo systemctl stop clamav-freshclam
# Cấu hình ClamAV
echo "Configuring ClamAV..."
sudo sed -i 's/^Example/#Example/' /etc/clamav/clamd.conf
sudo sed -i 's/^#LocalSocket \/var\/run\/clamav\/clamd.ctl/LocalSocket \/var\/run\/clamav\/clamd.ctl/' /etc/clamav/clamd.conf
echo "ConcurrentDatabaseReload no" | sudo tee -a /etc/clamav/clamd.conf
echo "TestDatabases no" | sudo tee -a /etc/clamav/freshclam.conf

# Tạo file log cho ClamAV và cấp quyền
echo "Creating ClamAV log and setting permissions..."
sudo touch /var/log/clamav/clamav.log
sudo chown clamav:clamav /var/log/clamav/clamav.log

# Cập nhật cơ sở dữ liệu ClamAV
echo "Updating ClamAV database..."
sudo freshclam

# Cấu hình logrotate cho ClamAV
echo "Configuring logrotate for ClamAV..."
sudo cp ./clamav-logrotate.conf /etc/logrotate.d/clamav

#cấu hình cho mariadb
sudo cp ./my_custom.cnf /etc/mysql/mariadb.conf.d/99-custom.cnf

# Cấu hình các dịch vụ khởi động cùng hệ thống
echo "Enabling services to start on boot..."
sudo systemctl enable apache2
sudo systemctl enable mariadb
sudo systemctl enable clamav-daemon
sudo systemctl enable filebeat

# Mở cổng 80 và 3310
echo "Configuring firewall..."
sudo ufw allow 80/tcp
sudo ufw allow 3310/tcp

# Khởi động Apache
echo "Starting Apache..."
sudo systemctl start apache2
sudo systemctl restart apache2


# Khởi động MariaDB
echo "Starting MariaDB..."
sudo systemctl start mariadb
sudo systemctl restart mariadb


# Khởi động ClamAV Daemon
echo "Starting ClamAV daemon..."
sudo systemctl start clamav-daemon

# Khởi động Filebeat
echo "Starting Filebeat..."
sudo systemctl start filebeat

# (Tuỳ chọn) Khởi động Packetbeat nếu cần
# echo "Starting Packetbeat..."
# sudo systemctl start packetbeat

# Kiểm tra trạng thái MariaDB và khởi động nếu cần
echo "Checking MariaDB status..."
if ! systemctl is-active --quiet mariadb; then
    echo "MariaDB is not running. Starting MariaDB..."
    sudo systemctl start mariadb
fi

# Thực thi file initWebTD.sql để triển khai database và user
echo "Running initWebTD.sql script..."

# Kiểm tra xem file initWebTD.sql có tồn tại không
if [ ! -f "$(pwd)/initWebTD.sql" ]; then
    echo "initWebTD.sql file not found! Exiting..."
    exit 1
fi

# Thực thi file SQL với MySQL/MariaDB
sudo mysql -u root -e "source $(pwd)/initWebTD.sql"

# Kiểm tra xem có lỗi không và báo kết quả
if [ $? -eq 0 ]; then
    echo "Database setup completed successfully!"
else
    echo "Error during database setup."
    exit 1
fi

# Kết thúc
echo "Server setup complete!"
