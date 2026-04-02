#!/bin/bash
# MySQL 8.0 Complete Reinstall Script
# This wipes MySQL and reinstalls it fresh with no root password.
# Run with: bash reset_mysql_password.sh

BREW_PREFIX=$(brew --prefix)
MYSQL="$BREW_PREFIX/opt/mysql@8.0/bin/mysql"

echo "==> Step 1: Stopping MySQL service..."
brew services stop mysql@8.0
sleep 2

echo "==> Step 2: Kill any remaining MySQL processes..."
pkill -f mysqld 2>/dev/null || true
sleep 2

echo "==> Step 3: Uninstalling MySQL..."
brew uninstall mysql@8.0
sleep 2

echo "==> Step 4: Removing ALL leftover MySQL data files..."
sudo rm -rf "$BREW_PREFIX/var/mysql"
sudo rm -rf /tmp/mysql.sock
sudo rm -rf /tmp/mysql.sock.lock
sleep 1

echo "==> Step 5: Reinstalling MySQL 8.0..."
brew install mysql@8.0
sleep 3

echo "==> Step 6: Starting MySQL..."
brew services start mysql@8.0
sleep 5

echo "==> Step 7: Testing connection..."
if "$MYSQL" -u root -e "SELECT 'OK';" 2>/dev/null; then
  echo ""
  echo "SUCCESS! MySQL is ready with no password."
  echo "You can now run the database setup commands."
else
  echo "Trying alternate connection method..."
  if sudo "$MYSQL" -u root -e "SELECT 'OK';"; then
    echo ""
    echo "Connected via sudo. Setting password to empty..."
    sudo "$MYSQL" -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY ''; FLUSH PRIVILEGES;"
    echo "Done! Try: $MYSQL -u root"
  else
    echo ""
    echo "Check temp password in log:"
    grep -i 'temporary password' "$BREW_PREFIX/var/mysql/"*.err 2>/dev/null || echo "No temp password found in logs."
  fi
fi
