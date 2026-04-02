#!/bin/bash
# MySQL Root Password Reset Script (MySQL 8 compatible)
# Run this from anywhere: bash reset_mysql_password.sh

MYSQL=/opt/homebrew/opt/mysql@8.0/bin/mysql
MYSQLD=/opt/homebrew/opt/mysql@8.0/bin/mysqld

echo "==> Step 1: Stopping MySQL..."
brew services stop mysql@8.0
sleep 2

echo "==> Step 2: Creating reset SQL file..."
echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '';" > /tmp/mysql_reset.sql

echo "==> Step 3: Starting MySQL with init-file to reset password..."
$MYSQLD --user=$(whoami) --datadir=/opt/homebrew/var/mysql --init-file=/tmp/mysql_reset.sql &
sleep 6

echo "==> Step 4: Stopping temporary MySQL instance..."
pkill -f mysqld
sleep 2

echo "==> Step 5: Restarting MySQL normally..."
brew services start mysql@8.0
sleep 3

echo "==> Step 6: Testing connection (should print OK)..."
$MYSQL -u root -e "SELECT 'OK';"

echo ""
echo "If you see OK above, the password has been cleared successfully."
echo "You can now run the database setup commands without -p."
