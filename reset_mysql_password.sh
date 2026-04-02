#!/bin/bash
# MySQL Root Password Reset Script (MySQL 8 compatible)
# Run this from anywhere: bash reset_mysql_password.sh

# Auto-detect Homebrew prefix (Apple Silicon = /opt/homebrew, Intel = /usr/local)
BREW_PREFIX=$(brew --prefix)
MYSQL="$BREW_PREFIX/opt/mysql@8.0/bin/mysql"
MYSQLD="$BREW_PREFIX/opt/mysql@8.0/bin/mysqld"
DATADIR="$BREW_PREFIX/var/mysql"

echo "Homebrew prefix: $BREW_PREFIX"
echo "MySQL binary: $MYSQL"
echo "Data dir: $DATADIR"
echo ""

# Check binaries exist
if [ ! -f "$MYSQL" ]; then
  echo "ERROR: MySQL not found at $MYSQL"
  echo "Make sure MySQL 8.0 is installed: brew install mysql@8.0"
  exit 1
fi

echo "==> Step 1: Stopping MySQL..."
brew services stop mysql@8.0
sleep 2

echo "==> Step 2: Creating reset SQL file..."
echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '';" > /tmp/mysql_reset.sql

echo "==> Step 3: Starting MySQL with init-file to reset password..."
$MYSQLD --user=$(whoami) --datadir="$DATADIR" --init-file=/tmp/mysql_reset.sql &
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
